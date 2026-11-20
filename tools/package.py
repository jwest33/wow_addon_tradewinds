"""Builds the release zip: dist/Deckhand-<version>.zip, holding a Deckhand/
folder with only what the game loads (the .toc, every file it lists,
Bindings.xml, Art/, and the licence and changelog if present).

    python tools/package.py            # build (runs the tests first)
    python tools/package.py --no-tests

The tests, tools, plans and the translators' template (Locales/enUS.lua)
stay out. Unzip into Interface/AddOns to install. The same list is in
.pkgmeta for the CurseForge / Wago packager.
"""
import pathlib
import re
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
NAME = "Deckhand"
EXTRA = ["Bindings.xml", "LICENSE", "LICENSE.txt", "CHANGELOG.md"]


def toc():
    text = (ROOT / f"{NAME}.toc").read_text(encoding="utf-8")
    version = re.search(r"^## Version:\s*(\S+)", text, re.M).group(1)
    files = [line.strip().replace("\\", "/") for line in text.splitlines()
             if line.strip() and not line.startswith("#")]
    return version, files


def main():
    if "--no-tests" not in sys.argv:
        r = subprocess.run([sys.executable, str(ROOT / "tests" / "run_tests.py")], cwd=ROOT)
        if r.returncode != 0:
            sys.exit("tests failed: no package built")
    version, files = toc()
    missing = [f for f in files if not (ROOT / f).is_file()]
    if missing:
        sys.exit("files in the .toc that don't exist: " + ", ".join(missing))
    ship = [f"{NAME}.toc"] + files
    ship += [f for f in EXTRA if (ROOT / f).is_file()]
    ship += sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "Art").glob("*.tga"))
    # every texture the code names is shipped
    code = "\n".join((ROOT / f).read_text(encoding="utf-8") for f in files if f.endswith(".lua"))
    arts = {p.stem for p in (ROOT / "Art").glob("*.tga")}
    named = set(re.findall(r'UI\.ART \.\. "(\w+)"', code))
    unknown = sorted(n for n in named if n not in arts and not n.endswith("_"))
    if unknown:
        sys.exit("textures the code uses that aren't in Art/: " + ", ".join(unknown))
    out = ROOT / "dist" / f"{NAME}-{version}.zip"
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for f in ship:
            z.write(ROOT / f, f"{NAME}/{f}")
    size = out.stat().st_size
    print(f"{out.relative_to(ROOT)}: {len(ship)} files, {size / 1024:.0f} KB")


if __name__ == "__main__":
    main()
