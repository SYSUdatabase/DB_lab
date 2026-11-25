SELECT p.quantity p,q.quantity q,o.status order_state,r.status restock_state,r.actual
FROM w13lab.Stock p CROSS JOIN w13lab.Stock q CROSS JOIN w13lab.OrderCase o
CROSS JOIN w13lab.RestockCase r WHERE p.product_id=1 AND q.product_id=2;
