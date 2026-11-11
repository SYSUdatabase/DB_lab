"""Run Week 10 integration assertions and retain a new, non-overwriting evidence directory."""

from __future__ import annotations

import argparse
import io
import json
import os
import re
import sys
import time
import unittest
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class EvidenceResult(unittest.TextTestResult):
    """Capture individual outcomes and SQL boundary inputs without session credentials."""

    def __init__(self, stream: io.TextIOBase, descriptions: bool, verbosity: int) -> None:
        super().__init__(stream, descriptions, verbosity)
        self.cases: list[dict[str, object]] = []
        self.started = 0.0

    def startTest(self, test: unittest.TestCase) -> None:
        self.started = time.monotonic()
        super().startTest(test)

    def record(self, test: unittest.TestCase, status: str, detail: str = "") -> None:
        self.cases.append(
            {
                "test": test.id(),
                "status": status,
                "elapsed_seconds": round(time.monotonic() - self.started, 4),
                "expected": "All explicit unittest assertions pass",
                "actual": detail or "All assertions passed",
                "database_calls": getattr(test, "events", []),
            }
        )

    def addSuccess(self, test: unittest.TestCase) -> None:
        super().addSuccess(test)
        self.record(test, "PASS")

    def addError(self, test: unittest.TestCase, err: tuple) -> None:
        super().addError(test, err)
        self.record(test, "ERROR", self._exc_info_to_string(err, test))

    def addFailure(self, test: unittest.TestCase, err: tuple) -> None:
        super().addFailure(test, err)
        self.record(test, "FAIL", self._exc_info_to_string(err, test))

    def addSkip(self, test: unittest.TestCase, reason: str) -> None:
        super().addSkip(test, reason)
        self.record(test, "SKIP", reason)

    def addSubTest(
        self, test: unittest.TestCase, subtest: unittest.TestCase, err: tuple | None
    ) -> None:
        super().addSubTest(test, subtest, err)
        if err is not None:
            self.record(subtest, "FAIL", self._exc_info_to_string(err, test))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", default=os.environ.get("DB_LAB_WEEK10_DATABASE", ""))
    parser.add_argument(
        "--server", default=os.environ.get("DB_LAB_TEST_SERVER", r"localhost\SQLEXPRESS")
    )
    parser.add_argument("--run-id", default="Verify" + datetime.now().strftime("%Y%m%dT%H%M%S%f"))
    args = parser.parse_args()
    if (
        not re.fullmatch(r"TokenHubDB_v11_Web[A-Za-z0-9_]+", args.database)
        or "base" in args.database.lower()
    ):
        parser.error(
            "--database must explicitly select an isolated extension Web database, excluding baseline databases"
        )
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,90}", args.run_id):
        parser.error("--run-id must contain 1–90 letters, digits, underscores or hyphens")
    evidence = ROOT / "result" / "week10" / args.run_id
    evidence.mkdir(parents=True, exist_ok=False)
    os.environ["DB_LAB_WEEK10_DATABASE"] = args.database
    os.environ["DB_LAB_APP_DATABASE"] = args.database
    os.environ["DB_LAB_TEST_SERVER"] = args.server
    sys.path.insert(0, str(ROOT))
    output = io.StringIO()
    runner = unittest.TextTestRunner(stream=output, verbosity=2, resultclass=EvidenceResult)
    suite = unittest.defaultTestLoader.discover(str(ROOT / "tests"), pattern="test_week10*.py")
    result = runner.run(suite)
    log = output.getvalue()
    (evidence / "unittest.log").write_text(log, encoding="utf-8")
    summary = {
        "utc_time": datetime.now(UTC).isoformat(),
        "database": args.database,
        "server": args.server,
        "tests_run": result.testsRun,
        "failures": len(result.failures),
        "errors": len(result.errors),
        "skipped": len(result.skipped),
        "passed": result.wasSuccessful() and not result.skipped and result.testsRun > 0,
        "cases": result.cases,
        "fixture_policy": "SQL test transactions roll back. Two-connection tests retain uniquely tagged committed fixtures in the isolated database.",
    }
    (evidence / "results.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2, default=str) + "\n", encoding="utf-8"
    )
    print(log, end="")
    print("Evidence saved to " + str(evidence))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
