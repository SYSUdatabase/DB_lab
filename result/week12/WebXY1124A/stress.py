"""Concurrent completion stress for week 12: 6 customers x 20 orders, direct SQL and web entry."""
import json, re, sys, threading, uuid, time
from collections import Counter
import pyodbc
DB = sys.argv[1]; LABEL = sys.argv[2]
CS = ("DRIVER={ODBC Driver 18 for SQL Server};SERVER=localhost\\SQLEXPRESS;DATABASE=" + DB +
      ";Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;")
pyodbc.pooling = False
def c(auto=True):
    x = pyodbc.connect(CS, autocommit=auto, timeout=10); x.timeout = 60; return x
def nums(e): return tuple(sorted({int(n) for n in re.findall(r"\((\d{3,5})\)", str(e))}))
s = c(); k = s.cursor(); k.execute("SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON;")
tag = uuid.uuid4().hex[:6]
pid = k.execute("SET NOCOUNT ON; INSERT dbo.Products(name,description,price,model_provider,token_amount,required_upstream_tokens,status) VALUES(?,N'stress',3.00,'Other',?,1000,'active'); SELECT CONVERT(INT,SCOPE_IDENTITY())", "STRESS_P_"+tag, 1000+int(tag,16)%900000).fetchval()
k.execute("INSERT dbo.UpstreamAccount(provider,account_name,api_key,total_quota,used_quota,safety_threshold,status,expires_at) VALUES('Other',?,?,100000000,0,1000,'active','20271231')", "STRESS_A_"+tag, "sk-stress-"+tag)
users = []
for i in range(6):
    tg = uuid.uuid4().hex[:10]
    u = k.execute("SET NOCOUNT ON; INSERT dbo.Users(username,password_hash,email,created_at) VALUES(?,?,?,DATEADD(DAY,-1,SYSDATETIME())); SELECT CONVERT(INT,SCOPE_IDENTITY())", "stress_"+tg, "fixture-unusable", tg+"@example.invalid").fetchval()
    t = uuid.uuid4().bytes*2; k.execute("EXEC app.StartSession 'customer',?,?", u, t).fetchall(); users.append((u, t))
def order(u):
    return k.execute("SET NOCOUNT ON; DECLARE @o INT; EXEC dbo.usp_W5_CreateRegisteredOrder ?,@emit_result=0,@app_result_id=@o OUTPUT; EXEC dbo.usp_W5_AddMergedOrderItem @o,?,1,@emit_result=0; SELECT @o", u, pid).fetchval()
def direct(o):
    x = c()
    try: x.cursor().execute("EXEC w12.usp_CompleteOrder ?,@emit_result=0", o); return "ok"
    except pyodbc.Error as e: return str(nums(e))
    finally: x.close()
def web(t, o):
    x = c(auto=False); kk = x.cursor()
    try:
        kk.execute("EXECUTE AS USER=N'app_runtime_probe'")
        kk.execute("EXEC app.[Execute] ?,?,?", t, "orders.pay", json.dumps({"order_id": o})).fetchall(); x.commit(); return "ok"
    except pyodbc.Error as e: x.rollback(); return str(nums(e))
    finally: x.close()
def race(args):
    res=[None]*len(args); bar=threading.Barrier(len(args))
    def run(i): bar.wait(); res[i]=args[i][0](*args[i][1:])
    th=[threading.Thread(target=run,args=(i,)) for i in range(len(args))]; [t.start() for t in th]; [t.join() for t in th]; return res
N = 20
ids = [[order(u) for _ in range(N)] for u, _ in users]
t0 = time.time(); rr = race([(lambda l: [direct(o) for o in l], l) for l in ids]); d1 = time.time()-t0
ids = [[order(u) for _ in range(N)] for u, _ in users]
t0 = time.time(); rr2 = race([(lambda t, l: [web(t, o) for o in l], users[i][1], ids[i]) for i in range(6)]); d2 = time.time()-t0
inv = k.execute("SELECT COUNT(*) FROM dbo.Inventory i JOIN dbo.UpstreamAccount a ON a.account_id=i.account_id WHERE i.current_quota<>a.total_quota-a.used_quota").fetchval()
bal = k.execute("""SELECT COUNT(*) FROM dbo.TokenBalances b WHERE b.remaining_tokens<>
 (SELECT COALESCE(SUM(l.issued_tokens-l.consumed_tokens-l.refunded_tokens),0) FROM dbo.OrderTokenLots l JOIN dbo.OrderDetails d ON d.detail_id=l.detail_id
  JOIN dbo.Orders o ON o.order_id=d.order_id JOIN dbo.Products p ON p.product_id=d.product_id WHERE o.user_id=b.user_id AND p.model_provider=b.model_provider)""").fetchval()
print(f"{LABEL}|direct|{dict(Counter(r for l in rr for r in l))}|{d1:.1f}s")
print(f"{LABEL}|web|{dict(Counter(r for l in rr2 for r in l))}|{d2:.1f}s")
print(f"{LABEL}|consistency|inventory_mismatch={inv}|balance_lot_mismatch={bal}|trancount={k.execute('SELECT @@TRANCOUNT').fetchval()}")
