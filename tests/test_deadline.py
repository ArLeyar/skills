#!/usr/bin/env python3
"""Self-check for skills/consilium/deadline.py: exit codes match GNU `timeout -k`. Run: python3 tests/test_deadline.py"""
import signal, subprocess, sys, time
from pathlib import Path

D = str(Path(__file__).resolve().parents[1] / "skills/consilium/deadline.py")

def run(limit, *cmd, sig=None, wait=1.0):
    p = subprocess.Popen([sys.executable, D, "-k", "1", str(limit), *cmd])
    if sig:
        time.sleep(wait); p.send_signal(sig)
    return p.wait(timeout=20)

assert run(5, "sh", "-c", "exit 7") == 7                                   # child status passes through
assert run(1, "sleep", "9") == 124                                         # deadline
assert run(1, "sh", "-c", "trap '' TERM; sleep 9") == 137                  # TERM ignored -> KILL
assert run(30, "sleep", "9", sig=signal.SIGTERM) == 143                    # forwarded signal
assert run(30, "sh", "-c", "trap '' TERM; sleep 9", sig=signal.SIGTERM) == 137   # forwarded, ignored -> KILL clock
print("ok")
