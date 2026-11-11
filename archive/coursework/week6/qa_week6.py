"""Static QA for the week-6 editable v1.0 ER delivery; no database writes."""
from __future__ import annotations

import re
from collections import Counter
from pathlib import Path
from xml.etree import ElementTree

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
HERE = ROOT / "week6"
model = (HERE / "er_diagram_v10.mmd").read_text(encoding="utf-8-sig")
sql_fk_text = (ROOT / "result/week6/regression/actual_fks.txt").read_text(
    encoding="utf-8-sig"
)
entities = set(re.findall(r"^\s{4}(\w+)\s+\{", model, re.M))
links = re.findall(
    r"^\s{4}(\w+)\s+(?:o\||\|\||o\{|\|\{)(?:\.\.|--)"
    r"(?:o\||\|\||o\{|\|\{)\s+(\w+)\s*:\s*(\w+)\s*$",
    model,
    re.M,
)
current = []
for line in sql_fk_text.splitlines():
    line = line.strip()
    if re.fullmatch(r"[A-Za-z_]+\|[A-Za-z_]+\|[A-Za-z_]+", line):
        current.append(tuple(line.split("|")))
assert len(entities) == 15, f"Mermaid table count {len(entities)}"
assert len(links) == 18, f"Mermaid FK count {len(links)}"
assert len(current) == 18, f"SQL Server FK count {len(current)}"
assert all(child in entities and parent in entities for parent, child, _ in links)
assert Counter(links) == Counter(current), (
    "ER source and actual SQL Server FK/columns differ: "
    f"missing={Counter(current)-Counter(links)}; extra={Counter(links)-Counter(current)}"
)
assert ("UsagePeriod", "UsageSummaryCore", "period_type_period_start") in links
assert "period_end" in model and "    UsagePeriod {" in model

vector = HERE / "er_diagram_v10.svg"
bitmap = HERE / "er_diagram_v10.png"
tree = ElementTree.parse(vector)
display_text = " ".join(n.text or "" for n in tree.iter() if n.tag.endswith("text"))
assert "v1.0 物理 ER 模型" in display_text
assert "0..*" in display_text and "1..1" in display_text
assert "created_by" in display_text and "assigned_to" in display_text
assert "stroke-dasharray" not in vector.read_text(encoding="utf-8"), "Unexpected dashed FK"
with Image.open(bitmap) as im:
    assert im.width > 2000 and im.height > 1200
    im.verify()

docs = [
    ROOT / "README.md",
    ROOT / "ROADMAP.md",
    ROOT / "week6/README.md",
    ROOT / "week6/data_dictionary_v10.md",
    ROOT / "week6/redesign_decisions.md",
    ROOT / "week6/dependency_normalization.md",
    ROOT / "week6/report_material.md",
    ROOT / "result/week6/README.md",
    ROOT / "plan/week6-normalization-migration-plan.md",
]
bad_links = []
checked = 0
for doc in docs:
    content = doc.read_text(encoding="utf-8-sig")
    for link in re.findall(r"\]\(([^)]+)\)", content):
        if link.startswith(("https://", "http://", "#")):
            continue
        destination = link.split("#", 1)[0]
        if not destination:
            continue
        checked += 1
        if not (doc.parent / destination).exists():
            bad_links.append(f"{doc.name}: {link}")
assert not bad_links, "Broken relative links:\n" + "\n".join(bad_links)
print(f"PASS W6 diagram: {len(entities)} entities / {len(links)} FKs match SQL Server columns")
print("PASS W6 exported SVG/PNG and visible textual multiplicities")
print(f"PASS W6 document links: {checked} checked; {len(bad_links)} broken")
