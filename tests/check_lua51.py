"""Checks the addon under Lua 5.1, the game's Lua, through lupa.

    python tests/check_lua51.py

Compiles every file the .toc lists with loadstring, then runs the Lua tests in a Lua 5.1
runtime as well. Run it from the repository root. Needs: pip install lupa
"""
import sys
from pathlib import Path

from lupa import lua51

root = Path(__file__).resolve().parent.parent
toc = (root / "SpellDamageInfo.toc").read_text(encoding="utf-8")
files = [line.strip() for line in toc.splitlines() if line.strip() and not line.startswith("##")]

failed = 0
rt = lua51.LuaRuntime()
print("runtime:", rt.eval("_VERSION"))
compile_ = rt.eval("function(src, name) local f, err = loadstring(src, name); return f ~= nil, err end")
for name in files:
    ok, err = compile_((root / name).read_bytes(), "@" + name)
    print(("OK   " if ok else "FAIL ") + name + ("" if ok else ": " + str(err)))
    failed += 0 if ok else 1

# Python sets the C library's character-type locale from Windows (a code page such as 1252);
# the game may not. Run the tests under that locale and under plain "C": string.lower and the
# %a/%d pattern classes follow it, and the parser must give the same answers either way.
for ctype in ("process default", "C"):
    for test in ("tests/test_parser.lua", "tests/test_weapon.lua", "tests/test_corpus.lua", "tests/test_client_texts.lua",
                 "tests/test_reduction.lua", "tests/test_estimate.lua", "tests/test_coefficients.lua", "tests/test_smoke.lua"):
        rt = lua51.LuaRuntime()
        if ctype == "C":
            rt.execute('os.setlocale("C", "ctype")')
        run = rt.eval(
            "function(path) arg = {} os.exit = function(code) error('exit ' .. tostring(code), 0) end"
            " local f, err = loadfile(path) if not f then return false, err end"
            " local ok, e = pcall(f) return ok, e end"
        )
        ok, err = run(test)
        where = "Lua 5.1, ctype " + str(rt.eval('os.setlocale(nil, "ctype")'))
        print(("OK   " if ok else "FAIL ") + test + " (" + where + ")" + ("" if ok else ": " + str(err)))
        failed += 0 if ok else 1

sys.exit(1 if failed else 0)
