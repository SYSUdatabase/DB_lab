"""Apply reviewed v1.1 hardening patches only to a specified isolated database."""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = "TokenHubDB_v11_Issues_20261014"
FILES = ("01_typed_consumption_refs.sql", "02_managed_usage_v11.sql",
         "03_close_write_paths.sql", "05_managed_restock.sql")


def apply_sql(server: str, dbname: str, filename: str, output: Path) -> None:
    source = (ROOT / "week6" / "v11" / filename).read_text(encoding="utf-8-sig")
    assert TEMPLATE in source, "Expected target-name safety guard is missing"
    adapted = source.replace(TEMPLATE, dbname)
    with tempfile.TemporaryDirectory(prefix="w6_hardening_") as tmp:
        script = Path(tmp) / "patch.sql"
        script.write_text(adapted, encoding="utf-8")
        result = subprocess.run(
            ["sqlcmd", "-S", server, "-d", dbname, "-E", "-C", "-b",
             "-r", "1", "-f", "65001", "-i", str(script)],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
    output.write_text(result.stdout + result.stderr, encoding="utf-8")
    if result.returncode:
        raise RuntimeError("FAILED: " + filename + " (see " + str(output) + ")")
    if "PASS" not in result.stdout + result.stderr:
        raise RuntimeError("Missing explicit PASS in " + filename)
    print("PASS", filename)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default=r"localhost\SQLEXPRESS")
    ap.add_argument("--database", required=True)
    ap.add_argument("--log-dir", type=Path, required=True)
    ap.add_argument("--resume", action="store_true", help="Continue after a verified PASS log")
    args = ap.parse_args()
    if not re.fullmatch(r"TokenHubDB_v11_[A-Za-z0-9_]+", args.database):
        raise SystemExit("Only isolated v1.1 database names are permitted")
    if not args.log_dir.is_dir():
        raise SystemExit("An existing log directory from the backed-up sandbox is required")
    if not args.resume and any((args.log_dir / (x + ".log")).exists() for x in FILES):
        raise SystemExit("Refusing to overwrite existing deployment evidence")
    for filename in FILES:
        path = args.log_dir / (filename + ".log")
        if path.exists():
            if not args.resume or "PASS" not in path.read_text(encoding="utf-8-sig"):
                raise RuntimeError("Cannot resume from unverified log: " + str(path))
            print("ALREADY PASS", filename)
            continue
        apply_sql(args.server, args.database, filename, path)
    print("PASS v1.1 hardening installed; source database untouched")


if __name__ == "__main__":
    main()
