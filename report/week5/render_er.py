"""Render the 14-entity Mermaid v0.1 source into presentation-ready vector and raster diagrams.

Only reads er_diagram.mmd; never connects to the database or reads any row values.
Requires matplotlib (already available on the demonstrated Windows host).
"""
from __future__ import annotations

import re
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "er_diagram.mmd"
ENTITY_RE = re.compile(r"^\s{4}(\w+)\s+\{\s*$")
EDGE_RE = re.compile(r"^\s{4}(\w+)\s+(o\||\|\||o\{|\|\{)--(o\||\|\||o\{|\|\{)\s+(\w+)\s*:\s*(\w+)\s*$")

# x,y represent card lower-left corners on a 17 x 13 grid.
LAYOUT = {
    "Roles": (0.45, 9.7), "Employees": (0.45, 6.2), "Users": (0.45, 2.4),
    "Products": (4.68, 9.65), "Orders": (4.68, 6.75),
    "OrderDetails": (4.68, 3.6), "TokenBalances": (4.68, 0.65),
    "UpstreamAccount": (8.91, 9.65), "Inventory": (8.91, 6.75),
    "InventoryLog": (8.91, 3.6), "RestockTask": (8.91, 0.65),
    "TokenUsageLogs": (13.14, 9.65), "UsageSummary": (13.14, 6.4),
    "ExceptionLog": (13.14, 3.05),
}
# Reserve dedicated header space; keep diagram cards below the title and legend.
LAYOUT = {name: (x, y - 1.10) for name, (x, y) in LAYOUT.items()}
TYPES = {
    "Roles": "权限元数据", "Employees": "员工", "Users": "会员",
    "Products": "销售套餐", "Orders": "订单", "OrderDetails": "订单明细",
    "TokenBalances": "会员余额", "UpstreamAccount": "上游账号",
    "Inventory": "额度快照", "InventoryLog": "额度流水",
    "RestockTask": "补货任务", "TokenUsageLogs": "调用流水",
    "UsageSummary": "期间汇总", "ExceptionLog": "异常处理",
}
W = 3.55
PANEL_H = 2.35
PALETTE = {
    "Roles": "#4F46E5", "Employees": "#4F46E5", "Users": "#4F46E5",
    "Products": "#0284C7", "Orders": "#0284C7", "OrderDetails": "#0284C7",
    "TokenBalances": "#0284C7",
    "UpstreamAccount": "#059669", "Inventory": "#059669",
    "InventoryLog": "#059669", "RestockTask": "#059669",
    "TokenUsageLogs": "#C47F0B", "UsageSummary": "#C47F0B",
    "ExceptionLog": "#C47F0B",
}


def read_source() -> tuple[dict[str, list[str]], list[tuple[str, str, str, str, str]]]:
    entities: dict[str, list[str]] = {}
    edges: list[tuple[str, str, str, str, str]] = []
    active: str | None = None
    for raw in SOURCE.read_text(encoding="utf-8").splitlines():
        if match := EDGE_RE.match(raw):
            edges.append(tuple(match.groups()))
        elif match := ENTITY_RE.match(raw):
            active = match.group(1)
            entities[active] = []
        elif active is not None and raw.strip() == "}":
            active = None
        elif active is not None and raw.strip():
            items = raw.strip().split()
            if len(items) >= 2:
                field = items[1]
                flags = items[2] if len(items) >= 3 else ""
                entities[active].append(field + (f"  [{flags}]" if flags else ""))
    if set(entities) != set(LAYOUT) or len(edges) != 17:
        raise ValueError(f"Unexpected ER source: {len(entities)} tables, {len(edges)} FKs")
    return entities, edges


def boundary(src: str, dst: str):
    xa, ya = LAYOUT[src]
    xb, yb = LAYOUT[dst]
    ca = (xa + W / 2, ya + PANEL_H / 2)
    cb = (xb + W / 2, yb + PANEL_H / 2)
    dx, dy = cb[0] - ca[0], cb[1] - ca[1]
    if abs(dx) > abs(dy) * 0.46:
        s = (xa + (W if dx > 0 else 0), ca[1])
        t = (xb if dx > 0 else xb + W, cb[1])
        off = (0.27 if dx > 0 else -0.27, 0)
    else:
        s = (ca[0], ya + (PANEL_H if dy > 0 else 0))
        t = (cb[0], yb if dy > 0 else yb + PANEL_H)
        off = (0, 0.19 if dy > 0 else -0.19)
    return s, t, off


