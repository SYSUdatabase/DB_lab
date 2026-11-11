"""Render the editable Mermaid ER source with readable 0..* cardinalities.

The data model lives in er_diagram.mmd. This file only changes presentation:
loose, domain-aware node positions and obstacle-avoiding routed FK connectors.
No database access, DDL, or sensitive row reads.
"""
from __future__ import annotations

import heapq
import re
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "er_diagram.mmd"
ENTITY_RE = re.compile(r"^    (\w+) \{$")
EDGE_RE = re.compile(
    r"^    (\w+)\s+(o\||\|\||o\{|\|\{)(\.\.|--)(o\||\|\||o\{|\|\{)"
    r"\s+(\w+)\s*:\s*(\w+)$"
)
CARDINALITY = {"||": "1..1", "o|": "0..1", "o{": "0..*", "|{": "1..*"}
W, H = 4.05, 2.55
STEP = 0.25
CANVAS_X, CANVAS_Y = 33.9, 20.7
# Deliberately staggered placement, not a forced rectangular grid.
# New positions are presentation-only; the Mermaid source remains authoritative.
LAYOUT = {
    "Users": (0.65, 14.10),
    "Orders": (6.05, 14.65),
    "OrderDetails": (11.48, 14.35),
    "Products": (16.80, 14.90),
    "UpstreamAccount": (23.13, 13.45),
    "Inventory": (29.00, 15.35),
    "TokenBalances": (0.72, 9.33),
    "UsageSummary": (7.65, 9.12),
    "TokenUsageLogs": (15.55, 9.45),
    "InventoryLog": (28.53, 9.46),
    "RestockTask": (24.12, 4.55),
    "Employees": (17.34, 3.80),
    "Roles": (11.58, 4.10),
    "ExceptionLog": (11.40, 0.08),
}
TYPES = {
    "Roles": "角色", "Employees": "员工", "Users": "会员",
    "Products": "销售套餐", "Orders": "订单", "OrderDetails": "关联实体",
    "TokenBalances": "余额依赖", "UpstreamAccount": "上游账号",
    "Inventory": "快照依赖", "InventoryLog": "额度流水",
    "RestockTask": "补货任务", "TokenUsageLogs": "三方调用",
    "UsageSummary": "周期汇总", "ExceptionLog": "异常处理",
}
COLORS = {
    **dict.fromkeys(("Users", "Orders", "OrderDetails", "Products", "TokenBalances"), "#216EAC"),
    **dict.fromkeys(("UpstreamAccount", "Inventory", "InventoryLog", "RestockTask"), "#087D72"),
    **dict.fromkeys(("UsageSummary", "TokenUsageLogs"), "#A35C25"),
    **dict.fromkeys(("Roles", "Employees", "ExceptionLog"), "#6D54B0"),
}
# Side choices are kept explicit for diagram legibility, not DB semantics.
# L/R/T/B = left/right/top/bottom perimeter of a table.
SIDES = {
    ("Roles", "Employees", "role_id"): ("R", "L"),
    ("Users", "Orders", "user_id"): ("R", "L"),
    ("Users", "TokenBalances", "user_id"): ("B", "T"),
    ("Users", "TokenUsageLogs", "user_id"): ("R", "L"),
    ("Users", "UsageSummary", "user_id"): ("R", "L"),
    ("Orders", "OrderDetails", "order_id"): ("R", "L"),
    ("Products", "OrderDetails", "product_id"): ("L", "R"),
    ("Products", "TokenUsageLogs", "product_id"): ("B", "T"),
    ("Products", "UsageSummary", "product_id"): ("B", "T"),
    ("UpstreamAccount", "Inventory", "account_id"): ("R", "L"),
    ("UpstreamAccount", "InventoryLog", "account_id"): ("R", "T"),
    ("UpstreamAccount", "TokenUsageLogs", "account_id"): ("L", "R"),
    ("UpstreamAccount", "RestockTask", "account_id"): ("B", "T"),
    ("Employees", "InventoryLog", "operator_id"): ("R", "L"),
    ("Employees", "RestockTask", "created_by"): ("R", "L"),
    ("Employees", "RestockTask", "assigned_to"): ("R", "L"),
    ("Employees", "ExceptionLog", "handled_by"): ("B", "R"),
}


