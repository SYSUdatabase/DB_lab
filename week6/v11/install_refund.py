"""One-time refund migration in a named, BACKED-UP isolated v1.1; never touch source DB."""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

import pyodbc
from seed_token_lots import main as _seed_main  # command-line runner through subprocess below

ROOT=Path(__file__).resolve().parents[2]
TEMPLATE="TokenHubDB_v11_Issues_20261014"
FILES=("07_refund_schema.sql","08_accounting_lots.sql","09_refund_workflow.sql")

def run_sql(server:str,db:str,name:str,log_dir:Path)->None:
    target=log_dir/(name+".log")
    if target.exists():
        if "PASS" not in target.read_text(encoding="utf-8-sig"):
            raise RuntimeError("Old failure log exists; do not overwrite "+str(target))
        print("ALREADY PASS",name);return
    src=(ROOT/"week6/v11"/name).read_text(encoding="utf-8-sig")
    if TEMPLATE not in src:raise RuntimeError("Template guard missing "+name)
    with tempfile.TemporaryDirectory(prefix="refund_sql_") as folder:
        p=Path(folder)/"task.sql"
        p.write_text(src.replace(TEMPLATE,db),encoding="utf-8")
        cmd=subprocess.run(["sqlcmd","-S",server,"-d",db,"-E","-C","-b","-r","1",
                            "-f","65001","-i",str(p)],
                           capture_output=True,text=True,encoding="utf-8",errors="replace")
    msg=cmd.stdout+cmd.stderr
    target.write_text(msg,encoding="utf-8")
    if cmd.returncode or "PASS" not in msg:
        raise RuntimeError(name+" failed: "+msg[-1300:])
    print("PASS",name)

def main()->None:
    ap=argparse.ArgumentParser()
    ap.add_argument("--server",default=r"localhost\SQLEXPRESS")
    ap.add_argument("--database",required=True)
    ap.add_argument("--log-dir",required=True,type=Path)
    args=ap.parse_args()
    if not re.fullmatch(r"TokenHubDB_v11_[A-Za-z0-9_]+",args.database):
        raise SystemExit("Only independent v1.1 database allowed")
    log_dir=args.log_dir
    if not log_dir.is_dir() or not any((log_dir/n).exists() for n in ("baseline_clone.log","copy_v10_to_v11.txt")):
        raise RuntimeError("A backed-up independent v1.1 clone is required")
    run_sql(args.server,args.database,FILES[0],log_dir)
    manifest=log_dir/"lots_manifest.json"
    if not manifest.exists():
        result=subprocess.run(
          ["python","-B",str(ROOT/"week6/v11/seed_token_lots.py"),
           "--server",args.server,"--database",args.database,
           "--manifest",str(manifest)],
          capture_output=True,text=True,encoding="utf-8",errors="replace")
        (log_dir/"seed_token_lots.log").write_text(result.stdout+result.stderr,encoding="utf-8")
        if result.returncode:raise RuntimeError("Historical lot seeding failed; see log")
        print("PASS historical FIFO lots")
    else:
        print("ALREADY PASS historical FIFO lot manifest exists")
    for name in FILES[1:]:run_sql(args.server,args.database,name,log_dir)
    print("PASS refund migration on isolated test clone",args.database)
if __name__=="__main__":main()
