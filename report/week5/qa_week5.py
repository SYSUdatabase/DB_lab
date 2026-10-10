"""Week 5 static artifact QA; reads only public schema descriptions and output counts."""
from __future__ import annotations

import re
from collections import Counter
from pathlib import Path
from xml.etree import ElementTree

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ER = (HERE / "er_diagram.mmd").read_text(encoding="utf-8")
LOG = (ROOT / "result/week5/readonly_validation.log").read_text(encoding="utf-8")

TABLES = set(re.findall(r"^\s{4}(\w+)\s+\{", ER, re.MULTILINE))
EDGES = re.findall(
    r"^\s{4}(\w+)\s+(?:o\||\|\||o\{|\|\{)--(?:o\||\|\||o\{|\|\{)\s+(\w+)\s*:\s*(\w+)\s*$",
    ER,
    re.MULTILINE,
)
FK_LOG = re.findall(r"^(\w+)\s+(FK_\w+)\s+(\w+)\s*$", LOG, re.MULTILINE)
assert len(TABLES) == 14, f"Table count: {len(TABLES)}"
assert len(EDGES) == 17, f"ER relation count: {len(EDGES)}"
assert len(FK_LOG) == 17, f"SQL Server FK count: {len(FK_LOG)}"
assert all(parent in TABLES and child in TABLES for parent, child, _ in EDGES)
er_pairs = Counter((parent, child) for parent, child, _ in EDGES)
sql_pairs = Counter((parent, child) for child, _, parent in FK_LOG)
assert er_pairs == sql_pairs, f"ER model does not match actual FK parent/child pairs: {er_pairs - sql_pairs}"

vector = HERE / "er_diagram.svg"
bitmap = HERE / "er_diagram.png"
ElementTree.parse(vector)
with Image.open(bitmap) as image:
    image.verify()

checks = [
    ROOT / "README.md",
    ROOT / "docs/requirements/README.md",
    ROOT / "report/stage_report.md",
    ROOT / "plan/week5-er-model-plan.md",
    ROOT / "result/week5/README.md",
    *HERE.glob("*.md"),
]
bad_links: list[str] = []
for document in checks:
    body = document.read_text(encoding="utf-8")
    for target in re.findall(r"\]\(([^)]+)\)", body):
        if "://" in target or target.startswith("#"):
            continue
        file_target = target.split("#", 1)[0]
        if file_target and not (document.parent / file_target).exists():
            bad_links.append(f"{document}: {target}")
assert not bad_links, "Dead markdown links:\n" + "\n".join(bad_links)

print(f"PASS: {len(TABLES)} Mermaid tables; {len(EDGES)} Mermaid relations match {len(FK_LOG)} SQL Server FKs")
print("PASS: SVG XML and PNG image parse correctly")
print(f"PASS: relative links in {len(checks)} current documents")
print("PASS: QA did not query/modify the database or read credential values")
