"""Read and write Baldur's Gate 3 .pak files (LSPK version 18).

The layout follows LSLib (github.com/Norbyte/lslib), LSLib/LS/PackageFormat.cs
and PackageWriter.cs (PackageWriter_V15 with LSPKHeader16 + FileEntry18):

  0x00  uint32  signature 'LSPK' (0x4B50534C)
  0x04  LSPKHeader16 (36 bytes, packed):
          uint32 Version (18), uint64 FileListOffset, uint32 FileListSize,
          uint8 Flags, uint8 Priority, uint8[16] Md5, uint16 NumParts
  0x28  file data; with non-solid packages each file is followed by 0xAD
        padding so that (position - 40) is a multiple of 64
  FileListOffset:
          uint32 NumFiles, uint32 CompressedSize,
          LZ4 block of NumFiles x FileEntry18 (272 bytes each):
            char[256] Name (NUL-terminated, '/' separators)
            uint32 OffsetLow, uint16 OffsetHigh, uint8 ArchivePart,
            uint8 Flags (low nibble method: 0 none, 1 zlib, 2 LZ4, 3 zstd;
                         high nibble level: 0x10 fast, 0x20 default, 0x40 max),
            uint32 SizeOnDisk, uint32 UncompressedSize (0 when not compressed)

MD5 (PackageWriter.ComputeArchiveHash): MD5 over every file's uncompressed
bytes in package order, then each byte incremented by 1. Written only when
the build asks for it; otherwise 16 zero bytes.

Usage:
  python3 lspk.py list <pak>
  python3 lspk.py extract <pak> <out_dir>
  python3 lspk.py create <src_dir> <pak> [--hash]
"""
import hashlib
import os
import struct
import sys
import zlib

import lz4.block

SIGNATURE = 0x4B50534C
VERSION = 18
HEADER = struct.Struct("<IQIBB16sH")          # LSPKHeader16, 36 bytes
ENTRY = struct.Struct("<256sIHBBII")          # FileEntry18, 272 bytes
PAD = 0x40
DATA_START = 4 + HEADER.size                  # 40
METHOD_NONE, METHOD_ZLIB, METHOD_LZ4 = 0, 1, 2
LEVEL_DEFAULT = 0x20
NO_COMPRESS_EXT = {".gts", ".gtp", ".wem", ".bnk", ".bk2"}  # PackageWriter.CanCompressFile


def read_pak(path):
    with open(path, "rb") as f:
        data = f.read()
    sig, = struct.unpack_from("<I", data, 0)
    if sig != SIGNATURE:
        raise ValueError("not an LSPK v15+ package (signature at offset 0 missing)")
    version, list_off, list_size, flags, priority, md5, parts = HEADER.unpack_from(data, 4)
    count, csize = struct.unpack_from("<II", data, list_off)
    raw = lz4.block.decompress(data[list_off + 8:list_off + 8 + csize], uncompressed_size=count * ENTRY.size)
    files = []
    for i in range(count):
        name, off1, off2, part, fflags, on_disk, unc = ENTRY.unpack_from(raw, i * ENTRY.size)
        name = name.split(b"\0", 1)[0].decode("utf-8")
        off = off1 | (off2 << 32)
        blob = data[off:off + on_disk]
        method = fflags & 0x0F
        if method == METHOD_NONE:
            content = blob
        elif method == METHOD_LZ4:
            content = lz4.block.decompress(blob, uncompressed_size=unc)
        elif method == METHOD_ZLIB:
            content = zlib.decompress(blob)
        else:
            raise ValueError(f"{name}: unsupported compression method {method}")
        files.append({"name": name, "offset": off, "part": part, "flags": fflags,
                      "size_on_disk": on_disk, "uncompressed": unc, "content": content})
    header = {"version": version, "file_list_offset": list_off, "file_list_size": list_size,
              "flags": flags, "priority": priority, "md5": md5, "parts": parts,
              "file_list_compressed": csize, "total_size": len(data)}
    return header, files


def archive_md5(contents):
    h = hashlib.md5()
    for c in contents:
        h.update(c)
    return bytes((b + 1) & 0xFF for b in h.digest())


def write_pak(path, files, flags=0, priority=0, with_hash=False):
    """files: list of (name_in_pak, bytes) in the order to write."""
    out = bytearray(DATA_START)  # header placeholder
    entries = []
    for name, content in files:
        name = name.replace("\\", "/")
        enc = name.encode("utf-8")
        if len(enc) >= 256:
            raise ValueError(f"path too long for a pak entry: {name}")
        ext = os.path.splitext(name)[1].lower()
        if ext in NO_COMPRESS_EXT or len(content) == 0:
            blob, fflags, unc = content, 0, 0
        else:
            blob = lz4.block.compress(content, mode="high_compression", compression=10, store_size=False)
            fflags, unc = METHOD_LZ4 | LEVEL_DEFAULT, len(content)
        off = len(out)
        out += blob
        if not (flags & 0x04):  # PackageFlags.Solid
            pad = (PAD - (len(out) - DATA_START) % PAD) % PAD
            out += b"\xAD" * pad
        entries.append(ENTRY.pack(enc, off & 0xFFFFFFFF, (off >> 32) & 0xFFFF, 0, fflags, len(blob), unc))
    raw = b"".join(entries)
    clist = lz4.block.compress(raw, mode="high_compression", compression=10, store_size=False)
    list_off = len(out)
    out += struct.pack("<II", len(files), len(clist)) + clist
    list_size = len(out) - list_off
    md5 = archive_md5([c for _, c in files]) if with_hash else bytes(16)
    struct.pack_into("<I", out, 0, SIGNATURE)
    HEADER.pack_into(out, 4, VERSION, list_off, list_size, flags, priority, md5, 1)
    with open(path, "wb") as f:
        f.write(out)


def collect(src_dir):
    """Files under src_dir as (pak path, bytes). Order matches the packages
    Divine produced for Scroll Repair: within each folder, files first
    (ordinal by name), then subfolders (ordinal by name)."""
    items = []

    def walk(folder, prefix):
        entries = sorted(os.listdir(folder))
        for n in entries:
            full = os.path.join(folder, n)
            if os.path.isfile(full):
                with open(full, "rb") as f:
                    items.append((prefix + n, f.read()))
        for n in entries:
            full = os.path.join(folder, n)
            if os.path.isdir(full):
                walk(full, prefix + n + "/")

    walk(src_dir, "")
    return items


def main(argv):
    if len(argv) >= 2 and argv[0] == "list":
        h, files = read_pak(argv[1])
        print({k: (v.hex() if isinstance(v, bytes) else v) for k, v in h.items()})
        for f in files:
            print(f"{f['flags']:#04x} {f['size_on_disk']:>7} {f['uncompressed']:>7} @{f['offset']:<7} {f['name']}")
        return 0
    if len(argv) == 3 and argv[0] == "extract":
        _, files = read_pak(argv[1])
        for f in files:
            dest = os.path.join(argv[2], *f["name"].split("/"))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "wb") as o:
                o.write(f["content"])
        return 0
    if len(argv) >= 3 and argv[0] == "create":
        write_pak(argv[2], collect(argv[1]), with_hash="--hash" in argv)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
