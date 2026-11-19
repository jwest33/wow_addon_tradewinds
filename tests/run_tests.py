"""Runs the Deckhand tests in Lua 5.1 (the version WoW uses).

    pip install lupa
    python tests/run_tests.py           # engine + UI smoke test
    python tests/run_tests.py engine    # just one
"""
import pathlib
import sys

import lupa.lua51 as lupa

root = pathlib.Path(__file__).resolve().parent.parent
suites = sys.argv[1:] or ["engine", "ui"]
failed = False
for name in suites:
    path = root / "tests" / f"{name}.lua"
    if not path.exists():
        continue
    print(f"== {name} ==")
    lua = lupa.LuaRuntime()
    lua.globals().ROOT = root.as_posix()
    lua.execute(path.read_text(encoding="utf-8"))
    failed = failed or bool(lua.globals().RESULT)
sys.exit(1 if failed else 0)
