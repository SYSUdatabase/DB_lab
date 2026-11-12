"use strict";

// Stage-2 demonstration dashboard. Uses the normal same-origin, authenticated API.
const dashboardColors = {
  pending:"#E6A23C", paid:"#19977B", partially_refunded:"#5875CB",
  refunded:"#9271C5", cancelled:"#9BA7B7"
};
let dashboardBusy = false;

function dashboardNumber(value) {
  return Number(value || 0).toLocaleString("zh-CN");
}
function dashboardMoney(value) {
  return "¥ " + Number(value || 0).toLocaleString("zh-CN", {
    minimumFractionDigits:2, maximumFractionDigits:2
  });
}
function dashboardSvg(tag, attributes) {
  const node = document.createElementNS("http://www.w3.org/2000/svg", tag);
  for (const [key,value] of Object.entries(attributes)) node.setAttribute(key, String(value));
  return node;
}
function renderDashboard(data) {
  const m = data.metrics;
  const kpis = [
    ["全部订单", dashboardNumber(m.total_orders), "数据库当前保留的全部订单", "orders"],
    ["待支付订单", dashboardNumber(m.pending_orders), "状态为 pending", "pending"],
    ["已支付订单", dashboardNumber(m.paid_orders), "状态为 paid，不含已退款订单", "paid"],
    ["模拟已付金额", dashboardMoney(m.gross_paid_amount), "含后续退款订单的原始金额", "revenue"],
    ["模拟退款金额", dashboardMoney(m.refund_amount), "退款账本金额合计", "refund"],
    ["库存预警账号", dashboardNumber(m.low_stock_accounts), "当前有效账号低于安全阈值", "stock"]
  ];
  const cards = $("#dashboard-kpis");
  cards.replaceChildren();
  for (const [label,value,desc,kind] of kpis) {
    const card = el("article",undefined,"kpi-card "+kind);
    card.append(el("div",label,"kpi-label"),el("strong",value,"kpi-number"),el("p",desc,"kpi-caption"));
    cards.append(card);
  }

  const daily = data.daily_orders || [];
  const maxCount = Math.max(1, ...daily.map(d => Number(d.order_count) || 0));
  const trend = $("#dashboard-trend");
  trend.replaceChildren();
  for (const day of daily) {
    const count = Number(day.order_count) || 0;
    const bar = el("div",undefined,"trend-column");
    const track = el("div",undefined,"trend-track");
    const fill = el("div",undefined,"trend-bar");
    fill.style.height = (count === 0 ? 2 : Math.max(5, count / maxCount * 100)) + "%";
    if (count === 0) fill.classList.add("zero");
    track.append(fill);
    bar.title = day.day + " · " + count + " 单";
    bar.append(el("strong",dashboardNumber(count),"trend-value"),track,el("span",day.day.slice(5),"trend-day"));
    trend.append(bar);
  }
  if (!daily.length) trend.append(el("p","暂无订单趋势数据","empty-chart"));

  const distribution = $("#dashboard-status-chart");
  distribution.replaceChildren();
  const counts = data.statuses || [];
  const total = counts.reduce((sum,row) => sum + Number(row.order_count || 0),0);
  const ring = el("div",undefined,"donut-ring");
  const svg = dashboardSvg("svg",{
    viewBox:"0 0 160 160",role:"img","aria-label":"订单状态占比环形图"
  });
  svg.append(dashboardSvg("circle",{cx:80,cy:80,r:57,fill:"none",stroke:"#E8EDF4","stroke-width":19}));
  let offset=0;
  const circumference=2*Math.PI*57;
  for(const row of counts){
    const part=total?Number(row.order_count)/total:0;
    const circle=dashboardSvg("circle",{
      cx:80,cy:80,r:57,fill:"none",
      stroke:dashboardColors[row.status] || "#557086",
      "stroke-width":19,
      "stroke-dasharray":(part*circumference)+" "+circumference,
      "stroke-dashoffset":-(offset*circumference),
      transform:"rotate(-90 80 80)"
    });
    svg.append(circle);offset+=part;
  }
  const center = el("div",undefined,"donut-center");
  center.append(el("strong",dashboardNumber(total)),el("span","条订单"));
  ring.append(svg,center);
  const legend=el("div",undefined,"donut-legend");
  for(const row of counts){
    const item=el("div",undefined,"legend-item");
    const dot=el("i",undefined,"legend-dot");
    dot.style.backgroundColor=dashboardColors[row.status] || "#557086";
    item.append(dot,el("span",statuses[row.status] || row.status),el("strong",dashboardNumber(row.order_count)));
    legend.append(item);
  }
  if (!counts.length) legend.append(el("p","暂无订单数据","empty-chart"));
  distribution.append(ring,legend);

  const stock=$("#dashboard-stock");
  stock.replaceChildren();
  const items=data.low_stock || [];
  if (!items.length) {
    const ok=el("div",undefined,"stock-ok");
    ok.append(el("span","✓","stock-icon"),el("span","当前没有低于安全阈值的有效上游账号"));
    stock.append(ok);
  } else {
    for(const item of items) {
      const line=el("div",undefined,"stock-row");
      const name=el("div",undefined,"stock-name");
      name.append(el("strong",item.account_name),el("span",item.provider+" · #"+item.account_id));
      const quota=el("div",undefined,"stock-quota");
      quota.append(el("strong",dashboardNumber(item.current_quota)+" Token"),el("span","安全阈值 "+dashboardNumber(item.safety_threshold)));
      line.append(name,quota);stock.append(line);
    }
  }
  $("#dashboard-status").textContent="SQL Server 更新于 "+String(data.refreshed_at || "刚刚");
}
async function refreshDashboard(){
  if (dashboardBusy || state.section !== "dashboard" || !["staff","admin"].includes(state.role)) return;
  dashboardBusy=true;
  $("#dashboard-status").textContent="正在同步 SQL Server…";
  try {
    const data=await api("/dashboard");
    if(state.section==="dashboard" && ["staff","admin"].includes(state.role)) renderDashboard(data);
  } catch(error) {
    if(state.section==="dashboard") {
      $("#dashboard-status").textContent="刷新失败 · "+(error instanceof Error?error.message:"请检查连接");
    }
  } finally {
    dashboardBusy=false;
  }
}
$("#dashboard-refresh").addEventListener("click",refreshDashboard);
window.setInterval(()=>{
  if (!document.hidden && state.section==="dashboard") refreshDashboard();
},15000);
