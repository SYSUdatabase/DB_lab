"""Test SQL Server service ACL setup for per-run backup directories."""

import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import MagicMock, patch

from db_tools.v11.build_sandbox import grant_sql_service_access


class BackupDirectoryPermissionTests(unittest.TestCase):
    @patch("db_tools.v11.build_sandbox.subprocess.run")
    def test_grants_modify_to_the_exact_sql_service_account(self, run: MagicMock) -> None:
        run.return_value = subprocess.CompletedProcess([], 0, "granted", "")
        with TemporaryDirectory() as folder:
            directory = Path(folder)
            grant_sql_service_access(directory, r"NT Service\MSSQL$SQLEXPRESS")
        args = run.call_args.args[0]
        self.assertEqual(
            args,
            [
                "icacls",
                str(directory),
                "/grant",
                r"NT Service\MSSQL$SQLEXPRESS:(OI)(CI)M",
            ],
        )
        self.assertTrue(run.call_args.kwargs["capture_output"])

    @patch("db_tools.v11.build_sandbox.subprocess.run")
    def test_rejects_control_characters_in_service_account(self, run: MagicMock) -> None:
        with TemporaryDirectory() as folder:
            with self.assertRaisesRegex(RuntimeError, "invalid service account"):
                grant_sql_service_access(Path(folder), "NT Service\\SQL\nInjected")
        run.assert_not_called()

    @patch("db_tools.v11.build_sandbox.subprocess.run")
    def test_fails_closed_when_icacls_cannot_grant_access(self, run: MagicMock) -> None:
        run.return_value = subprocess.CompletedProcess([], 5, "", "Access is denied")
        with TemporaryDirectory() as folder:
            with self.assertRaisesRegex(RuntimeError, "Could not grant"):
                grant_sql_service_access(Path(folder), r"NT Service\MSSQL$SQLEXPRESS")


if __name__ == "__main__":
    unittest.main()
