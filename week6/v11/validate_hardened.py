"""Run full v1.1 checks and new transactional regressions on one isolated target."""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

import pyodbc

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = "TokenHubDB_v11_Issues_20261014"
TESTS = (
    ("04_regression.sql", "PASS V1.1 HARDENED REGRESSION X01-X10"),
    ("06_restock_regression.sql", "PASS V1.1 CONTROLLED RESTOCK TESTS Y01-Y04"),
    ("verify_v11_full.sql", "PASS v1.1 adapted VFY01-VFY14 verification"),
    ("10_refund_regression.sql", "PASS V1.1 REFUND REGRESSION RF01-RF06"),
)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default=r"localhost\SQLEXPRESS")
    ap.add_argument("--database", required=True)
    ap.add_argument("--log-dir", type=Path, required=True)
    args = ap.parse_args()
    if not re.fullmatch(r"TokenHubDB_v11_[A-Za-z0-9_]+", args.database):
        raise SystemExit("Refusing to test non-v1.1 database")
    args.log_dir.mkdir(parents=True, exist_ok=True)
    for filename, expected_pass in TESTS:
        logfile = args.log_dir / ("validation_" + filename + ".log")
        if logfile.exists():
            if expected_pass in logfile.read_text(encoding="utf-8-sig"):
                print("ALREADY PASS", filename)
                continue
            raise RuntimeError("Existing failed evidence must not be overwritten: " + str(logfile))
        content = (ROOT / "week6" / "v11" / filename).read_text(encoding="utf-8-sig")
        if TEMPLATE not in content:
            raise RuntimeError("Test target guard unexpectedly absent")
        content = content.replace(TEMPLATE, args.database)
        with tempfile.TemporaryDirectory(prefix="w6_harden_vfy_") as tmp:
            sql = Path(tmp) / "validate.sql"
            sql.write_text(content, encoding="utf-8")
            process = subprocess.run(
                ["sqlcmd", "-S", args.server, "-d", args.database, "-E", "-C", "-b",
                 "-r", "1", "-f", "65001", "-i", str(sql)],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
            )
        output = process.stdout + process.stderr
        logfile.write_text(output, encoding="utf-8")
        if process.returncode or expected_pass not in output:
            raise RuntimeError("Test failed; inspect " + str(logfile))
        print("PASS", filename)
    db = pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};SERVER=" + args.server
        + ";DATABASE=" + args.database
        + ";Trusted_Connection=yes;TrustServerCertificate=yes;",
        autocommit=True,
    )
    count = db.execute(
        "SELECT COUNT(*) FROM dbo.InventoryLog WHERE reference_type='usage'"
    ).fetchval()
    if count != 3000:
        raise RuntimeError("Typed history missing")
    count = db.execute(
        "SELECT COUNT(*) FROM sys.triggers WHERE name LIKE 'trg_W6_%' AND is_disabled=0"
    ).fetchval()
    if count != 11:
        raise RuntimeError("v1.1 protections missing")
    if db.execute(
        "SELECT COUNT(*) FROM sys.procedures WHERE name IN ('usp_W6_PayPendingOrder','usp_W6_RestockAccount')"
    ).fetchval() != 2:
        raise RuntimeError("Payment/restock procedures missing")
    if db.execute("SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0").fetchval()!=17:
        raise RuntimeError("Expected unified 17-table v1.1")
    if db.execute("SELECT COUNT(*) FROM sys.foreign_keys WHERE is_disabled=0 AND is_not_trusted=0").fetchval()!=20:
        raise RuntimeError("Expected unified 20 trusted FKs")
    if db.execute("SELECT COUNT(*) FROM dbo.OrderTokenLots").fetchval()!=158:
        raise RuntimeError("Historical lot provenance missing")
    if db.execute("SELECT COUNT(*) FROM dbo.RefundLedger").fetchval()!=0:
        raise RuntimeError("Regression created an unexpected persisted refund")
    if db.execute("SELECT COUNT(*) FROM sys.procedures WHERE name IN ('usp_W6_RequestRefund','usp_W6_AttestRefundPayout')").fetchval()!=2:
        raise RuntimeError("Controlled refund or payout attestation missing")
    print("PASS final v1.1 metadata: 17 tables, 20 trusted FKs, 158 lots, 3000 typed refs, 11 W6 guards, refund ledgers clean")


if __name__ == "__main__":
    main()
