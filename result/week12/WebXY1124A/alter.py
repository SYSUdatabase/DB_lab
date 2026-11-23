"""Re-create w12.usp_CompleteOrder from the repository file: 'fixed' as committed, 'old' without the provider lock."""
import re, sys, pathlib
import pyodbc
db, mode = sys.argv[1], sys.argv[2]
text = pathlib.Path("sql/week12/order_transaction.sql").read_text(encoding="utf-8")
body = text[text.index("CREATE PROCEDURE w12.usp_CompleteOrder"):]
body = body[:body.index("\nGO\n")].replace("$(DatabaseName)", db).replace("CREATE PROCEDURE", "ALTER PROCEDURE", 1)
lock = re.search(r"  -- 核对可售余量之前.*?WHERE provider IN \(SELECT provider FROM @credit\);\n", body, re.S).group(0)
if mode == "old":
    body = body.replace(lock, "")
c = pyodbc.connect("DRIVER={ODBC Driver 18 for SQL Server};SERVER=localhost\\SQLEXPRESS;DATABASE=" + db +
                   ";Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;", autocommit=True)
k = c.cursor(); k.execute("SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON;"); k.execute(body)
d = k.execute("SELECT OBJECT_DEFINITION(OBJECT_ID('w12.usp_CompleteOrder'))").fetchval()
print("proc", mode, "provider_lock_present=", "FROM dbo.UpstreamAccount WITH(UPDLOCK,HOLDLOCK)" in d)
