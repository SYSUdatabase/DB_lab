"""Render a six-module business map from the editable Mermaid flowchart.

Run from repository root: python -B report/render_overview_modules.py
This visual is a conceptual module guide, not an ER/FK or executable process graph.
"""
from __future__ import annotations

import re
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.axes import Axes
from matplotlib.figure import Figure
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "overview_modules.mmd"
WIDTH = 10.8
HEIGHT = 7.35
POS = {
    "A": (0.7, 11.45), "B": (13.0, 11.45), "C": (25.3, 11.45),
    "F": (0.7, 2.90), "E": (13.0, 2.90), "D": (25.3, 2.90),
}
PHYSICAL = {
    "Users", "Roles", "Employees", "Products", "Orders", "OrderDetails",
    "TokenBalances", "TokenUsageLogs", "UpstreamAccount", "Inventory",
    "InventoryLog", "RestockTask", "UsagePeriod", "UsageSummaryCore",
    "ExceptionLog",
}
FOOTNOTE = {
    "A": "应用角色 Roles 与 SQL Server 数据库角色是两回事",
    "B": "明细保存下单时的价格和 Token 快照",
    "C": "按 provider 管理会员余额；一次调用记一条流水",
    "D": "库存表示上游 Token 配额，不是实体商品数量",
    "E": "UsageSummary 是兼容视图，不是第 16 张表",
    "F": "实际权限由数据库角色与授权视图控制",
}
SWATCH = {
    "A": "#3776CA", "B": "#C78A28", "C": "#268E69",
    "D": "#268F91", "E": "#7C64C2", "F": "#BE666B",
}
NODE_RE = re.compile(r'^\s+([A-F])\["([^"]+)"\]\s*$')
EDGE_RE = re.compile(r"^\s+([A-F]) -->\|([^|]+)\| ([A-F])\s*$")


def parse_source() -> tuple[dict[str, list[str]], list[tuple[str, str, str]]]:
    nodes: dict[str, list[str]] = {}
    edges: list[tuple[str, str, str]] = []
    for raw in SOURCE.read_text(encoding="utf-8").splitlines():
        if match := NODE_RE.match(raw):
            nodes[match.group(1)] = match.group(2).split("<br/>")
        elif match := EDGE_RE.match(raw):
            edges.append((match.group(1), match.group(2), match.group(3)))
    if set(nodes) != set(POS) or len(edges) != 5:
        raise ValueError("Expected six business modules and five main map arrows")
    names = [s.split("｜", 1)[0].strip() for v in nodes.values() for s in v[2:]]
    physical_names = [name for name in names if name in PHYSICAL]
    if set(physical_names) != PHYSICAL or len(physical_names) != len(PHYSICAL):
        raise ValueError("A physical table is missing, duplicated, or misclassified")
    if names.count("UsageSummary") != 1:
        raise ValueError("UsageSummary read compatibility view must be represented once")
    return nodes, edges


def draw_card(ax: Axes, code: str, lines: list[str]) -> None:
    x, y = POS[code]
    color = SWATCH[code]
    box = FancyBboxPatch((x, y), WIDTH, HEIGHT, boxstyle="round,pad=0,rounding_size=.20",
                         ec="#D5DFE7", lw=1.25, fc="#FFFFFF", zorder=3)
    ax.add_patch(box)
    header = FancyBboxPatch((x, y + HEIGHT - 1.17), WIDTH, 1.17,
                            boxstyle="round,pad=0,rounding_size=.20",
                            ec="none", fc=color, zorder=4)
    ax.add_patch(header)
    ax.add_patch(plt.Rectangle((x, y + HEIGHT - 1.17), WIDTH, 0.32,
                               ec="none", fc=color, zorder=4))
    number, title = lines[0].split(" ", 1)
    count = sum(s.split("｜", 1)[0].strip() in PHYSICAL for s in lines[2:])
    ax.text(x + 0.30, y + HEIGHT - 0.59, number, color="#FFFFFF", fontsize=14,
            fontweight="bold", va="center", zorder=5)
    ax.text(x + 1.15, y + HEIGHT - 0.59, title, color="#FFFFFF", fontsize=14.3,
            fontweight="bold", va="center", zorder=5)
    ax.text(x + WIDTH - .32, y + HEIGHT - .59, f"{count} 张表",
            color="#FFFFFF", alpha=.90, fontsize=10, ha="right", va="center", zorder=5)
    ax.text(x + 0.34, y + HEIGHT - 1.70, lines[1], fontsize=10.6,
            color="#475569", va="center", zorder=5)
    ax.plot([x + .30, x + WIDTH - .30], [y + HEIGHT - 2.10] * 2,
            lw=1, color="#E9EEF2", zorder=5)
    for index, line in enumerate(lines[2:]):
        table_name, detail = (line.split("｜", 1) + [""])[:2]
        baseline = y + HEIGHT - 2.72 - index * .84
        is_table = table_name in PHYSICAL
        tag = "表" if is_table else ("视图" if table_name == "UsageSummary" else "机制")
        ax.text(x + .34, baseline, tag, fontsize=8.2, color=color, va="center",
                bbox={"boxstyle": "round,pad=.22", "facecolor": "#F0F4F8",
                      "edgecolor": "none"}, zorder=5)
        ax.text(x + 1.24, baseline, table_name, fontsize=10.0,
                color="#203044", fontweight="bold", va="center", zorder=5)
        ax.text(x + WIDTH - .31, baseline, detail, fontsize=9.05,
                color="#56657A", va="center", ha="right", zorder=5)
    ax.plot([x + .30, x + WIDTH - .30], [y + .90] * 2,
            lw=.8, color="#E9EEF2", zorder=5)
    ax.text(x + .33, y + .46, FOOTNOTE[code], color="#64748B",
            fontsize=8.6, va="center", zorder=5)


