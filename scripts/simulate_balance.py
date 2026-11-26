"""Run seeded four-bot lobbies and commit each finished game to SQLite."""

import argparse
import ctypes
from ctypes import wintypes
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
MEMORY_LIMIT_BYTES = 10_000_000_000
LOBBY_TIMEOUT_SECONDS = 300
WORKER_SCRIPT = "res://scripts/simulate_balance.gd"


def cap_windows_process_tree():
    """Put the coordinator and every Godot child under one committed-memory limit."""
    if os.name != "nt":
        raise RuntimeError("The balance runner currently enforces its memory cap on Windows.")

    class BasicLimits(ctypes.Structure):
        _fields_ = [
            ("process_time", ctypes.c_longlong), ("job_time", ctypes.c_longlong),
            ("flags", wintypes.DWORD), ("min_working_set", ctypes.c_size_t),
            ("max_working_set", ctypes.c_size_t), ("active_processes", wintypes.DWORD),
            ("affinity", ctypes.c_size_t), ("priority", wintypes.DWORD),
            ("scheduling", wintypes.DWORD),
        ]

    class ExtendedLimits(ctypes.Structure):
        _fields_ = [
            ("basic", BasicLimits), ("io_counters", ctypes.c_ulonglong * 6),
            ("process_memory", ctypes.c_size_t), ("job_memory", ctypes.c_size_t),
            ("peak_process_memory", ctypes.c_size_t), ("peak_job_memory", ctypes.c_size_t),
        ]

    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateJobObjectW.argtypes = (wintypes.LPVOID, wintypes.LPCWSTR)
    kernel.CreateJobObjectW.restype = wintypes.HANDLE
    kernel.GetCurrentProcess.restype = wintypes.HANDLE
    kernel.SetInformationJobObject.argtypes = (
        wintypes.HANDLE, ctypes.c_int, wintypes.LPVOID, wintypes.DWORD,
    )
    kernel.QueryInformationJobObject.argtypes = (
        wintypes.HANDLE, ctypes.c_int, wintypes.LPVOID, wintypes.DWORD, ctypes.c_void_p,
    )
    kernel.AssignProcessToJobObject.argtypes = (wintypes.HANDLE, wintypes.HANDLE)
    job = kernel.CreateJobObjectW(None, None)
    limits = ExtendedLimits()
    limits.basic.flags = 0x0200 | 0x2000  # Limit job memory and terminate children if the runner dies.
    limits.job_memory = MEMORY_LIMIT_BYTES
    info_class = 9  # JobObjectExtendedLimitInformation
    if not job or not kernel.SetInformationJobObject(job, info_class, ctypes.byref(limits), ctypes.sizeof(limits)):
        raise ctypes.WinError(ctypes.get_last_error())
    if not kernel.AssignProcessToJobObject(job, kernel.GetCurrentProcess()):
        raise ctypes.WinError(ctypes.get_last_error())

    def peak_memory():
        info = ExtendedLimits()
        if not kernel.QueryInformationJobObject(job, info_class, ctypes.byref(info), ctypes.sizeof(info), None):
            raise ctypes.WinError(ctypes.get_last_error())
        return info.peak_job_memory

    # Windows closes the non-inherited job handle when this coordinator exits.
    return peak_memory


