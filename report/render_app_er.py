"""Render the editable 18-table application model with existing ER routing."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parent))
from week6.v11 import render_er_v11 as drawing  # noqa: E402


def read_model() -> tuple[dict[str, list[str]], list[drawing.Link]]:
    tables: dict[str, list[str]] = {}
    links: list[drawing.Link] = []
    current = None
    for row in (ROOT / "er_diagram_app.mmd").read_text(encoding="utf-8").splitlines():
        if match := drawing.EDGE_RE.match(row):
            links.append(drawing.Link(*match.groups()))
        elif match := drawing.ENTITY_RE.match(row):
            current = match.group(1)
            tables[current] = []
        elif row.strip() == "}":
            current = None
        elif current and len(row.split()) >= 2:
            parts = row.split()
            tables[current].append(" ".join(parts[1:]))
    if len(tables) != 18 or len(links) != 22:
        raise ValueError("Expected 18 entities / 22 foreign keys")
    return tables, links


def main() -> None:
    drawing.LAYOUT["Sessions"] = (0.7, 4.1)
    drawing.TYPES["Sessions"] = "会话身份"
    drawing.COLORS["Sessions"] = "#495E83"
    drawing.SIDES[("Users", "Sessions", "user_id")] = ("R", "T")
    drawing.SIDES[("Employees", "Sessions", "employee_id")] = ("L", "R")
    tables, links = read_model()
    drawing.plt.rcParams.update(
        {"font.family": ["Microsoft YaHei", "DejaVu Sans"], "svg.fonttype": "none"}
    )
    figure, axes = drawing.plt.subplots(figsize=(25, 19), dpi=130)
    axes.set(xlim=(-0.35, drawing.CANVAS_X), ylim=(-0.5, drawing.CANVAS_Y), aspect="equal")
    axes.axis("off")
    axes.text(0.65, 24, "TokenHub Web | 18 张表 / 22 条外键", size=20, weight="bold")
    axes.text(0.65, 23.2, "业务基线 v1.1：17 表 / 20 FK；应用增量：app.Sessions / 2 FK", size=12)
    axes.text(
        0.65, 22.6, "会话必须关联顾客或员工之一；两个可空外键与 CHECK 联合限定唯一身份。", size=11
    )
    drawing.draw_edges(axes, links)
    drawing.draw_nodes(axes, tables)
    for extension in ("svg", "png"):
        figure.savefig(ROOT / ("er_diagram_app." + extension), bbox_inches="tight", dpi=130)
    svg = ROOT / "er_diagram_app.svg"
    svg.write_text(
        "\n".join(line.rstrip() for line in svg.read_text(encoding="utf-8").splitlines()) + "\n",
        encoding="utf-8",
    )
    drawing.plt.close(figure)
    print("PASS editable application ER: 18 entities / 22 FK, SVG and PNG exported")


if __name__ == "__main__":
    main()
