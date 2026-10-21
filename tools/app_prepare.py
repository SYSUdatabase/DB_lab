"""Build a new clean database chain, then install the application extension."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import bcrypt
import pyodbc

ROOT = Path(__file__).resolve().parents[1]


def run(command: list[str], log: Path) -> None:
    if log.exists():
        raise RuntimeError("Evidence already exists: " + str(log))
    process = subprocess.run(
        command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace"
    )
    log.write_text(process.stdout + process.stderr, encoding="utf-8")
    if process.returncode:
        raise RuntimeError("Stage failed; inspect " + str(log))
    print("PASS", log.name, flush=True)


def seed(server: str, database: str) -> None:
    password = os.environ.get("DB_LAB_DEMO_PASSWORD")
    if not password or not 12 <= len(password.encode()) <= 72:
        raise RuntimeError("Set DB_LAB_DEMO_PASSWORD (12–72 UTF-8 bytes) before preparation")
    hashed = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
    db = pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};SERVER="
        + server
        + ";DATABASE="
        + database
        + ";Trusted_Connection=yes;TrustServerCertificate=yes;",
        autocommit=False,
    )
    try:
        db.execute(
            "CREATE USER app_runtime_probe WITHOUT LOGIN; "
            "ALTER ROLE app_runtime ADD MEMBER app_runtime_probe;"
        )
        for name in ("web_customer", "web_other"):
            db.execute(
                "INSERT dbo.Users(username,password_hash,email) VALUES(?,?,?)",
                name,
                hashed,
                name + "@example.invalid",
            )
        for name, role in (("web_staff", "staff"), ("web_admin", "admin")):
            db.execute(
                "INSERT dbo.Employees(name,account,password_hash,role_id) "
                "SELECT ?,?,?,role_id FROM dbo.Roles WHERE role_name=?",
                name,
                name,
                hashed,
                role,
            )
        for provider in ("OpenAI", "Claude", "Gemini", "Other"):
            db.execute(
                "INSERT dbo.UpstreamAccount(provider,account_name,api_key,total_quota,"
                "safety_threshold,status,expires_at) VALUES(?,?,?,100000000,10000,"
                "'active',DATEADD(year,1,SYSDATETIME()))",
                provider,
                "Web " + provider,
                "DEMO_NOT_A_REAL_API_KEY_WEB",
            )
        db.commit()
    except BaseException:
        db.rollback()
        raise
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suffix", required=True)
    parser.add_argument("--server", default=r"localhost\SQLEXPRESS")
    args = parser.parse_args()
    if not re.fullmatch(r"Web[A-Za-z0-9]{3,12}", args.suffix):
        raise SystemExit("Suffix must start Web followed by 3–12 letters/digits")
    password = os.environ.get("DB_LAB_DEMO_PASSWORD", "")
    if not 12 <= len(password.encode("utf-8")) <= 72:
        raise SystemExit("DB_LAB_DEMO_PASSWORD must be 12–72 UTF-8 bytes; never log its value")
    evidence = ROOT / "result" / "webapp" / args.suffix
    evidence.mkdir(parents=True, exist_ok=False)
    source, target = "TokenHubDB_v01_" + args.suffix, "TokenHubDB_v11_" + args.suffix
    run(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(ROOT / "tools/run_v01.ps1"),
            "-Server",
            args.server,
            "-DatabaseName",
            source,
            "-RunLabel",
            "source_" + args.suffix,
        ],
        evidence / "01_source.log",
    )
    base = [sys.executable, "-B"]
    run(
        [
            *base,
            "week6/v11/build_sandbox.py",
            "--server",
            args.server,
            "--source",
            source,
            "--suffix",
            args.suffix,
        ],
        evidence / "02_clone.log",
    )
    log_dir = ROOT / "result/week6/v11" / args.suffix
    for script in ("deploy_extension.py", "install_refund.py", "validate_hardened.py"):
        run(
            [
                *base,
                "week6/v11/" + script,
                "--server",
                args.server,
                "--database",
                target,
                "--log-dir",
                str(log_dir),
            ],
            evidence / (script + ".log"),
        )
    run(
        [
            "sqlcmd",
            "-S",
            args.server,
            "-d",
            target,
            "-E",
            "-C",
            "-b",
            "-f",
            "65001",
            "-v",
            "DatabaseName=" + target,
            "-i",
            str(ROOT / "sql/app/install.sql"),
        ],
        evidence / "03_app_install.log",
    )
    seed(args.server, target)
    (evidence / "manifest.json").write_text(
        json.dumps(
            {
                "server": args.server,
                "database": target,
                "source": source,
                "history_repair": "skipped: fresh v01 passed VFY12/13; hardened verification passed",
                "business_tables": 17,
                "app_tables": 1,
                "accounts": ["web_customer", "web_other", "web_staff", "web_admin"],
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    print("PASS application prepared:", target)


if __name__ == "__main__":
    main()