def edge_coords(start: str, end: str) -> tuple[tuple[float, float], tuple[float, float]]:
    x1, y1 = POS[start]
    x2, y2 = POS[end]
    if abs(y1 - y2) < .01:
        mid = y1 + HEIGHT / 2
        return ((x1 + WIDTH, mid), (x2, mid)) if x2 > x1 else ((x1, mid), (x2 + WIDTH, mid))
    return ((x1 + WIDTH / 2, y1), (x2 + WIDTH / 2, y2 + HEIGHT))


def draw_arrows(ax: Axes, edges: list[tuple[str, str, str]]) -> None:
    for start, label, end in edges:
        p, q = edge_coords(start, end)
        ax.add_patch(FancyArrowPatch(p, q, arrowstyle="-|>", mutation_scale=17,
                                     linewidth=1.8, color="#64748B", zorder=2,
                                     shrinkA=5.0, shrinkB=5.0))
        center_x, center_y = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
        vertical = abs(p[0] - q[0]) < .05
        ax.text(center_x + (.85 if vertical else 0),
                center_y + (0 if vertical else .49), label, fontsize=8.0,
                ha="center", va="center", color="#50647B", zorder=7,
                bbox={"facecolor": "white", "edgecolor": "none", "pad": 1.4})


def render() -> None:
    nodes, edges = parse_source()
    plt.rcParams.update({"font.family": ["Microsoft YaHei", "DejaVu Sans"],
                         "svg.fonttype": "none", "axes.unicode_minus": False})
    fig: Figure
    fig, ax = plt.subplots(figsize=(20, 12.5), dpi=175)
    fig.patch.set_facecolor("#F7F9FC")
    ax.set_facecolor("#F7F9FC")
    ax.set_xlim(0, 36.8)
    ax.set_ylim(0, 23)
    ax.set_aspect("equal")
    ax.axis("off")
    fig.subplots_adjust(left=.02, right=.98, top=.98, bottom=.02)
    ax.text(.70, 21.65, "API Token 中转站  |  按业务板块理解",
            color="#183047", fontsize=23.5, weight="bold", va="center")
    ax.text(.73, 20.61, "从注册、购买、充值与调用，到上游额度、数据统计和运营管理",
            color="#67788D", fontsize=12, va="center")
    ax.text(36.04, 21.66, "v1.0  ·  6 板块  ·  15 张物理表",
            color="#556781", fontsize=11.3, va="center", ha="right")
    ax.plot([.70, 36.07], [19.66, 19.66], color="#D9E2EA", lw=1)
    draw_arrows(ax, edges)
    for code in ("A", "B", "C", "D", "E", "F"):
        draw_card(ax, code, nodes[code])
    ax.text(.72, 1.66, "阅读方向：上排从左到右 → 右侧向下 → 下排从右向左。",
            fontsize=10.3, color="#32485E")
    ax.text(.72, 1.00,
            "箭头仅表示主要业务关联，不是完整外码图或强制执行顺序。实际用量统计直接来自调用数据；异常/补货也可独立触发。",
            fontsize=9.8, color="#6C7B8A")
    ax.text(.72, .42,
            "说明：本图按已迁移的 v1.0 绘制；v1.1 问题修补在另一隔离副本内。实体级关系另见 week6/er_diagram_v10.mmd。",
            fontsize=9.0, color="#6C7B8A")
    svg, png = ROOT / "overview_modules.svg", ROOT / "overview_modules.png"
    fig.savefig(svg, format="svg", bbox_inches="tight", pad_inches=.18)
    svg.write_text("\n".join(line.rstrip() for line in
                             svg.read_text(encoding="utf-8").splitlines()) + "\n",
                   encoding="utf-8")
    fig.savefig(png, format="png", dpi=175, bbox_inches="tight", pad_inches=.18)
    plt.close(fig)
    print(f"Business overview: {len(nodes)} modules, {len(PHYSICAL)} physical tables, "
          f"{len(edges)} primary associations -> {svg.name}, {png.name}")


if __name__ == "__main__":
    render()
