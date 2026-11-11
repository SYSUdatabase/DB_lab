"""One-command reproduction of an independent v1.1 incl. refund accounting.

Creates new v1.0 + v1.1 names, SQL CHECKSUM backups, synthetic reconciliation,
approved issue fixes, managed account workflows and refund regression.
No original database is changed. Never rerun with an existing suffix.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent

def run(name: str, *args: str) -> None:
    p=subprocess.run([sys.executable,"-B",str(HERE/name),*args],
                     cwd=ROOT,check=False)
    if p.returncode!=0:raise RuntimeError("Stopped at "+name+"; earlier backups and failure logs retained")
    print("PASS",name,flush=True)

def main() -> None:
    parser=argparse.ArgumentParser()
    parser.add_argument("--suffix",required=True,
       help="Unique 6-16 character alphanumeric suffix, starting with a letter")
    parser.add_argument("--server",default=r"localhost\SQLEXPRESS")
    args=parser.parse_args()
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]{5,15}",args.suffix):
        raise SystemExit("Invalid new isolated DB suffix")
    db="TokenHubDB_v11_"+args.suffix
    evidence=ROOT/"result/week6/v11"/args.suffix
    if evidence.exists():
        raise SystemExit("Target evidence folder exists; never overwrite: "+str(evidence))
    run("build_sandbox.py","--server",args.server,"--suffix",args.suffix)
    run("repair_generated_history.py","--server",args.server,
        "--database",db,"--apply",
        "--audit",str(evidence/"synthetic_repair_audit.json"))
    run("deploy_extension.py","--server",args.server,
        "--database",db,"--log-dir",str(evidence))
    run("install_refund.py","--server",args.server,
        "--database",db,"--log-dir",str(evidence))
    run("validate_hardened.py","--server",args.server,
        "--database",db,"--log-dir",str(evidence/"final_validation"))
    run("qa_approved_rules.py")
    print("PASS COMPLETE unified 17-table / 20-FK v1.1 with refund; source unchanged",db)

if __name__=="__main__":main()
