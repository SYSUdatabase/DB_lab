"""Run the Week 13 two-session SQL scripts against a disposable WebW13 database."""

from __future__ import annotations

import argparse
import json
import re
import time
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack, closing
from datetime import datetime
from pathlib import Path

import pyodbc

SQL = Path(__file__).resolve().parents[1] / "sql/week13"


def source(name: str) -> str:
    return (SQL / f"{name}.sql").read_text(encoding="utf-8")


def steps(name: str, side: str) -> dict[str, str]:
    parts = re.split(r"(?m)^-- step: (\w+)\n", source(f"{name}_{side}"))
    return {
        key: re.sub(r"(?im)^GO\s*$", "", body).strip()
        for key, body in zip(parts[1::2], parts[2::2], strict=True)
    }


def connect(server: str, database: str) -> pyodbc.Connection:
    if not re.fullmatch(r"[A-Za-z0-9_.\\,-]+", server):
        raise ValueError("Expected a local-style SQL Server instance name")
    db = pyodbc.connect(
        f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={server};DATABASE={database};"
        "Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;",
        timeout=10,
        autocommit=True,
    )
    db.timeout = 20
    return db


def select(db: pyodbc.Connection, query: str, *params: int) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    with closing(db.cursor()) as cur:
        cur.execute(query, *params)
        while True:
            if cur.description is not None:
                names = [col[0] for col in cur.description]
                result.extend(dict(zip(names, row, strict=True)) for row in cur.fetchall())
            if not cur.nextset():
                return result


def require(condition: bool, details: object) -> None:
    if not condition:
        raise AssertionError(details)


def wait_info(db: pyodbc.Connection, waiter: int, blocker: int) -> dict[str, object]:
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        rows = select(
            db,
            """SELECT session_id,blocking_session_id,wait_type,wait_resource,wait_time
FROM sys.dm_exec_requests WHERE session_id=? AND blocking_session_id=?
AND wait_type LIKE 'LCK[_]M[_]%';""",
            waiter,
            blocker,
        )
        if rows:
            return rows[0]
        time.sleep(0.04)
    raise AssertionError(f"No observed lock wait for {waiter} blocked by {blocker}")


