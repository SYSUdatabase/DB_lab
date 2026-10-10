"""Week 5 static artifact QA; reads only public schema descriptions and output counts."""
from __future__ import annotations

import re
from collections import Counter
from pathlib import Path
from xml.etree import ElementTree

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
ER = (HERE / "er_diagram.mmd").read_text(encoding="utf-8")
LOG = (ROOT / "result/week5/readonly_validation.log").read_text(encoding="utf-8")

TABLES = set(re.findall(r"^\s{4}(\w+)\s+\{", ER, re.MULTILINE))
EDGES = re.findall(
    r"^\s{4}(\w+)\s+(?:o\||\|\||o\{|\|\{)(?:\.\.|--)(?:o\||\|\||o\{|\|\{)\s+(\w+)\s*:\s*(\w+)\s*$",
    ER,
    re.MULTILINE,
)
FK_LOG = re.findall(r"^(\w+)\s+(FK_\w+)\s+(\w+)\s*$", LOG, re.MULTILINE)
assert len(TABLES) == 14, f"Table count: {len(TABLES)}"
assert len(EDGES) == 17, f"ER relation count: {len(EDGES)}"
assert len(re.findall(r"^\s{4}\w+\s+(?:o\||\|\||o\{|\|\{)\.\.", ER, re.MULTILINE)) == 17, "17 FKs must be non-identifying"
assert len(FK_LOG) == 17, f"SQL Server FK count: {len(FK_LOG)}"
assert all(parent in TABLES and child in TABLES for parent, child, _ in EDGES)
er_pairs = Counter((parent, child) for parent, child, _ in EDGES)
sql_pairs = Counter((parent, child) for child, _, parent in FK_LOG)
assert er_pairs == sql_pairs, f"ER model does not match actual FK parent/child pairs: {er_pairs - sql_pairs}"

# Verify each relation's exact child FK column against the authoritative v0.1 DDL.
# Comparing parent/child pairs alone misses role swaps such as created_by vs assigned_to.
ddl = (ROOT / "sql/01_create_tables.sql").read_text(encoding="utf-8-sig")
schema_fk: set[tuple[str, str, str]] = set()
for block in re.finditer(r"CREATE TABLE dbo\.(\w+)\s*\((.*?)^\);", ddl, re.S | re.M):
    child, definition = block.groups()
    for match in re.finditer(
        r"CONSTRAINT\s+FK_\w+\s+FOREIGN KEY\s*\((\w+)\)\s*"
        r"REFERENCES\s+dbo\.(\w+)\s*\(\w+\)", definition, re.S
    ):
        column, parent = match.groups()
        schema_fk.add((parent, child, column))
er_fk = set((parent, child, column) for parent, child, column in EDGES)
assert len(schema_fk) == len(er_fk) == 17, (schema_fk, er_fk)
assert schema_fk == er_fk, f"Mermaid FK column mismatch: {er_fk ^ schema_fk}"

vector = HERE / "er_diagram.svg"
bitmap = HERE / "er_diagram.png"
tree = ElementTree.parse(vector)
visible_text = " ".join(t.text or "" for t in tree.iter() if t.tag.endswith("text"))
assert "stroke-dasharray" not in vector.read_text(encoding="utf-8"), "Exported FK lines must be solid"
for role_label in ("created_by", "assigned_to", "双角色外码", "实线"):
    assert role_label in visible_text, f"Missing role/solid-line explanation: {role_label}"
assert "API Token 中转站" in visible_text, "Main diagram title missing"
assert "第五周 · 14 张业务表" not in visible_text, "Unwanted subtitle still displayed"
assert "图例" in visible_text, "Diagram legend missing"
assert "0..N" not in visible_text and "1..N" not in visible_text
assert "0..*" in visible_text and "1..1" in visible_text and "0..1" in visible_text
for tag in ("关联实体", "三方调用", "计算存储", "汇总存储", "额度快照"):
    assert tag in visible_text, f"Special ER feature annotation missing: {tag}"
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
