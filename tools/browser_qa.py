"""Run the installed Tabbit CLI with a private in-memory local fixture password."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--request-id", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--script", type=Path, default=ROOT / "tools/browser_qa.js")
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Refusing to overwrite browser evidence")
    password = os.environ.get("DB_LAB_DEMO_PASSWORD", "")
    script = args.script.read_text(encoding="utf-8").replace(
        "__DEMO_PASSWORD__", json.dumps(password)
    )
    cli = Path(os.environ["LOCALAPPDATA"]) / "Tabbit/LocalAgent/bin/tabbit-cli.exe"
    result = subprocess.run(
        [
            str(cli),
            "nodejs",
            "--task",
            "TokenHub QA",
            "--request-id",
            args.request_id,
            "--timeout-ms",
            "120000",
        ],
        input=script.encode(),
        capture_output=True,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    output = result.stdout.decode("utf-8")
    args.output.write_text(output, encoding="utf-8")
    print(output)
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
