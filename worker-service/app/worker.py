import asyncio
import os
import signal
import sys

try:
	import uvloop  # type: ignore
	asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())
except Exception:
	pass

import psycopg


def build_database_url() -> str:
	url = os.environ.get("DATABASE_URL")
	if url and "$(" not in url:
		return url
	user = os.environ.get("POSTGRES_USER", "app")
	password = os.environ.get("POSTGRES_PASSWORD", "app")
	host = os.environ.get("POSTGRES_HOST", "postgres.app.svc.cluster.local")
	db = os.environ.get("POSTGRES_DB", "app")
	port = os.environ.get("POSTGRES_PORT", "5432")
	return f"postgres://{user}:{password}@{host}:{port}/{db}"

DB_URL = build_database_url()
INTERVAL_SECONDS = int(os.environ.get("WORKER_INTERVAL_SECONDS", "5"))

_stop = asyncio.Event()

def _handle_signal(*_args) -> None:
	_stop.set()

signal.signal(signal.SIGTERM, _handle_signal)
signal.signal(signal.SIGINT, _handle_signal)


async def run_worker() -> None:
	if not DB_URL:
		print("DATABASE_URL is not set", file=sys.stderr)
		sys.exit(1)
	while not _stop.is_set():
		try:
			async with await psycopg.AsyncConnection.connect(DB_URL) as aconn:
				async with aconn.cursor() as cur:
					await cur.execute("SELECT NOW()")
					row = await cur.fetchone()
					print(f"worker-service heartbeat at {row[0]}")
		except Exception as exc:
			print(f"worker-service error: {exc}", file=sys.stderr)
		await asyncio.wait([_stop.wait()], timeout=INTERVAL_SECONDS)

if __name__ == "__main__":
	asyncio.run(run_worker())
