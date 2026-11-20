"""Runs the Tradewinds tests in Lua 5.1 (the version WoW uses).

    pip install lupa
    python tests/run_tests.py           # engine, UI, PvP and translations
    python tests/run_tests.py engine    # just one
    python tests/run_tests.py locale write   # regenerate Locales/enUS.lua, the translators' template
    python tests/run_tests.py balance ai|ladder|cards ...   # on demand, see tests/balance.lua
"""
import pathlib
import sys

import lupa.lua51 as lupa

root = pathlib.Path(__file__).resolve().parent.parent
suites = sys.argv[1:] or ["engine", "ui", "pvp", "locale"]
args = []
if suites[0] in ("balance", "locale") and len(suites) > 1:
    suites, args = [suites[0]], suites[1:]
locale_files = sorted(p.name for p in (root / "Locales").glob("*.lua"))


def run(name, **globals_):
    lua = lupa.LuaRuntime()
    g = lua.globals()
    g.ROOT = root.as_posix()
    g.ARGS = lua.table_from(args)
    g.LOCALE_FILES = lua.table_from(locale_files)
    for k, v in globals_.items():
        g[k] = v
    lua.execute((root / "tests" / f"{name}.lua").read_text(encoding="utf-8"))
    return bool(g.RESULT)


failed = False
for name in suites:
    if not (root / "tests" / f"{name}.lua").exists():
        continue
    print(f"== {name} ==")
    failed = run(name) or failed
    if name == "locale" and not args:
        # the addon in every language, English included
        codes = ["enUS"] + [f[:-4] for f in locale_files if f not in ("Locale.lua", "enUS.lua")]
        for code in codes:
            failed = run("locale_smoke", LOCALE=code) or failed
sys.exit(1 if failed else 0)
