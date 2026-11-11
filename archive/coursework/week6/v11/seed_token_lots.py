"""One-time FIFO historical token-lot provenance for the verified synthetic seed.

Derived from immutable orders, paid_at, OrderDetails and token usage events.
Never assigns lots for old 'refunded' rows: the legacy examples did not credit
TokenBalances and have no external payout evidence.
"""
from __future__ import annotations
import argparse
from collections import defaultdict, deque
from pathlib import Path
import re
import json
import hashlib
import pyodbc

def main() -> None:
    ap=argparse.ArgumentParser()
    ap.add_argument("--database",required=True)
    ap.add_argument("--server",default=r"localhost\SQLEXPRESS")
    ap.add_argument("--manifest",type=Path,required=True)
    args=ap.parse_args()
    if not re.fullmatch(r"TokenHubDB_v11_[A-Za-z0-9_]+",args.database):
        raise SystemExit("Only isolated v1.1 sandbox names allowed")
    if args.manifest.exists():
        raise RuntimeError("Refuse to overwrite existing lot seeding manifest")
    db=pyodbc.connect("DRIVER={ODBC Driver 18 for SQL Server};SERVER="+args.server
      +";DATABASE="+args.database
      +";Trusted_Connection=yes;TrustServerCertificate=yes;",autocommit=False)
    try:
        if db.execute("SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0").fetchval()!=17:
            raise RuntimeError("Refund schema missing")
        if db.execute("SELECT COUNT(*) FROM dbo.OrderTokenLots").fetchval() != 0:
            raise RuntimeError("Historical lots already populated")
        if db.execute("SELECT COUNT(*) FROM dbo.RefundLedger").fetchval() != 0:
            raise RuntimeError("Refunds already exist")
        if db.execute("SELECT COUNT(*) FROM dbo.Orders WHERE status='paid'").fetchval()!=85:
            raise RuntimeError("Unexpected synthetic paid history")
        if db.execute("SELECT COUNT(*) FROM dbo.TokenUsageLogs").fetchval()!=3000:
            raise RuntimeError("Unexpected synthetic usage history")
        credits=list(db.execute("""
          SELECT d.detail_id,o.user_id,p.model_provider,o.paid_at,d.total_tokens
          FROM dbo.OrderDetails d JOIN dbo.Orders o ON o.order_id=d.order_id
          JOIN dbo.Products p ON p.product_id=d.product_id
          WHERE o.status='paid' ORDER BY o.paid_at,d.detail_id
        """))
        debits=list(db.execute("""
          SELECT l.log_id,l.user_id,p.model_provider,l.used_at,l.tokens_used
          FROM dbo.TokenUsageLogs l JOIN dbo.Products p ON p.product_id=l.product_id
          ORDER BY l.used_at,l.log_id
        """))
        if len(credits)!=158:
            raise RuntimeError("Expected 158 seeded paid order-detail lots")
        events=[(x[3],0,int(x[0]),int(x[1]),str(x[2]),int(x[4])) for x in credits]
        events.extend((x[3],1,int(x[0]),int(x[1]),str(x[2]),int(x[4])) for x in debits)
        events.sort(key=lambda x:(x[0],x[1],x[2]))
        queue:dict[tuple[int,str],deque]=defaultdict(deque)
        used=defaultdict(int)
        issued={}
        for ts,kind,row_id,user,provider,amount in events:
            key=(user,provider)
            if kind==0:
                issued[row_id]=amount
                queue[key].append([row_id,amount])
                continue
            remaining=amount
            while remaining:
                if not queue[key]:
                    raise RuntimeError(f"Historical usage has no paid lot for {key} event {row_id}")
                lot=queue[key][0]
                piece=min(remaining,lot[1])
                used[lot[0]]+=piece
                lot[1]-=piece
                remaining-=piece
                if lot[1]==0:
                    queue[key].popleft()
        expected=defaultdict(int)
        for key, lots in queue.items():
            expected[key]=sum(qty for _,qty in lots)
        balances={(int(u),str(prov)):int(n) for u,prov,n in db.execute(
          "SELECT user_id,model_provider,remaining_tokens FROM dbo.TokenBalances"
        )}
        if any(expected.get(k,0)!=v for k,v in balances.items()):
            raise RuntimeError("Historical FIFO lot balances do not match TokenBalances")
        if any(v!=balances.get(k,0) for k,v in expected.items()):
            raise RuntimeError("Lot balance contains a provider without corresponding TokenBalances row")
        inserts=[(int(x[0]),x[3],int(x[4]),used[int(x[0])])
                 for x in credits]
        for detail_id,ts,tokens,consumed in inserts:
            db.execute("""INSERT dbo.OrderTokenLots
              (detail_id,credited_at,issued_tokens,consumed_tokens,refunded_tokens)
              VALUES(?,?,?,?,0)""",detail_id,ts,tokens,consumed)
        if db.execute("SELECT COUNT(*) FROM dbo.OrderTokenLots").fetchval()!=158:
            raise RuntimeError("Lot seed insert count mismatch")
        fingerprint=hashlib.sha256(
          json.dumps([(x[0],x[2],x[3]) for x in inserts],sort_keys=True).encode()
        ).hexdigest()
        db.commit()
    except BaseException:
        db.rollback()
        raise
    finally:db.close()
    data={"database":args.database,"legacy_paid_lots":len(inserts),
          "historical_usage_events":len(debits),"total_issued":sum(x[2] for x in inserts),
          "total_consumed":sum(x[3] for x in inserts),
          "total_remaining":sum(x[2]-x[3] for x in inserts),
          "lot_allocation_sha256":fingerprint,
          "policy":"FIFO by paid_at/detail_id, paid credits before same-second usage; legacy refunded excluded"}
    args.manifest.parent.mkdir(parents=True,exist_ok=True)
    args.manifest.write_text(json.dumps(data,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    print("PASS FIFO historical token lot allocation and balance reconciliation",data)

if __name__=="__main__":main()