def main() -> None:
    entities, edges = read_source()
    plt.rcParams["font.family"] = ["Microsoft YaHei", "DejaVu Sans"]
    plt.rcParams["svg.fonttype"] = "none"
    fig, ax = plt.subplots(figsize=(23.0, 17.0), dpi=200)
    fig.patch.set_facecolor("#FFFFFF")
    ax.set_facecolor("#FFFFFF")
    ax.set_xlim(0, 17.15)
    ax.set_ylim(-1.8, 13.1)
    ax.set_aspect("equal")
    ax.axis("off")
    ax.text(0.44, 12.47, "API Token 中转站  |  v0.1 物理 ER 模型", fontsize=22, weight="bold", color="#111827")
    ax.text(0.47, 12.05, "第五周 · 14 张业务表 · 17 条实际 FK · Crow's Foot · 以当前 DDL 为准", fontsize=11, color="#475569")
    ax.text(0.47, 11.66, "|| = 1..1    o| = 0..1    o{ = 0..N    |{ = 1..N     端点标的是对侧每条记录可关联的数量", fontsize=10, color="#334155")

    for i, (src, left, right, dst, fk) in enumerate(edges):
        s, t, offset = boundary(src, dst)
        color = PALETTE.get(src, "#64748B")
        bow = [0.055, -0.06, 0.12, -0.12][i % 4]
        line = FancyArrowPatch(s, t, arrowstyle="-", color=color,
                               mutation_scale=8, lw=1.5, alpha=0.32,
                               connectionstyle=f"arc3,rad={bow}", zorder=1)
        ax.add_patch(line)
        # Endpoint symbols convey the relation multiplicities. See mapping for role-specific participation.
        ax.text(s[0] + offset[0], s[1] + offset[1], left, fontsize=9, weight="bold",
                color=color, zorder=3, ha="center", va="center",
                bbox=dict(boxstyle="round,pad=0.08", facecolor="white", edgecolor="none", alpha=0.95))
        ax.text(t[0] - offset[0], t[1] - offset[1], right, fontsize=9, weight="bold",
                color=color, zorder=3, ha="center", va="center",
                bbox=dict(boxstyle="round,pad=0.08", facecolor="white", edgecolor="none", alpha=0.95))

    for table, fields in entities.items():
        x, y = LAYOUT[table]
        c = PALETTE[table]
        bg = FancyBboxPatch((x, y), W, PANEL_H, boxstyle="round,pad=0.02,rounding_size=0.13",
                            linewidth=1.4, edgecolor="#CBD5E1", facecolor="white", zorder=5)
        ax.add_patch(bg)
        header = FancyBboxPatch((x + 0.02, y + PANEL_H - 0.59), W - 0.04, 0.56,
                                boxstyle="round,pad=0.005,rounding_size=0.08",
                                linewidth=0, facecolor=c, zorder=6)
        ax.add_patch(header)
        ax.text(x + 0.16, y + PANEL_H - 0.27, table, color="white",
                fontsize=13, weight="bold", va="center", zorder=7)
        ax.text(x + W - 0.13, y + PANEL_H - 0.27, TYPES[table], color="white",
                fontsize=8.5, ha="right", va="center", zorder=7)
        for j, field in enumerate(fields[:8]):
            label = field.replace("  [", "   ").replace("]", "")
            if len(label) > 37:
                label = label[:36] + "…"
            ax.text(x + 0.18, y + PANEL_H - 0.87 - j * 0.185, label,
                    fontsize=8.4, color="#0F172A" if "PK" in field else "#334155",
                    weight="bold" if "PK" in field else "normal", zorder=7, va="center")
    ax.text(0.48, -1.40,
            "实线表示实际外键。此图只反映 v0.1 的结构性约束；订单至少一条明细、散客购买、跨表余额等业务规则见映射和问题清单。",
            fontsize=10.5, color="#475569")
    svg = ROOT / "er_diagram.svg"
    png = ROOT / "er_diagram.png"
    fig.savefig(svg, format="svg", bbox_inches="tight", pad_inches=0.28)
    # Matplotlib emits trailing spaces in multi-line SVG paths; normalize for Git checks.
    svg.write_text(
        "\n".join(line.rstrip() for line in svg.read_text(encoding="utf-8").splitlines()) + "\n",
        encoding="utf-8",
    )
    fig.savefig(png, format="png", dpi=200, bbox_inches="tight", pad_inches=0.28)
    plt.close(fig)
    print(f"rendered {len(entities)} entities, {len(edges)} FK relationships: {svg.name}, {png.name}")


if __name__ == "__main__":
    main()
