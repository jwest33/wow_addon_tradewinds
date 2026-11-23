"""Runs the Tradewinds tests in Lua 5.1 (the version WoW uses).

    pip install lupa
    python tests/run_tests.py           # engine, UI, PvP, saved data and translations
    python tests/run_tests.py engine    # just one
    python tests/run_tests.py saves     # saved data: real saves in tests/saves/, the set-aside store, the previous version
    python tests/run_tests.py locale write   # regenerate Locales/enUS.lua, the translators' template
    python tests/run_tests.py balance ai|ladder|cards ...   # on demand, see tests/balance.lua

tests/saves/ holds copies of real saved files (SavedVariables/Tradewinds.lua,
renamed *.lua). It's kept out of git: they have character names in them.
"""
import io
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

import lupa.lua51 as lupa

root = pathlib.Path(__file__).resolve().parent.parent
suites = sys.argv[1:] or ["engine", "ui", "pvp", "saves", "locale"]
args = []
if suites[0] in ("balance", "locale") and len(suites) > 1:
    suites, args = [suites[0]], suites[1:]
locale_files = sorted(p.name for p in (root / "Locales").glob("*.lua"))


def toc_version(text):
    m = re.search(r"^## Version:\s*(\S+)", text, re.M)
    return m.group(1) if m else None


def previous_version():
    """The files of the last commit whose .toc has another version than the
    working tree's (the version players have now), exported to a temporary
    folder. Returns (folder, version), or (None, None) without git."""
    try:
        current = toc_version((root / "Tradewinds.toc").read_text(encoding="utf-8"))

        def git(*a, text=True):
            out = subprocess.run(["git", "-C", str(root), *a], capture_output=True, check=True).stdout
            return out.decode("utf-8", "replace") if text else out

        for commit in git("log", "--format=%H", "--", "Tradewinds.toc").split():
            version = toc_version(git("show", f"{commit}:Tradewinds.toc"))
            if version and version != current:
                folder = pathlib.Path(tempfile.mkdtemp(prefix="tradewinds-previous-"))
                with tarfile.open(fileobj=io.BytesIO(git("archive", commit, text=False))) as tar:
                    tar.extractall(folder)
                return folder, version
    except (OSError, subprocess.CalledProcessError) as e:
        print("no previous version to test against:", e)
    return None, None


def run(name, **globals_):
    lua = lupa.LuaRuntime()
    g = lua.globals()
    g.ROOT = root.as_posix()
    g.ARGS = lua.table_from(args)
    g.LOCALE_FILES = lua.table_from(locale_files)
    for k, v in globals_.items():
        g[k] = lua.table_from(v) if isinstance(v, list) else v
    lua.execute((root / "tests" / f"{name}.lua").read_text(encoding="utf-8"))
    return bool(g.RESULT)


failed = False
for name in suites:
    if not (root / "tests" / f"{name}.lua").exists():
        continue
    print(f"== {name} ==")
    if name == "saves":
        folder = root / "tests" / "saves"
        saves = sorted(p.name for p in folder.glob("*.lua")) if folder.is_dir() else []
        old, version = previous_version()
        print(f"previous version: {version or 'none'}")
        try:
            extra = {"SAVE_FILES": saves}
            if old:
                extra["OLD_ROOT"] = old.as_posix()
            failed = run(name, **extra) or failed
        finally:
            if old:
                shutil.rmtree(old, ignore_errors=True)
        continue
    failed = run(name) or failed
    if name == "locale" and not args:
        # the addon in every language, English included
        codes = ["enUS"] + [f[:-4] for f in locale_files if f not in ("Locale.lua", "enUS.lua")]
        for code in codes:
            failed = run("locale_smoke", LOCALE=code) or failed
sys.exit(1 if failed else 0)