class Experiments:
    def __init__(
        self,
        a: pyodbc.Connection,
        b: pyodbc.Connection,
        observer: pyodbc.Connection,
        threads: ThreadPoolExecutor,
        evidence: Path,
    ) -> None:
        self.db = {"A": a, "B": b, "O": observer}
        self.threads = threads
        self.evidence = evidence
        self.info = {side: select(db, source("session"))[0] for side, db in self.db.items()}
        self.record("sessions", self.info)
        require(self.info["A"]["spid"] != self.info["B"]["spid"], self.info)
        self.rcsi = bool(self.info["B"]["is_read_committed_snapshot_on"])

    def record(self, name: str, result: object) -> None:
        row = {
            "time": datetime.now().isoformat(timespec="milliseconds"),
            "step": name,
            "result": result,
        }
        with self.evidence.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(row, ensure_ascii=False, default=str) + "\n")

    def step(self, exp: str, side: str, key: str) -> list[dict[str, object]]:
        self.record(f"{exp}.{key}.start", self.info[side]["spid"])
        value = select(self.db[side], steps(exp, side)[key])
        self.record(f"{exp}.{key}.end", value)
        return value

    def blocked(self, waiter: str, blocker: str, resource: str) -> None:
        db = self.db["O"]
        sid = int(str(self.info[waiter]["spid"]))
        owner = int(str(self.info[blocker]["spid"]))
        wait = wait_info(db, sid, owner)
        locks = select(
            db,
            """SELECT l.request_session_id,l.resource_type,l.resource_description,
 l.request_mode,l.request_status,OBJECT_NAME(p.object_id,DB_ID()) table_name
FROM sys.dm_tran_locks l LEFT JOIN sys.partitions p ON p.hobt_id=l.resource_associated_entity_id
WHERE l.resource_database_id=DB_ID() AND l.request_session_id IN (?,?)
 AND (OBJECT_SCHEMA_NAME(p.object_id,DB_ID())='w13lab' OR l.resource_type='APPLICATION')
ORDER BY l.request_session_id,l.resource_type,l.request_status;""",
            sid,
            owner,
        )
        self.record(f"{resource}.blocked", {"wait": wait, "locks": locks})
        table = None if resource.startswith("business.") else "Stock"
        if table:
            waiting = [
                lock
                for lock in locks
                if lock["request_session_id"] == sid
                and lock["request_status"] in ("WAIT", "CONVERT")
                and lock["table_name"] == table
            ]
            require(
                any(
                    held["request_session_id"] == owner
                    and held["request_status"] == "GRANT"
                    and held["resource_type"] == pending["resource_type"]
                    and held["resource_description"] == pending["resource_description"]
                    and held["table_name"] == table
                    for pending in waiting
                    for held in locks
                ),
                locks,
            )
        else:
            require(
                any(
                    row["request_session_id"] == sid
                    and row["resource_type"] == "APPLICATION"
                    and row["request_status"] == "WAIT"
                    for row in locks
                ),
                locks,
            )

    def reset(self) -> None:
        for side in ("A", "B"):
            state = select(self.db[side], "SELECT @@TRANCOUNT AS n;")
            require(state == [{"n": 0}], (side, state))
        select(self.db["O"], source("reset"))

    def final(self, p: int, q: int, paid: bool = False, received: bool = False) -> None:
        rows = select(self.db["O"], source("state"))
        self.record("state", rows)
        require(
            rows
            == [
                dict(
                    p=p,
                    q=q,
                    order_state="paid" if paid else "pending",
                    restock_state="completed" if received else "pending",
                    actual=5 if received else None,
                )
            ],
            rows,
        )

    def write_wait(self) -> None:
        name = "write_wait"
        for end, quantity in (("commit", 13), ("rollback", 15)):
            self.reset()
            self.step(name, "A", "A1")
            b = self.threads.submit(self.step, name, "B", "B1")
            self.blocked("B", "A", f"{name}.{end}.P")
            self.step(name, "A", f"A2_{end}")
            b.result()
            self.final(quantity, 8, paid=end == "commit", received=True)

    def dirty_read(self) -> None:
        name = "dirty_read"
        for key, quantity in (("B1_ru", 15), ("B1_rc", 10), ("B1_locking_rc", 10)):
            self.reset()
            self.step(name, "A", "A1")
            if key == "B1_ru" or (key == "B1_rc" and self.rcsi):
                rows = self.step(name, "B", key)
                self.step(name, "A", "A2")
            else:
                b = self.threads.submit(self.step, name, "B", key)
                self.blocked("B", "A", f"{name}.{key}.P")
                self.step(name, "A", "A2")
                rows = b.result()
            require(rows == [{"quantity": quantity}], rows)
            self.final(10, 8)

    def repeatable_read(self) -> None:
        name = "repeatable_read"
        self.reset()
        require(self.step(name, "A", "A1_rc") == [{"quantity": 10}], "RC first")
        self.step(name, "B", "B1")
        require(self.step(name, "A", "A2") == [{"quantity": 15}], "RC second")
        self.final(15, 8, received=True)
        self.reset()
        require(self.step(name, "A", "A1_rr") == [{"quantity": 10}], "RR first")
        b = self.threads.submit(self.step, name, "B", "B1")
        self.blocked("B", "A", f"{name}.RR.P")
        require(self.step(name, "A", "A2") == [{"quantity": 10}], "RR second")
        b.result()
        self.final(15, 8, received=True)

    def deadlock(self) -> None:
        name = "deadlock"
        self.reset()
        self.step(name, "A", "A1")
        self.step(name, "B", "B1_reverse")
        a = self.threads.submit(self.step, name, "A", "A2")
        self.blocked("A", "B", f"{name}.reverse.Q")
        victim = self.step(name, "B", "B2_reverse")
        require(
            len(victim) == 1 and victim[0]["error_number"] == 1205 and victim[0]["trancount"] == 0,
            victim,
        )
        a.result()
        self.final(8, 6, paid=True)
        self.reset()
        self.step(name, "A", "A1")
        b = self.threads.submit(self.step, name, "B", "B1_ordered")
        self.blocked("B", "A", f"{name}.ordered.P")
        self.step(name, "A", "A2")
        b.result()
        self.final(13, 11, paid=True, received=True)

    def competition(self) -> None:
        db = self.db["O"]
        fixture = select(db, "SELECT * FROM w13lab.Business;")[0]
        first, second = (int(str(fixture[key])) for key in ("order_a", "order_b"))
        unit, tokens = (int(str(fixture[key])) for key in ("units_per_pack", "token_per_pack"))
        task = int(str(fixture["task_id"]))
        self.record("business.fixture", fixture)
        baseline = select(db, "SELECT available_quota FROM w11.fn_ProviderSellable('Other');")[0]
        self.record("business.common_gate", select(db, source("business_gate_check")))
        a = self.db["A"]
        select(a, "BEGIN TRAN;")
        select(a, "EXEC w12.usp_CompleteOrder ?,0;", first)

        def restock_in_outer_transaction() -> list[dict[str, object]]:
            b = self.db["B"]
            select(b, "BEGIN TRAN;")
            try:
                select(b, "EXEC w12.usp_ReceiveRestock ?,5,0;", task)
                return select(
                    b, "SELECT status,actual_amount FROM dbo.RestockTask WHERE task_id=?;", task
                )
            finally:
                select(b, "IF @@TRANCOUNT>0 ROLLBACK;")

        restock = self.threads.submit(restock_in_outer_transaction)
        try:
            self.blocked("B", "A", "business.restock.Other")
        finally:
            select(a, "IF @@TRANCOUNT>0 ROLLBACK;")
        restock_result = restock.result()
        self.record("business.restock.tentative", restock_result)
        require(restock_result == [{"status": "completed", "actual_amount": 5}], restock_result)
        task_after = select(
            db, "SELECT status,actual_amount FROM dbo.RestockTask WHERE task_id=?;", task
        )
        self.record("business.restock.rolled_back", task_after)
        require(task_after == [{"status": "pending", "actual_amount": None}], task_after)
        select(a, "BEGIN TRAN;")
        select(a, "EXEC w12.usp_CompleteOrder ?,0;", first)

        def compete() -> list[dict[str, object]]:
            return select(
                self.db["B"],
                """BEGIN TRY EXEC w12.usp_CompleteOrder ?,0;
 SELECT 0 error_number,@@TRANCOUNT trancount;
END TRY BEGIN CATCH SELECT ERROR_NUMBER() error_number,@@TRANCOUNT trancount; END CATCH;""",
                second,
            )

        b = self.threads.submit(compete)
        try:
            self.blocked("B", "A", "business.Other")
        except BaseException:
            select(a, "IF @@TRANCOUNT>0 ROLLBACK;")
            raise
        select(a, "COMMIT;")
        rejected = b.result()
        self.record("business.loser", rejected)
        require(rejected == [{"error_number": 53132, "trancount": 0}], rejected)
        rows = select(
            db,
            """SELECT o.order_id,o.status,o.paid_at,
 COALESCE(b.remaining_tokens,0) balance,COUNT(l.detail_id) lots,
 COALESCE(SUM(l.issued_tokens),0) issued
FROM dbo.Orders o LEFT JOIN dbo.TokenBalances b ON b.user_id=o.user_id AND b.model_provider='Other'
JOIN dbo.OrderDetails d ON d.order_id=o.order_id LEFT JOIN dbo.OrderTokenLots l ON l.detail_id=d.detail_id
WHERE o.order_id IN (?,?) GROUP BY o.order_id,o.status,o.paid_at,b.remaining_tokens ORDER BY o.order_id;""",
            first,
            second,
        )
        capacity = select(
            db, "SELECT available_quota,outstanding_upstream FROM w11.fn_ProviderSellable('Other');"
        )[0]
        self.record("business.orders", rows)
        self.record("business.capacity", capacity)
        require(
            len(rows) == 2
            and rows[0]["status"] == "paid"
            and rows[0]["paid_at"] is not None
            and rows[0]["balance"] == rows[0]["issued"] == 6 * tokens
            and rows[0]["lots"] == 1
            and rows[1]["status"] == "pending"
            and rows[1]["paid_at"] is None
            and rows[1]["lots"] == rows[1]["balance"] == rows[1]["issued"] == 0
            and capacity["available_quota"] == baseline["available_quota"]
            and int(str(capacity["available_quota"])) - int(str(capacity["outstanding_upstream"]))
            == 4 * unit,
            (rows, capacity),
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suffix", required=True)
    parser.add_argument("--server", default=r"localhost\SQLEXPRESS")
    args = parser.parse_args()
    if not re.fullmatch(r"WebW13[A-Za-z0-9]{2,9}", args.suffix):
        parser.error("Use a new dedicated WebW13 batch suffix")
    database = "TokenHubDB_v11_" + args.suffix
    folder = SQL.parents[1] / "result" / "week13" / args.suffix
    folder.mkdir(parents=True, exist_ok=True)
    evidence = folder / "concurrency.jsonl"
    with evidence.open("x", encoding="utf-8"):
        pass
    with ExitStack() as stack:
        a, b, obs = [stack.enter_context(closing(connect(args.server, database))) for _ in range(3)]
        threads = stack.enter_context(ThreadPoolExecutor(max_workers=2))
        if not select(obs, "SELECT SCHEMA_ID('w13lab') AS id;")[0]["id"]:
            select(obs, source("init"))
        ex = Experiments(a, b, obs, threads, evidence)
        for scenario in (ex.write_wait, ex.dirty_read, ex.repeatable_read, ex.deadlock):
            scenario()
            ex.record(scenario.__name__, "PASS")
        if not select(obs, "SELECT OBJECT_ID('w13lab.Business','U') AS id;")[0]["id"]:
            select(obs, source("business_fixture"))
        ex.competition()
        ex.reset()
        ex.record("competition", "PASS")
    print(f"PASS Week 13 concurrency; {evidence}")


if __name__ == "__main__":
    main()
