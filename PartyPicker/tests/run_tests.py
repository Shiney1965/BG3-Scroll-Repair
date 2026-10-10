"""Runs the Party Picker server scenarios outside the game.

Needs Python 3 and the `lupa` package (pip install lupa), which embeds Lua 5.4,
the same major Lua version Script Extender's own scripts are written for.

    python3 tests/run_tests.py
"""
import glob
import os
import sys

from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
LUA_ROOT = os.path.join(HERE, "..", "src", "Mods", "PartyPicker", "ScriptExtender", "Lua")


def compile_all(lua):
    ok = True
    for path in sorted(glob.glob(os.path.join(LUA_ROOT, "**", "*.lua"), recursive=True)):
        with open(path, encoding="utf-8") as f:
            result = lua.globals().load(f.read(), "@" + os.path.relpath(path, LUA_ROOT))
        if isinstance(result, tuple) and result[0] is None:
            print("SYNTAX:", result[1])
            ok = False
    return ok


def main():
    lua = lua54.LuaRuntime()
    if not compile_all(lua):
        return 1
    g = lua.globals()
    g.LUA_ROOT = LUA_ROOT.replace("\\", "/")
    g.TEST_ROOT = HERE.replace("\\", "/")
    try:
        lua.execute('dofile(TEST_ROOT .. "/test_server.lua")')
    except Exception as exc:  # lupa raises LuaError
        print(exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
