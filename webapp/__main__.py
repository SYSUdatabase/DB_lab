"""Local production WSGI server; never enables Flask debug mode."""

import os

from waitress import serve

from . import create_app

if __name__ == "__main__":
    serve(
        create_app(), host="127.0.0.1", port=int(os.environ.get("DB_LAB_PORT", "5050")), threads=6
    )