@dataclass(frozen=True)
class Link:
    src: str
    src_mark: str
    identifying_operator: str
    dst_mark: str
    dst: str
    fk: str


def read_model() -> tuple[dict[str, list[str]], list[Link]]:
    tables: dict[str, list[str]] = {}
    links: list[Link] = []
    current: str | None = None
    for row in SOURCE.read_text(encoding="utf-8").splitlines():
        if m := EDGE_RE.match(row):
            links.append(Link(*m.groups()))
        elif m := ENTITY_RE.match(row):
            current = m.group(1)
            tables[current] = []
        elif current and row.strip() == "}":
            current = None
        elif current and row.strip():
            parts = row.split()
            if len(parts) >= 2:
                field, flags = parts[1], (parts[2] if len(parts) > 2 else "")
                tables[current].append(f"{field}  {flags}".strip())
    if set(tables) != set(LAYOUT) or len(links) != 17:
        raise ValueError("Expected 14 editable entities and 17 FK links")
    if {tuple((v.src, v.dst, v.fk)) for v in links} != set(SIDES):
        raise ValueError("Routing side settings must correspond to every Mermaid FK")
    if any(link.identifying_operator != ".." for link in links):
        raise ValueError("All current FK columns are outside child primary keys; expected non-identifying links")
    return tables, links


def center(table: str) -> tuple[float, float]:
    x, y = LAYOUT[table]
    return x + W / 2, y + H / 2


def assign_ports(links: list[Link]) -> dict[tuple[int, str], tuple[float, float, str]]:
    uses: dict[tuple[str, str], list[tuple[int, str, float]]] = defaultdict(list)
    for i, edge in enumerate(links):
        left_side, right_side = SIDES[edge.src, edge.dst, edge.fk]
        uses[edge.src, left_side].append((i, "src", center(edge.dst)[1 if left_side in "LR" else 0]))
        uses[edge.dst, right_side].append((i, "dst", center(edge.src)[1 if right_side in "LR" else 0]))
    ports: dict[tuple[int, str], tuple[float, float, str]] = {}
    for (table, side), ends in uses.items():
        x, y = LAYOUT[table]
        ends.sort(key=lambda item: (item[2], item[0]))
        for j, (index, tag, _) in enumerate(ends, 1):
            f = j / (len(ends) + 1)
            if side == "L":
                point = (x, y + 0.35 + f * (H - 0.70), side)
            elif side == "R":
                point = (x + W, y + 0.35 + f * (H - 0.70), side)
            elif side == "T":
                point = (x + 0.35 + f * (W - 0.70), y + H, side)
            else:
                point = (x + 0.35 + f * (W - 0.70), y, side)
            # Snap the coordinate along the box edge to the routing grid.
            # This removes small diagonal kinks where paths leave their boxes.
            px, py, _ = point
            point = (px, round(py / STEP) * STEP, side) if side in "LR" else (round(px / STEP) * STEP, py, side)
            ports[index, tag] = point
    return ports


NORMAL = {"L": (-1, 0), "R": (1, 0), "T": (0, 1), "B": (0, -1)}
MOVES = ((1, 0), (0, 1), (-1, 0), (0, -1))


def snap(p: tuple[float, float]) -> tuple[int, int]:
    return round(p[0] / STEP), round(p[1] / STEP)


def route(
    start: tuple[float, float],
    end: tuple[float, float],
    forbidden: set[tuple[int, int]],
    occupancy: dict[tuple[int, int], int],
) -> list[tuple[float, float]]:
    """Four-direction A*, with large obstacle/crossing and turn penalties."""
    a, b = snap(start), snap(end)
    start_state = (*a, -1)
    best = {start_state: 0.0}
    previous: dict[tuple[int, int, int], tuple[int, int, int]] = {}
    queue: list[tuple[float, float, tuple[int, int, int]]] = [(0, 0, start_state)]
    target = None
    while queue:
        _, g, state = heapq.heappop(queue)
        if g > best.get(state, float("inf")) + 0.00001:
            continue
        x, y, old_dir = state
        if (x, y) == b:
            target = state
            break
        for direction, (dx, dy) in enumerate(MOVES):
            nx, ny = x + dx, y + dy
            if not (1 <= nx < CANVAS_X / STEP - 2 and 1 <= ny < CANVAS_Y / STEP - 2):
                continue
            if (nx, ny) in forbidden and (nx, ny) not in (a, b):
                continue
            crossing = occupancy.get((nx, ny), 0)
            adjacent = sum(occupancy.get((nx + ox, ny + oy), 0) > 0 for ox, oy in MOVES)
            bend = 2.7 if old_dir != -1 and direction != old_dir else 0
            ng = g + 1 + bend + 42 * crossing + adjacent * 0.8
            new = (nx, ny, direction)
            if ng < best.get(new, float("inf")):
                best[new] = ng
                previous[new] = state
                heur = (abs(nx - b[0]) + abs(ny - b[1])) * 1
                heapq.heappush(queue, (ng + heur, ng, new))
    if target is None:
        raise RuntimeError(f"No clear diagram route between {start} and {end}")
    chain = [target]
    while chain[-1] != start_state:
        chain.append(previous[chain[-1]])
    chain.reverse()
    return [(x * STEP, y * STEP) for x, y, _ in chain]


