#!/usr/bin/env python3
"""Stand-in for `timeout -k KILL LIMIT cmd...` where GNU timeout is absent (stock macOS).
Same exit codes: 124 deadline hit, 137 child needed KILL, else the child's own status."""
import os, signal, subprocess, sys

kill_after, limit, cmd = int(sys.argv[2]), int(sys.argv[3]), sys.argv[4:]
child = subprocess.Popen(cmd, start_new_session=True)

def stop(sig):
    try: os.killpg(child.pid, sig)
    except ProcessLookupError: pass

for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(s, lambda n, _f: stop(n))   # runner's cleanup kill reaches the seat through here

def code(rc): return 128 - rc if rc < 0 else rc

try:
    sys.exit(code(child.wait(limit)))
except subprocess.TimeoutExpired:
    stop(signal.SIGTERM)
    try:
        child.wait(kill_after); sys.exit(124)
    except subprocess.TimeoutExpired:
        stop(signal.SIGKILL); child.wait(); sys.exit(137)
