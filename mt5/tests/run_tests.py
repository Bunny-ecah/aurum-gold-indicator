"""Execute the compiled, shared decision core, not a Python reimplementation."""
import ctypes
from pathlib import Path

directory = Path(__file__).resolve().parent
library = ctypes.CDLL(str(directory / "core_tests.dll"))
result = library.RunTests()
summary = f"{library.CheckCount()} checks, {library.FailureCount()} failures"
print(summary)
(directory / "test-results.txt").write_text(summary + "\n", encoding="utf-8")
raise SystemExit(result)