def reduce_collinear(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    kept: list[tuple[float, float]] = []
    for p in points:
        if kept and p == kept[-1]:
            continue
        kept.append(p)
        while len(kept) >= 3:
            a, b, c = kept[-3:]
            if abs((b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])) > 1e-5:
                break
            kept.pop(-2)
    return kept


def obstacle_cells() -> set[tuple[int, int]]:
    blocks: set[tuple[int, int]] = set()
    for x, y in LAYOUT.values():
        ix0, iy0 = snap((x - 0.20, y - 0.20))
        ix1, iy1 = snap((x + W + 0.20, y + H + 0.20))
        for i in range(ix0, ix1 + 1):
            for j in range(iy0, iy1 + 1):
                blocks.add((i, j))
    return blocks


def draw_edges(ax, edges: list[Link]) -> None:
    ports = assign_ports(edges)
    obstacles = obstacle_cells()
    occupancy: dict[tuple[int, int], int] = {}
    # Local links first, letting costly longer routes use the free corridors.
    order = sorted(range(len(edges)), key=lambda i: (
        abs(center(edges[i].src)[0] - center(edges[i].dst)[0])
        + abs(center(edges[i].src)[1] - center(edges[i].dst)[1])
    ))
    for i in order:
        edge = edges[i]
        first, last = ports[i, "src"], ports[i, "dst"]
        p, q = first[:2], last[:2]
        fx, fy = NORMAL[first[2]]
        lx, ly = NORMAL[last[2]]
        start = (p[0] + 0.73 * fx, p[1] + 0.73 * fy)
        stop = (q[0] + 0.73 * lx, q[1] + 0.73 * ly)
        interior = route(start, stop, obstacles, occupancy)
        for point in interior:
            cell = snap(point)
            occupancy[cell] = occupancy.get(cell, 0) + 1
        points = reduce_collinear([p, start, *interior, stop, q])
        xs, ys = zip(*points)
        # Export as solid connections for the course ER diagram.
        # Mermaid's ".." still records non-identifying FK semantics in the editable source;
        # visual line style here does NOT imply a child FK is part of its primary key.
        edge_color = "#6D54B0" if (edge.src, edge.dst) == ("Employees", "RestockTask") else "#74889E"
        ax.plot(xs, ys, color=edge_color, lw=1.65, linestyle="-",
                solid_capstyle="round", zorder=1)
        for xy in (p, q):
            ax.plot([xy[0]], [xy[1]], marker="o", ms=2.5, color="#64748B", zorder=4)
        for endpoint, mark in ((first, edge.src_mark), (last, edge.dst_mark)):
            x, y, side = endpoint
            dx, dy = NORMAL[side]
            # Only human-readable min..max labels. No crow's-foot symbols in exports.
            ax.text(x + 0.31 * dx, y + 0.31 * dy, CARDINALITY[mark],
                    size=8.2, color="#172A42", ha="center", va="center", zorder=7,
                    bbox=dict(facecolor="white", edgecolor="none", pad=0.7, alpha=0.94))
        if edge.src == "Employees" and edge.dst == "RestockTask":
            # Distinguish the two FK links sharing one parent/child pair.
            label_x = 22.58
            label_y = 6.78 if edge.fk == "created_by" else 5.25
            ax.text(label_x, label_y, edge.fk, fontsize=8.1, color="#6D54B0",
                    ha="left", va="center", zorder=8,
                    bbox=dict(facecolor="white", edgecolor="none", pad=0.8))