def snapshot_rules(project, godot):
    """Freeze rules for the batch so edits to the game cannot mix versions in one database."""
    paths = sorted((ROOT / "src/core").rglob("*.gd"))
    paths += [ROOT / "src/view/app/scoring_reference.gd", ROOT / "scripts/simulate_balance.gd"]
    digest = hashlib.sha256()
    for path in paths:
        relative = path.relative_to(ROOT)
        target = project / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        contents = path.read_bytes()
        target.write_bytes(contents)
        digest.update(relative.as_posix().encode("utf-8"))
        digest.update(hashlib.sha256(contents).digest())
    (project / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="Zeitklus Balance Simulation"\n', encoding="utf-8",
    )
    result = subprocess.run([
        str(godot), "--headless", "--audio-driver", "Dummy", "--path", str(project),
        "--log-file", str(project / "import.log"), "--editor", "--import", "--quit",
    ], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
        encoding="utf-8", errors="replace", timeout=60, creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode or any(line.startswith(("ERROR:", "SCRIPT ERROR:")) for line in result.stderr.splitlines()):
        raise RuntimeError(f"Could not import the balance project.\n{result.stderr[-4000:]}")
    with godot.open("rb") as engine:
        for chunk in iter(lambda: engine.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def initialize_database(db, budget, rules):
    db.execute("PRAGMA foreign_keys = ON")
    db.execute("PRAGMA journal_mode = WAL")
    db.executescript("""
        CREATE TABLE IF NOT EXISTS settings (
            id INTEGER PRIMARY KEY CHECK (id = 1), manifest TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS matches (
            seed INTEGER PRIMARY KEY, rounds INTEGER NOT NULL, winner_seat INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS multipliers (
            family TEXT NOT NULL, type TEXT NOT NULL, multiplier REAL NOT NULL,
            PRIMARY KEY (family, type)
        );
        CREATE TABLE IF NOT EXISTS hands (
            seed INTEGER NOT NULL REFERENCES matches(seed),
            round INTEGER NOT NULL, seat INTEGER NOT NULL, score INTEGER NOT NULL,
            hand_type TEXT NOT NULL, context_type TEXT NOT NULL, context_group TEXT NOT NULL,
            base INTEGER NOT NULL, hand_multi REAL NOT NULL, context_multi REAL NOT NULL,
            field_multi REAL NOT NULL, cards INTEGER NOT NULL, round_winner INTEGER NOT NULL,
            hand_components TEXT NOT NULL, context_counts TEXT NOT NULL,
            PRIMARY KEY (seed, round, seat)
        );
        CREATE VIEW IF NOT EXISTS bracketed_hands AS
            SELECT *, CASE
                WHEN score = 0 THEN 0 WHEN score < 50 THEN 1 WHEN score < 100 THEN 50
                WHEN score < 200 THEN 100 WHEN score < 400 THEN 200 ELSE 400
            END AS bracket_min FROM hands;
    """)
    manifest = json.dumps({"rules_and_engine": rules, "search_budget": budget}, sort_keys=True)
    with db:
        db.execute("INSERT OR IGNORE INTO settings VALUES (1, ?)", (manifest,))
        saved, = db.execute("SELECT manifest FROM settings WHERE id = 1").fetchone()
        if saved != manifest:
            raise ValueError("This database uses different game rules or a different search budget.")


def consolidate_lobby(db, seed, file):
    with file.open(encoding="utf-8") as stream:
        records = [json.loads(line) for line in stream]
    if not records:
        raise ValueError(f"Seed {seed} did not produce any records.")
    match = records.pop()
    rounds, winner = match["rounds"], match["winner_seat"]
    if match["seed"] != seed or rounds <= 0 or len(records) != rounds * 4 or not 1 <= winner <= 4:
        raise ValueError(f"Incomplete or invalid result for seed {seed}.")
    rows = []
    for index, record in enumerate(records):
        if record["round"] != index // 4 + 1 or record["seat"] != index % 4 + 1:
            raise ValueError(f"Unexpected round or seat in seed {seed}.")
        rows.append((
            seed, record["round"], record["seat"], record["score"], record["hand_type"],
            record["context_type"], record["context_group"], record["base"], record["hand_multi"],
            record["context_multi"], record["field_multi"], record["cards"], record["round_winner"],
            json.dumps(record["hand_components"]), json.dumps(record["context_counts"]),
        ))
    with db:
        match_insert = db.execute("INSERT OR IGNORE INTO matches VALUES (?, ?, ?)", (seed, rounds, winner))
        if match_insert.rowcount:
            if not db.execute("SELECT 1 FROM multipliers LIMIT 1").fetchone():
                db.executemany("INSERT INTO multipliers VALUES (?, ?, ?)", (
                    (family, name, value)
                    for family, types in match["multipliers"].items()
                    for name, value in types.items()
                ))
            db.executemany("INSERT INTO hands VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", rows)
    file.unlink()


def simulate(db, args, scratch, project):
    first, end = args.seed_start, args.seed_start + args.games
    existing = {seed for seed, in db.execute("SELECT seed FROM matches WHERE seed >= ? AND seed < ?", (first, end))}
    seeds = iter(seed for seed in range(first, end) if seed not in existing)
    completed = len(existing)
    started = time.monotonic()
    active = {}
    try:
        while completed < args.games:
            while len(active) < args.workers:
                seed = next(seeds, None)
                if seed is None:
                    break
                result, errors = scratch / f"{seed}.jsonl", scratch / f"{seed}.log"
                engine_log = scratch / f"{seed}.engine.log"
                with errors.open("wb") as stderr:
                    proc = subprocess.Popen([
                        str(args.godot), "--headless", "--audio-driver", "Dummy",
                        "--log-file", str(engine_log), "--path", str(project), "--script", WORKER_SCRIPT, "--",
                        str(seed), str(args.work_budget), str(result),
                    ], stdout=subprocess.DEVNULL, stderr=stderr, creationflags=subprocess.CREATE_NO_WINDOW)
                active[seed] = (proc, result, errors, engine_log, time.monotonic())

            for seed, (proc, result, errors, engine_log, launched) in list(active.items()):
                status = proc.poll()
                if status is None:
                    if time.monotonic() - launched > LOBBY_TIMEOUT_SECONDS:
                        raise RuntimeError(f"Seed {seed} timed out.")
                    continue
                diagnostics = errors.read_text(encoding="utf-8", errors="replace")
                if status != 0 or any(line.startswith(("ERROR:", "SCRIPT ERROR:")) for line in diagnostics.splitlines()):
                    raise RuntimeError(f"Seed {seed} exited with status {status}.\n{diagnostics[-4000:]}")
                consolidate_lobby(db, seed, result)
                errors.unlink()
                engine_log.unlink(missing_ok=True)
                del active[seed]
                completed += 1
                if completed % 100 == 0 or completed == args.games:
                    print(f"{completed:,}/{args.games:,} games saved in {time.monotonic() - started:.1f}s", flush=True)
            if active:
                time.sleep(0.025)
    finally:
        for proc, *_ in active.values():
            if proc.poll() is None:
                proc.terminate()
            proc.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=os.environ.get("SHIFT_GODOT_BIN"), required="SHIFT_GODOT_BIN" not in os.environ)
    parser.add_argument("--database", type=Path, default=ROOT / "build/balance/standard.sqlite")
    parser.add_argument("--games", type=int, default=10000)
    parser.add_argument("--workers", type=int, default=12, choices=range(1, 13))
    parser.add_argument("--seed-start", type=int, default=132801)
    parser.add_argument("--work-budget", type=int, default=4096, help="Maximum search checkpoints per bot and hand")
    args = parser.parse_args()
    if args.games <= 0 or args.work_budget <= 0 or not 0 <= args.seed_start < args.seed_start + args.games <= 2**31:
        parser.error("Use a positive game count and search budget, and keep all seeds in the signed 32-bit range.")
    args.godot = args.godot.resolve(strict=True)
    args.database = args.database.resolve()
    args.database.parent.mkdir(parents=True, exist_ok=True)
    peak_memory = cap_windows_process_tree()
    with tempfile.TemporaryDirectory(prefix=".balance-workers-", dir=args.database.parent) as scratch:
        project = Path(scratch) / "project"
        rules = snapshot_rules(project, args.godot)
        with sqlite3.connect(args.database, timeout=30) as db:
            initialize_database(db, args.work_budget, rules)
            simulate(db, args, Path(scratch), project)
            db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        db.close()
    print(f"Peak committed memory: {peak_memory() / 1_000_000_000:.2f} GB of 10 GB")
    print(f"Results: {args.database}")


if __name__ == "__main__":
    main()
