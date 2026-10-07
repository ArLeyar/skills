#!/usr/bin/env python3
"""Stand-in for `timeout -k KILL LIMIT cmd...` where GNU timeout is absent (stock macOS).
Same exit codes: 124 deadline hit, 137 child needed KILL, else the child's own status."""
import os, signal, subprocess, sys, time

kill_after, limit, cmd = int(sys.argv[2]), int(sys.argv[3]), sys.argv[4:]
child, term_at, got = None, None, None   # term_at: when the child was first told to stop

def stop(sig):
    try: os.killpg(child.pid, sig)
    except ProcessLookupError: pass

def on_signal(n, _f):   # runner's cleanup kill lands here; it starts the same KILL clock a deadline does
    global term_at, got
    got = got or n
    if child:
        if term_at is None: term_at = time.monotonic()   # the KILL clock starts once; every signal is still forwarded
        stop(n)

for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGQUIT):
    if signal.getsignal(s) != signal.SIG_IGN:   # keep an inherited ignore, as `nohup` sets for HUP
        signal.signal(s, on_signal)   # before the spawn: a signal in between would strand the child with no deadline

child = subprocess.Popen(cmd, start_new_session=True)
if got and term_at is None: term_at = time.monotonic(); stop(got)

start, timed_out, killed = time.monotonic(), False, False
while child.poll() is None:
    now = time.monotonic()
    if term_at is None and now >= start + limit: timed_out, term_at = True, now; stop(signal.SIGTERM)
    if term_at is not None and not killed and now >= term_at + kill_after: killed = True; stop(signal.SIGKILL)
    time.sleep(0.05)

rc = child.returncode
sys.exit(137 if killed else 124 if timed_out else 128 - rc if rc < 0 else rc)
