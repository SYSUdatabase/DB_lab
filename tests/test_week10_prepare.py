"""Week 10 is an explicit, bounded extension to existing preparation."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools import app_prepare


class Week10PreparationTests(unittest.TestCase):
    def test_help_exposes_opt_in_without_connecting(self) -> None:
        result = subprocess.run(
            [sys.executable, "tools/app_prepare.py", "--help"], capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("--with-week10", result.stdout)

    def test_rejects_unbounded_database_before_running_sql(self) -> None:
        with patch.object(app_prepare, "run") as run:
            with self.assertRaisesRegex(ValueError, "isolated"):
                app_prepare.install_week10("localhost", "master", Path("unused"))
            run.assert_not_called()

    def test_extension_uses_guarded_entry_and_own_log(self) -> None:
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(app_prepare, "run") as run,
            patch.object(app_prepare, "week10_baseline", return_value={"Orders": [100, 42]}),
        ):
            app_prepare.install_week10("localhost", "TokenHubDB_v11_WebW10Dev01", Path(directory))
            command, log = run.call_args.args
            self.assertIn("DatabaseName=TokenHubDB_v11_WebW10Dev01", command)
            self.assertEqual(Path(command[-1]).name, "install.sql")
            self.assertEqual(log.name, "04_week10_install.log")
