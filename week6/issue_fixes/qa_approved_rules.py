"""Check editable v1.1 ER against actual FK source and approved cardinalities."""
from __future__ import annotations

import re
from collections import Counter
from pathlib import Path
from xml.etree import ElementTree

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "week6" / "issue_fixes"
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
assert len(tables) == 15 and len(edges) == 18 and len(actual) == 18
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
with Image.open(HERE / "er_diagram_v11.png") as pic:
    assert pic.width >= 2000 and pic.height >= 1200
    pic.verify()
print("PASS v1.1 editable ER: 15 tables / 18 actual FKs; cardinalities and exported SVG/PNG")
