"""Extract the canonical 14-table signature file from sqlcmd -o UTF-8 output.

PowerShell nested external-command stdout encoding can vary across Windows hosts.
Read SQLCMD's binary output directly, require all 14 result rows and the expected
canonical order, then emit the same UTF-8 BOM + LF signature used historically.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

TABLES = (
    "Employees", "ExceptionLog", "Inventory", "InventoryLog",
    "OrderDetails", "Orders", "Products", "RestockTask", "Roles",
    "TokenBalances", "TokenUsageLogs", "UpstreamAccount", "UsageSummary", "Users"
)
PATTERN = re.compile(r"^([A-Za-z_]+)\|(\d+)\|([0-9A-F]{64})$")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: signature_from_log.py sqlcmd_output.txt signature.txt")
    source, dest = Path(sys.argv[1]), Path(sys.argv[2])
    if not source.is_file() or dest.exists():
        raise SystemExit("Input not found or output already exists")
    rows = [line for line in source.read_text(encoding="utf-8-sig").splitlines()
            if PATTERN.fullmatch(line)]
    if len(rows) != 14 or tuple(row.split("|", 1)[0] for row in rows) != TABLES:
        raise SystemExit(f"Refused invalid SQL signature: {len(rows)} rows or wrong tables")
    payload = "\ufeff" + "\n".join(rows) + "\n"
    dest.write_bytes(payload.encode("utf-8"))
    print("PASS signature.sql 14 table signatures")


if __name__ == "__main__":
    main()
