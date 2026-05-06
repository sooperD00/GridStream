"""
Regression test for Sprint-1 §6 bug: mypy must run in strict mode when
invoked with this package's pyproject.toml. If this test fails, someone
removed or weakened the [tool.mypy] block in
packages/standard-service-stub/pyproject.toml. Restore it.
"""

import subprocess
import sys
from pathlib import Path

UNTYPED_CANARY = "def explode(x): return x.upper()\n"


def test_mypy_strict_rejects_untyped_def(tmp_path: Path) -> None:
    canary = tmp_path / "canary.py"
    canary.write_text(UNTYPED_CANARY)

    package_dir = Path(__file__).resolve().parent.parent
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "mypy",
            "--config-file",
            str(package_dir / "pyproject.toml"),
            str(canary),
        ],
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0, (
        f"mypy accepted untyped def — strict mode is NOT active.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
