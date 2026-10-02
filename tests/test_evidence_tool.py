"""未预期 SQL 错误和显式 FAIL 都必须阻止生成证据图片。"""

import os
import subprocess
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATABASE = os.environ.get("DB_LAB_TEST_DATABASE", "")


@unittest.skipUnless(DATABASE, "Set DB_LAB_TEST_DATABASE for evidence tool integration")
class EvidenceToolTests(unittest.TestCase):
    def assert_capture_fails(self, fixture: str, expected: str) -> None:
        name = "rejected_" + uuid.uuid4().hex[:12]
        image = ROOT / "result/recheck" / (name + ".png")
        log = image.with_suffix(".log")
        result = subprocess.run(
            [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(ROOT / "tools/capture_evidence.ps1"),
                "-Title",
                "intentional failure",
                "-SqlFile",
                str(ROOT / "tests/sql" / fixture),
                "-Output",
                str(image),
                "-LogFile",
                str(log),
                "-Database",
                DATABASE,
            ],
            capture_output=True,
            text=True,
            errors="replace",
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(expected, result.stderr)
        self.assertFalse(image.exists())

    def test_unexpected_sql_error_prevents_capture(self) -> None:
        self.assert_capture_fails("fail_unexpected.sql", "Evidence SQL failed")

    def test_fail_marker_prevents_capture_despite_pass_marker(self) -> None:
        self.assert_capture_fails("fail_marker.sql", "Evidence assertion failed")
