"""Read-only QA for a pre-week6 code snapshot and completed clean replay."""
from __future__ import annotations

import hashlib
from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
ARCHIVE_DIR = ROOT / "archive/week6-pre-migration"
ZIP = ARCHIVE_DIR / "DB_lab_pre_week6_c8d4e64_full_source.zip"
EXPECTED_SHA256 = "D2DFA2F23504050ACBA3F4BDE95A7946DCA72D29F6599A6D75A67C16DDE5743C"
RUN = ROOT / "result/week6/reproduction/W6Auto261014"

with ZIP.open("rb") as stream:
    digest = hashlib.file_digest(stream, "sha256").hexdigest().upper()
assert digest == EXPECTED_SHA256, "Historical source ZIP differs from frozen original"
with ZipFile(ZIP) as archive:
    paths = {entry.filename for entry in archive.infolist() if not entry.is_dir()}
assert len(paths) == 344, "Historical source archive must contain 344 tracked files"
for required in (
    "sql/00_create_database.sql",
    "sql/01_create_tables.sql",
    "sql/02_insert_data.sql",
    "sql/constraint.sql",
    "sql/role.sql",
    "sql/view.sql",
    "sql/verify.sql",
    "sql/signature.sql",
    "tools/run_v01.ps1",
    "tools/datagen.py",
    "week5/er_diagram.mmd",
):
    assert required in paths, f"Historical source missing {required}"
manifest = (ARCHIVE_DIR / "source_manifest.txt").read_text(encoding="utf-8").splitlines()
assert len(manifest) == 344, "Historical Git object manifest length mismatched"
print("PASS frozen pre-week6 code archive: SHA-256 verified, 344 tracked files")

def read_log(path: Path) -> str:
    """Decode PowerShell UTF-16 or SQLCMD UTF-8/default-codepage log files."""
    payload = path.read_bytes()
    if payload.startswith((bytes.fromhex("fffe"), bytes.fromhex("feff"))):
        return payload.decode("utf-16")
    return payload.decode("utf-8-sig", errors="replace")


logs = {
    "bootstrap": read_log(RUN / "historical_bootstrap.log"),
    "migration": read_log(RUN / "migration_replay.log"),
    "regression": read_log(RUN / "regression_replay.log"),
    "verify": read_log(RUN / "verify_replay.log"),
}
assert "PASS v0.1" in logs["bootstrap"]
assert "PASS W6 MIGRATION" in logs["migration"]
assert "PASS W6 REGRESSION R01-R12" in logs["regression"]
assert "PASS v1.0 adapted VFY01-VFY14 verification" in logs["verify"]
for number in range(1, 13):
    assert f"PASS R{number:02}" in logs["regression"]
assert "VFY01 Baseline row counts" in logs["verify"]
for number in range(2, 15):
    assert f"PASS VFY{number:02}" in logs["verify"]

source = (RUN / "source_before.txt").read_bytes()
before = (RUN / "copy_before.txt").read_bytes()
after = (RUN / "copy_after.txt").read_text(encoding="utf-16").splitlines()
assert source == before, "Freshly built v0.1 and restored copy differ"
before_records = [
    line for line in (RUN / "copy_before.txt").read_text(encoding="utf-16").splitlines()
    if not line.startswith("PERMISSION|")
]
after_records = [line for line in after if not line.startswith("PERMISSION|")]
assert len(before_records) == len(after_records) == 3763
assert before_records == after_records, "Migrated non-permission business rows differ"
record = (RUN / "replay_manifest.txt").read_text(encoding="utf-8-sig")
assert "business_differences=0" in record
assert "source_archive_sha256=" + EXPECTED_SHA256 in record
print("PASS full replay logs: v0.1 build; migration; R01-R12; VFY01-VFY14")
print("PASS source backup/restore hash and 3763 business records unchanged")