ATTRIBUTE_KIND = {
    ("OrderDetails", "subtotal"): "计算存储",
    ("OrderDetails", "total_tokens"): "计算存储",
    ("Orders", "total_amount"): "汇总存储",
    ("Orders", "total_tokens"): "汇总存储",
    ("Inventory", "current_quota"): "额度快照",
    ("TokenBalances", "remaining_tokens"): "余额快照",
    ("UsageSummary", "total_tokens_used"): "周期汇总",
    ("UsageSummary", "request_count"): "周期汇总",
}


def draw_nodes(ax, entities: dict[str, list[str]]) -> None:
    for name, (x, y) in LAYOUT.items():
        bg = FancyBboxPatch((x, y), W, H, boxstyle="round,pad=0.01,rounding_size=0.10",
                            facecolor="white", edgecolor="#CBD5E1", lw=1.0, zorder=3)
        ax.add_patch(bg)
        head = FancyBboxPatch((x + 0.02, y + H - 0.54), W - 0.04, 0.51,
                              boxstyle="round,pad=0.01,rounding_size=0.07",
                              facecolor=COLORS[name], edgecolor="none", zorder=4)
        ax.add_patch(head)
        ax.text(x + 0.12, y + H - 0.27, name, va="center", ha="left",
                color="white", fontweight="bold", fontsize=11.0, zorder=5)
        ax.text(x + W - 0.14, y + H - 0.27, TYPES[name], va="center", ha="right",
                color="white", fontsize=7.8, zorder=5)
        for j, field in enumerate(entities[name][:8]):
            column = field.split()[0]
            if annotation := ATTRIBUTE_KIND.get((name, column)):
                field += f"  ({annotation})"
            if len(field) > 39:
                field = field[:38] + "…"
            ax.text(x + 0.15, y + H - 0.77 - j * 0.218, field,
                    va="center", ha="left", fontsize=8.35, zorder=5,
                    color="#0F172A" if "PK" in field else "#334155",
                    fontweight="bold" if "PK" in field else "normal")


def main() -> None:
    tables, edges = read_model()
    plt.rcParams.update({"font.family": ["Microsoft YaHei", "DejaVu Sans"], "svg.fonttype": "none"})
    fig, ax = plt.subplots(figsize=(25, 15), dpi=170)
    fig.patch.set_facecolor("white")
    ax.set_xlim(-0.35, CANVAS_X)
    ax.set_ylim(-0.5, CANVAS_Y)
    ax.set_aspect("equal")
    ax.axis("off")
    # The assignment requires a legend; keep it inside the exported diagram.
    ax.text(0.65, 19.52, "API Token 中转站 | v0.1 物理 ER 模型",
            size=20, fontweight="bold", color="#13263D", ha="left")
    ax.text(0.65, 18.85, "图例  PK = 主码   UK = 候选/唯一键成员（复合 UK 需组合看）   FK = 外码   实线 = 实体之间的业务联系",
            fontsize=10.0, color="#334155", ha="left")
    ax.text(0.65, 18.43, "基数  0..1 = 可选一个   1..1 = 恰好一个   0..* = 零到多个   1..* = 至少一个；当前图按 v0.1 物理约束绘制",
            fontsize=10.0, color="#334155", ha="left")
    ax.text(0.65, 18.01, "双角色外码  Employees → RestockTask：created_by = 创建人（必填）   assigned_to = 被指派人（可空）",
            fontsize=10.0, color="#6D54B0", ha="left")
    draw_edges(ax, edges)
    draw_nodes(ax, tables)
    svg, png = ROOT / "er_diagram.svg", ROOT / "er_diagram.png"
    fig.savefig(svg, bbox_inches="tight", pad_inches=0.23, format="svg")
    svg.write_text(
        "\n".join(line.rstrip() for line in svg.read_text(encoding="utf-8").splitlines()) + "\n",
        encoding="utf-8",
    )
    fig.savefig(png, bbox_inches="tight", pad_inches=0.23, format="png", dpi=170)
    plt.close(fig)
    print(f"ER export: {len(tables)} entities, {len(edges)} physical FK links -> {svg.name}, {png.name}")


if __name__ == "__main__":
    main()
