"""Package only the indicator, documentation, presets and developer test sources."""
import hashlib
import json
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parent
files = [
    "AurumConfirmation.ex5", "AurumConfirmation.mq5", "AurumCore.mqh",
    "README.md", "CHANGELOG.md", "compile.log", "build_release.py",
    "presets/Scalping-M5.set", "presets/Longer-Trades-H1.set",
    "tests/core_tests.cpp", "tests/run-tests.cmd", "tests/run_tests.py",
    "tests/test-results.txt",
]
log = (root / "compile.log").read_text(encoding="utf-16")
assert "0 errors, 0 warnings" in log, "Compilation did not pass"
assert (root / "AurumConfirmation.ex5").stat().st_mtime >= max(
    (root / p).stat().st_mtime for p in ("AurumConfirmation.mq5", "AurumCore.mqh")
), "Compiled indicator is older than its source"
assert "773 checks, 0 failures" in (root / "tests/test-results.txt").read_text()
manifest = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in files}
(root / "SHA256.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
archive = root / "AurumConfirmation-MT5-v2.zip"
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as release:
    for p in files + ["SHA256.json"]:
        release.write(root / p, p)
with zipfile.ZipFile(archive) as release:
    assert release.testzip() is None
    for p, digest in manifest.items():
        assert hashlib.sha256(release.read(p)).hexdigest() == digest
print(f"Verified release: {archive}\n{len(files) + 1} files, {archive.stat().st_size} bytes")
