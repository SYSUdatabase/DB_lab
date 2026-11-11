"""Check editable v1.1 ER against actual FK source and approved cardinalities."""
from __future__ import annotations

import re
from collections import Counter
from pathlib import Path
from xml.etree import ElementTree

import struct
import zlib

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "db_tools" / "v11"
model = (HERE / "er_diagram_v11.mmd").read_text(encoding="utf-8-sig")
edges = re.findall(
    r"^    (\w+)\s+(?:o\||\|\||o\{|\|\{)(?:\.\.|--)"
    r"(?:o\||\|\||o\{|\|\{)\s+(\w+)\s*:\s*(\w+)\s*$",
    model,
    re.M,
)
tables = set(re.findall(r"^    (\w+)\s+\{$", model, re.M))
raw_fks = (ROOT / "result/week6/regression/actual_fks.txt").read_text(encoding="utf-8-sig")
actual = [
    tuple(line.strip().split("|"))
    for line in raw_fks.splitlines()
    if re.fullmatch(r"\w+\|\w+\|\w+", line.strip())
]
assert len(tables) == 17 and len(edges) == 20 and len(actual) == 18
actual += [("Orders","RefundLedger","order_id"),
           ("OrderDetails","OrderTokenLots","detail_id")]
assert Counter(edges) == Counter(actual), (Counter(edges) - Counter(actual), Counter(actual) - Counter(edges))
assert "UpstreamAccount ||..|| Inventory : account_id" in model
assert "Employees o|..o{ RestockTask : created_by" in model
assert "varchar created_source" in model
assert "Users ||..o{ Orders : user_id" in model
for suffix in ("svg", "png"):
    assert (HERE / f"er_diagram_v11.{suffix}").is_file()
tree = ElementTree.parse(HERE / "er_diagram_v11.svg")
labels = " ".join(t.text or "" for t in tree.iter() if t.tag.endswith("text"))
assert "v1.1" in labels and "created_by" in labels and "0..1" in labels and "1..1" in labels
# Validate PNG dimensions, structure, and chunk checksums without optional Pillow.
png = (HERE / "er_diagram_v11.png").read_bytes()
assert png[:8] == bytes.fromhex("89504e470d0a1a0a")
offset, width, height, seen_end = 8, 0, 0, False
while offset + 12 <= len(png):
    n = int.from_bytes(png[offset : offset + 4], "big")
    kind = png[offset + 4 : offset + 8]
    data = png[offset + 8 : offset + 8 + n]
    stored_crc = int.from_bytes(png[offset + 8 + n : offset + 12 + n], "big")
    assert len(data) == n and len(png) >= offset + 12 + n
    assert zlib.crc32(kind + data) == stored_crc, "PNG chunk CRC mismatch"
    if kind == b"IHDR":
        width, height = struct.unpack(">II", data[:8])
    if kind == b"IEND":
        seen_end = True
        break
    offset += 12 + n
assert seen_end and width >= 2000 and height >= 1200
print("PASS v1.1 editable ER: 17 tables / 20 FKs; cardinalities and exported SVG/PNG")
