"""Wait for the metastore and Valkey. Managed by the dashboard Helm chart.

usage: wait_for_dependencies.py [--migrations]

Loads superset_config.py exactly as Superset will (overrides included), so it
waits for the endpoints Superset will actually use. With --migrations it also
waits until the metastore schema is at this image's alembic head: a web or
worker pod on a new image then stays in Init until the init Job has migrated,
instead of serving against the old schema.
"""

import ast
import importlib.util
import os
import socket
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit

MIGRATIONS_DIR = "/app/superset/migrations"
DEFAULT_PORTS = {"postgresql": 5432, "mysql": 3306, "redis": 6379, "rediss": 6379}


def log(msg):
    print(f"[wait-for-dependencies] {msg}", flush=True)


def load_config():
    spec = importlib.util.spec_from_file_location(
        "superset_config", os.environ["SUPERSET_CONFIG_PATH"]
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def wait_tcp(name, host, port, deadline):
    while True:
        try:
            with socket.create_connection((host, port), timeout=3):
                log(f"{name} is accepting connections at {host}:{port}")
                return
        except OSError as exc:
            if time.monotonic() > deadline:
                raise SystemExit(f"{name} at {host}:{port} unreachable: {exc}")
            log(f"waiting for {name} at {host}:{port} ({exc.__class__.__name__})")
            time.sleep(3)


def migration_graph():
    """(all revisions, head revisions), read from the migration files' source.

    Parsed, not imported: Superset's migration modules import its models,
    which refuse to load outside an initialized app — so alembic's own
    ScriptDirectory cannot be used here.
    """
    revisions, parents = set(), set()
    for path in Path(MIGRATIONS_DIR, "versions").rglob("*.py"):
        values = {}
        for node in ast.parse(path.read_text()).body:
            if isinstance(node, ast.Assign) and len(node.targets) == 1:
                target, value = node.targets[0], node.value
            elif isinstance(node, ast.AnnAssign) and node.value is not None:
                target, value = node.target, node.value
            else:
                continue
            if isinstance(target, ast.Name) and target.id in ("revision", "down_revision"):
                try:
                    values[target.id] = ast.literal_eval(value)
                except ValueError:
                    pass
        if isinstance(values.get("revision"), str):
            revisions.add(values["revision"])
            down = values.get("down_revision")
            parents.update([down] if isinstance(down, str) else down or [])
    return revisions, revisions - parents


def wait_migrations(uri, deadline):
    # Imported late: only this path needs the metastore driver.
    from sqlalchemy import create_engine, text
    from sqlalchemy.pool import NullPool

    known, heads = migration_graph()
    if not heads:
        raise SystemExit(f"no alembic revisions found under {MIGRATIONS_DIR}")
    engine = create_engine(uri, poolclass=NullPool)
    while True:
        try:
            with engine.connect() as conn:
                current = {
                    row[0]
                    for row in conn.execute(text("SELECT version_num FROM alembic_version"))
                }
        except Exception as exc:  # pylint: disable=broad-except
            # The class only: driver messages can echo connection parameters.
            current = None
            reason = exc.__class__.__name__
        if current == heads:
            log(f"metastore schema is at head {sorted(heads)}")
            return
        if current and not current <= known:
            raise SystemExit(
                f"metastore schema {sorted(current)} is NEWER than this image "
                f"(head {sorted(heads)}). Running an older Superset against a "
                "newer schema is unsupported; roll the image forward."
            )
        if time.monotonic() > deadline:
            raise SystemExit("timed out waiting for the init Job to migrate the metastore")
        if current is None:
            state = f"not readable yet ({reason})"
        elif not current:
            state = "empty"
        else:
            state = f"at {sorted(current)}"
        log(f"metastore schema {state}; waiting for {sorted(heads)} (the init Job migrates it)")
        time.sleep(5)


def main():
    deadline = time.monotonic() + int(os.environ.get("WAIT_TIMEOUT_SECONDS", "900"))
    config = load_config()

    from sqlalchemy.engine import make_url

    url = make_url(config.SQLALCHEMY_DATABASE_URI)
    backend = url.get_backend_name()
    wait_tcp("metastore", url.host, url.port or DEFAULT_PORTS.get(backend, 5432), deadline)

    broker = urlsplit(config.CELERY_CONFIG.broker_url)
    wait_tcp("valkey", broker.hostname, broker.port or DEFAULT_PORTS[broker.scheme], deadline)

    if "--migrations" in sys.argv[1:]:
        wait_migrations(config.SQLALCHEMY_DATABASE_URI, deadline)


if __name__ == "__main__":
    main()
