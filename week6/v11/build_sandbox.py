"""Create v1.0 and v1.1 on two NEW isolated databases from backed-up v0.1.

The original v0.1, existing v1.0/v1.1, and all older log files remain untouched.
The script uses a caller-supplied NEW suffix and rejects target name collisions.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import subprocess
import tempfile
from uuid import uuid4

import pyodbc

ROOT = Path(__file__).resolve().parents[2]


def connection(server: str, db: str = "master") -> pyodbc.Connection:
    return pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};SERVER=" + server
        + ";DATABASE=" + db + ";Trusted_Connection=yes;TrustServerCertificate=yes;",
        autocommit=True,
    )


def run_sqlcmd(server: str, database: str, sql: str, log: Path, note: str) -> None:
    if log.exists():
        raise RuntimeError("Refusing to overwrite log: " + str(log))
    with tempfile.TemporaryDirectory(prefix="w6_v11_stage_") as folder:
        sql_path = Path(folder) / "task.sql"
        sql_path.write_text(sql, encoding="utf-8")
        proc = subprocess.run(
            ["sqlcmd", "-S", server, "-d", database, "-E", "-C", "-b", "-r", "1",
             "-f", "65001", "-i", str(sql_path)],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
    log.write_text(proc.stdout + proc.stderr, encoding="utf-8")
    if proc.returncode:
        raise RuntimeError(note + " FAILED; inspect " + str(log))
    print("PASS", note)


def backup_restore(cur: pyodbc.Cursor, server_name: str, original: str, target: str,
                   bak_dir: str, data_dir: str, log_file: Path) -> None:
    if cur.execute("SELECT DB_ID(?)", target).fetchval() is not None:
        raise RuntimeError("Refusing to overwrite existing DB: " + target)
    token = uuid4().hex[:12]
    bak = str(Path(bak_dir) / (original + "_W6_" + token + ".bak"))
    qbak = bak.replace("'", "''")
    qdata = str(Path(data_dir) / (target + ".mdf")).replace("'", "''")
    qlog = str(Path(data_dir) / (target + "_log.ldf")).replace("'", "''")
    # BACKUP / RESTORE produce progress result sets. sqlcmd waits for the
    # complete operation; closing a Python cursor early can cancel it.
    print("Backing up", original, "then restoring", target)
    operations = [
        ("BACKUP DATABASE [" + original + "] TO DISK=N'" + qbak
         + "' WITH COPY_ONLY,CHECKSUM", "backup"),
        ("RESTORE VERIFYONLY FROM DISK=N'" + qbak + "' WITH CHECKSUM", "verifyonly"),
        ("RESTORE DATABASE [" + target + "] FROM DISK=N'" + qbak
         + "' WITH MOVE N'TokenHubDB_v01_A' TO N'" + qdata
         + "', MOVE N'TokenHubDB_v01_A_log' TO N'" + qlog
         + "', RECOVERY,CHECKSUM", "restore"),
    ]
    for sql, step in operations:
        command = subprocess.run(
            ["sqlcmd", "-S", server_name, "-d", "master",
             "-E", "-C", "-b", "-r", "1", "-Q", sql],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
        if command.returncode != 0:
            raise RuntimeError("Isolated database " + step + " failed: "
                               + command.stdout[-500:] + command.stderr[-500:])
    state = cur.execute("SELECT state_desc FROM sys.databases WHERE name=?", target).fetchval()
    if state != "ONLINE":
        raise RuntimeError("Restore did not finish ONLINE: " + repr(state))
    log_file.write_text("BACKUP COPY_ONLY CHECKSUM + VERIFYONLY + RESTORE PASS\n"
                        + "source=" + original + "\ntarget=" + target + "\nbackup=" + bak
                        + "\n", encoding="utf-8")
    print("PASS isolated DB backup and restore")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default=r"localhost\SQLEXPRESS")
    ap.add_argument("--source", default="TokenHubDB_v01_A",
                    choices=["TokenHubDB_v01_A"])
    ap.add_argument("--suffix", required=True, help="new 6-16 alphanumeric characters")
    args = ap.parse_args()
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]{5,15}", args.suffix):
        raise SystemExit("Invalid suffix")
    v10 = "TokenHubDB_v10_" + args.suffix
    v11 = "TokenHubDB_v11_" + args.suffix
    evidence = ROOT / "result" / "week6" / "v11" / args.suffix
    if evidence.exists():
        raise RuntimeError("Refusing to overwrite previous run")
    master = connection(args.server)
    cur = master.cursor()
    if cur.execute("SELECT DB_ID(?)", args.source).fetchval() is None:
        raise RuntimeError("Original v0.1 database missing")
    if any(cur.execute("SELECT DB_ID(?)", name).fetchval() is not None
           for name in (v10, v11)):
        raise RuntimeError("Isolated databases already exist")
    bakdir = cur.execute(
        "SELECT CONVERT(NVARCHAR(400),SERVERPROPERTY('InstanceDefaultBackupPath'))"
    ).fetchval()
    datadir = cur.execute(
        "SELECT CONVERT(NVARCHAR(400),SERVERPROPERTY('InstanceDefaultDataPath'))"
    ).fetchval()
    if not bakdir or not datadir:
        raise RuntimeError("Cannot determine SQL paths")
    evidence.mkdir(parents=True)
    backup_restore(cur, args.server, args.source, v10, bakdir, datadir, evidence / "copy_v01_to_v10.txt")
    migr = (ROOT / "sql" / "migration.sql").read_text(encoding="utf-8-sig")
    if "TokenHubDB_v10_W6_20261014" not in migr:
        raise RuntimeError("Migration whitelist was changed")
    migr = migr.replace("TokenHubDB_v10_W6_20261014", v10)
    run_sqlcmd(args.server, v10, migr, evidence / "migration.log", "v1.0 migration")
    backup_restore(cur, args.server, v10, v11, bakdir, datadir, evidence / "copy_v10_to_v11.txt")
    scripts = [
        "enforce_known_rules.sql",
        "record_usage.sql",
        "protect_parent_deletes.sql",
        "approved_rules.sql",
        "registered_order_workflow.sql",
    ]
    for fname in scripts:
        sql = (ROOT / "week6" / "v11" / fname).read_text(encoding="utf-8-sig")
        if "TokenHubDB_v11_Issues_20261014" not in sql:
            raise RuntimeError("v1.1 source whitelist changed: " + fname)
        sql = sql.replace("TokenHubDB_v11_Issues_20261014", v11)
        run_sqlcmd(args.server, v11, sql, evidence / (fname + ".log"), fname)
    for fname in (
        "verify_approved_rules_baseline.sql", "test_guards.sql",
        "test_managed_usage.sql", "test_parent_and_role.sql",
        "test_approved_rules.sql",
        "regression_v11.sql",
    ):
        sql = (ROOT / "week6" / "v11" / fname).read_text(encoding="utf-8-sig")
        sql = sql.replace("TokenHubDB_v11_Issues_20261014", v11)
        run_sqlcmd(args.server, v11, sql, evidence / (fname + ".log"), fname)
    print("PASS original v0.1 protected; isolated v1.0 and v1.1 ready:", v11)


if __name__ == "__main__":
    main()
