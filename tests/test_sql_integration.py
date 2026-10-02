"""在指定实验库中注入真实反例；每例回滚，不修改正常业务行内容。"""

import os
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATABASE = os.environ.get("DB_LAB_TEST_DATABASE", "")
SERVER = os.environ.get("DB_LAB_TEST_SERVER", r"localhost\SQLEXPRESS")


def section(start: str, end: str) -> str:
    source = (ROOT / "sql/verify.sql").read_text(encoding="utf-8")
    segment = source[source.index(start) : source.index(end)]
    return re.sub(r"^GO\s*$", "", segment, flags=re.MULTILINE)


def literal(value: str) -> str:
    return "N'" + value.replace("'", "''") + "'"


@unittest.skipUnless(DATABASE, "Set DB_LAB_TEST_DATABASE to a fresh experiment database")
class SqlIntegrationTests(unittest.TestCase):
    def reject(self, mutation: str, check: str, expected: int) -> None:
        self.assertRegex(DATABASE, r"^TokenHubDB_v01_[A-Za-z0-9]+$")
        query = f"""SET NOCOUNT ON; SET XACT_ABORT OFF;
        DECLARE @got INT=0;
        BEGIN TRANSACTION;
        BEGIN TRY
            {mutation}
            EXEC sys.sp_executesql {literal(check)};
        END TRY
        BEGIN CATCH
            SET @got=ERROR_NUMBER();
        END CATCH;
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        IF USER_NAME()<>N'dbo' THROW 51598,N'Test context not restored',1;
        IF @got<>{expected} THROW 51599,N'Wrong regression rejection',1;
        SELECT @got AS expected_rejection;
        """
        result = subprocess.run(
            ["sqlcmd", "-S", SERVER, "-d", DATABASE, "-E", "-C", "-b", "-Q", query],
            capture_output=True,
            text=True,
            errors="replace",
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_registration_order(self) -> None:
        self.reject(
            "UPDATE dbo.Users SET created_at='2026-10-01' WHERE user_id=17;",
            section("PRINT N'VFY12", "PRINT N'VFY13"),
            51360,
        )

    def test_registration_usage(self) -> None:
        self.reject(
            "UPDATE l SET used_at=DATEADD(SECOND,-1,u.created_at) FROM dbo.TokenUsageLogs l JOIN dbo.Users u ON u.user_id=l.user_id WHERE l.log_id=1;",
            section("PRINT N'VFY12", "PRINT N'VFY13"),
            51361,
        )

    def test_expiry_equal_boundary(self) -> None:
        self.reject(
            "UPDATE l SET used_at=a.expires_at FROM dbo.TokenUsageLogs l JOIN dbo.UpstreamAccount a ON a.account_id=l.account_id WHERE l.log_id=(SELECT MIN(log_id) FROM dbo.TokenUsageLogs WHERE account_id=7);",
            section("PRINT N'VFY12", "PRINT N'VFY13"),
            51362,
        )

    def test_provider_mismatch(self) -> None:
        self.reject(
            "UPDATE dbo.TokenUsageLogs SET account_id=4 WHERE log_id=(SELECT MIN(log_id) FROM dbo.TokenUsageLogs WHERE account_id=1);",
            section("PRINT N'VFY12", "PRINT N'VFY13"),
            51362,
        )

    def test_historical_overdraft_with_correct_final_totals(self) -> None:
        self.reject(
            "UPDATE dbo.TokenUsageLogs SET used_at=DATEADD(SECOND,-1,(SELECT MIN(paid_at) FROM dbo.Orders WHERE user_id=32 AND status='paid')) WHERE log_id=(SELECT MIN(l.log_id) FROM dbo.TokenUsageLogs l JOIN dbo.Products p ON p.product_id=l.product_id WHERE l.user_id=32 AND p.model_provider='OpenAI');",
            section("PRINT N'VFY13", "PRINT N'VFY14"),
            51363,
        )

    def test_missing_one_manager_permission(self) -> None:
        self.reject(
            "REVOKE DELETE ON dbo.Users FROM hub_manager;",
            section("PRINT N'VFY03", "PRINT N'VFY04"),
            51355,
        )

    def test_direct_user_grant_is_detected(self) -> None:
        self.reject(
            "GRANT SELECT ON dbo.Users TO hub_staff_demo;",
            section("PRINT N'VFY14", "PRINT N'PASS v0.1 verification'"),
            51366,
        )

    def test_direct_customer_view_write_is_detected(self) -> None:
        self.reject(
            "GRANT UPDATE ON dbo.v_MyOrders TO hub_user_1;",
            section("PRINT N'VFY14", "PRINT N'PASS v0.1 verification'"),
            51368,
        )
