#!/usr/bin/env bash
# consilium runner: one brief, three models in parallel, arranged to work blind, one answer file per model.
# usage: run.sh <dir> [high|medium|low]     (tier default: high; <dir> holds brief.md and no earlier run)
#   reads  <dir>/brief.md
#   writes <dir>/{claude,codex,agy}.md  answers
#          <dir>/<seat>.err  stderr;  <dir>/codex.log and <dir>/agy.log  raw transcripts
#          <dir>/status.tsv  seat<TAB>state   state = ok | no-position | timeout | exit:<n> | no-result | skipped | missing:<cmd> | brief-too-large
#          <dir>/panel.txt   tier, deadline, and per seat the model and its final state (written after the run)
#   exit   0 = at least one usable answer, 1 = seats ran and none is usable, 2 = refused before any paid call
# tiers:  high   = fable  / gpt-6-astra / gemini-3.8-flash-high
#         medium = opus   / gpt-5.6-sol / gemini-3.8-flash-high
#         low    = sonnet / gpt-5.6-terra / gemini-3.8-flash-low
# env:    CONSILIUM_SKIP="codex,agy" (or space-separated)   CONSILIUM_TIMEOUT=540 (seconds per seat, 60..570)
#         CONSILIUM_CLAUDE_BUDGET=5 (USD)   CONSILIUM_{CLAUDE,CODEX,AGY}_MODEL override one seat of any tier
# isolation is arrangement, not a sandbox: every seat starts in its own empty dir under an unguessable temp root
# outside <dir>, gets no path to the others, and is told there is nothing to look for. codex (read-only sandbox)
# and agy (plan mode) can still read the filesystem if they go looking (measured 2026-09-16).
# transport lessons come from fleet/agy/bin/agy-roles and fleet/codex/bin/review-pr, measured there:
# agy takes the prompt as ONE NDJSON line on stdin (argv is capped and visible in ps), silently delivers only part
# of a prompt above ~165 KB while reporting SUCCESS, and exits 0 on CANCELED — the result's status field decides.
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

[ $# -ge 1 ] || { echo "usage: run.sh <dir> [high|medium|low]" >&2; exit 2; }
dir=$(cd -- "$1" 2>/dev/null && pwd -P) || { echo "no such dir: $1" >&2; exit 2; }
tier=${2:-high}
cd "$dir" || exit 2
[ -s brief.md ] || { echo "no brief at $dir/brief.md" >&2; exit 2; }
mkdir status.d 2>/dev/null || { echo "$dir already holds a run; use a fresh dir" >&2; exit 2; }   # atomic claim, kept after the run
trap 'rm -rf status.d' EXIT   # a refusal before launch leaves no run marker; replaced by cleanup once seats start
TO=$(command -v timeout || command -v gtimeout) || { echo "GNU timeout missing (brew install coreutils gives gtimeout); no paid seat starts without a deadline" >&2; exit 2; }
"$TO" --version 2>/dev/null | grep -q GNU || { echo "$TO is not GNU timeout; brew install coreutils" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 missing; needed to build and read agy's stream-json" >&2; exit 2; }

case "$tier" in
  high)   claude_m=fable;  codex_m=gpt-6-astra; agy_m=gemini-3.8-flash-high ;;
  medium) claude_m=opus;   codex_m=gpt-5.6-sol; agy_m=gemini-3.8-flash-high ;;
  low)    claude_m=sonnet; codex_m=gpt-5.6-terra; agy_m=gemini-3.8-flash-low ;;
  *) echo "unknown tier: $tier (high|medium|low)" >&2; exit 2 ;;
esac
claude_m=${CONSILIUM_CLAUDE_MODEL:-$claude_m}
codex_m=${CONSILIUM_CODEX_MODEL:-$codex_m}
agy_m=${CONSILIUM_AGY_MODEL:-$agy_m}

limit=${CONSILIUM_TIMEOUT:-540}
case "$limit" in ''|*[!0-9]*) echo "CONSILIUM_TIMEOUT must be integer seconds" >&2; exit 2 ;; esac
limit=$((10#$limit))   # "090" would otherwise be read as octal in the arithmetic below
[ "$limit" -ge 60 ] && [ "$limit" -le 570 ] || { echo "CONSILIUM_TIMEOUT out of range 60..570 (caller's tool cap is 600s)" >&2; exit 2; }
budget=${CONSILIUM_CLAUDE_BUDGET:-5}
[[ $budget =~ ^[0-9]+(\.[0-9]+)?$ ]] && ! [[ $budget =~ ^0*(\.0*)?$ ]] || { echo "CONSILIUM_CLAUDE_BUDGET must be a positive decimal USD amount" >&2; exit 2; }

skip=",$(printf %s "${CONSILIUM_SKIP:-}" | tr ' \t' ',,' | tr -s ','),"
active=0
for s in ${skip//,/ }; do
  case "$s" in claude|codex|agy) ;; *) echo "unknown seat in CONSILIUM_SKIP: $s" >&2; exit 2 ;; esac
done
for s in claude codex agy; do case "$skip" in *",$s,"*) ;; *) active=$((active + 1)) ;; esac; done
[ "$active" -gt 0 ] || { echo "all seats skipped; nothing to run" >&2; exit 2; }

wdroot=$(mktemp -d "${TMPDIR:-/tmp}/consilium-wd.XXXXXX") || { echo "mktemp failed" >&2; exit 2; }
# agy's stdin message is built HERE, before any seat starts: a failure must stay an exit 2 with nothing spent.
# One NDJSON line, built by python because the brief carries quotes and backslashes. Above 165 KB agy has been
# measured to deliver part of the prompt and report SUCCESS, so that seat is refused instead.
agy_state=""
case "$skip" in *",agy,"*) ;; *)
  if [ "$(wc -c < brief.md)" -gt 165000 ]; then agy_state=brief-too-large
  else
    python3 -c 'import json,sys
c=open(sys.argv[1],encoding="utf-8",newline="",errors="surrogateescape").read()
json.dump({"event":"user","message":{"role":"user","content":c}},sys.stdout); sys.stdout.write("\n")' brief.md > "$wdroot/agy.ndjson" \
      || { echo "could not build agy's stream-json message" >&2; rm -rf "$wdroot"; exit 2; }
  fi ;;
esac
echo "tier=$tier timeout=${limit}s" > panel.txt

pids=(); started=()
cleanup() { trap - INT TERM HUP EXIT; [ ${#pids[@]} -gt 0 ] && kill "${pids[@]}" 2>/dev/null; rm -rf "$wdroot"; }
trap 'cleanup; exit 130' INT TERM HUP
trap cleanup EXIT   # a runner that dies takes its seats with it, or they keep billing

run() { # run <seat> <stdout-file> <stdin-file> <cmd...>
  local seat=$1 out=$2 in=$3; shift 3
  case "$skip" in *",$seat,"*) echo skipped > "status.d/$seat"; return ;; esac
  command -v "$1" >/dev/null || { echo "missing:$1" > "status.d/$seat"; return; }
  mkdir "$wdroot/$seat" || { echo "exit:mkdir" > "status.d/$seat"; return; }
  # exec makes the job's pid the timeout's pid, so cleanup's kill reaches the seat through timeout's forwarding
  ( cd "$wdroot/$seat" && exec "$TO" -k 30 "$limit" "$@" ) > "$dir/$out" 2> "$dir/$seat.err" < "$in" &
  pids+=("$!"); started+=("$seat")
}

# claude: prompt on stdin; no hooks, no user settings, no MCP, no skills, no file tools, no transcript, capped spend
run claude claude.md brief.md claude -p --model "$claude_m" --permission-mode dontAsk --permission-prompts none \
  --tools "WebSearch,WebFetch" --setting-sources "" --strict-mcp-config --disable-slash-commands \
  --no-session-persistence --max-budget-usd "$budget"
# codex: prompt on stdin via "-"; no user config or rules, effort set here since the config is ignored;
# -o carries the clean final message, stdout is the transcript (codex.log)
run codex codex.log brief.md codex exec --skip-git-repo-check --ephemeral --ignore-user-config --ignore-rules \
  -C "$wdroot/codex" -s read-only --color never -m "$codex_m" -c 'model_reasoning_effort="high"' -o "$dir/codex.md" -
# agy: the NDJSON message built above on stdin; --print='' MUST stay attached (as two words --print eats the next
# flag as its prompt); output is the NDJSON stream, parsed after the run. --print-timeout sits ABOVE the deadline
# so GNU timeout is the only authority. --disable-slash-commands is deliberately absent: it switches --mode plan off.
if [ -n "$agy_state" ]; then echo "$agy_state" > status.d/agy
else
  run agy agy.log "$wdroot/agy.ndjson" agy --print='' --input-format stream-json --output-format stream-json \
    --mode plan --model "$agy_m" --print-timeout "$((limit + 60))s"
fi

usable() { grep -qiE '^#{1,4} *Position\**:? *$' "$1" 2>/dev/null && grep -qiE '^#{1,4} *Confidence\**:? *$' "$1" 2>/dev/null; }

for i in "${!pids[@]}"; do
  wait "${pids[$i]}"; rc=$?; seat=${started[$i]}
  if [ "$seat" = agy ] && [ "$rc" -eq 0 ]; then
    # exactly one result event, status SUCCESS, non-empty response — anything else is no-result, whatever the exit code
    python3 -c 'import json,sys
r=[e.get("result") for e in (json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip()) if isinstance(e,dict) and e.get("event")=="result"]
ok=len(r)==1 and isinstance(r[0],dict) and r[0].get("status")=="SUCCESS" and str(r[0].get("response","")).strip()
if not ok: print("agy: no single SUCCESS result with a response", file=sys.stderr); sys.exit(1)
print(r[0]["response"])' "$dir/agy.log" > "$dir/agy.md" 2>> "$dir/agy.err" || rc=no-result
  fi
  case "$rc" in
    124|137) echo timeout ;;   # 124 = deadline; 137 = timeout's own KILL after TERM was ignored. 143 stays exit:143: the CLI may exit so itself
    no-result) echo no-result ;;
    0) if usable "$dir/$seat.md"; then echo ok; else echo no-position; fi ;;
    *) echo "exit:$rc" ;;
  esac > "status.d/$seat"
done
pids=()

for s in claude codex agy; do printf '%s\t%s\n' "$s" "$(cat "status.d/$s")"; done > status.tsv
for s in claude codex agy; do
  case "$s" in claude) m=$claude_m ;; codex) m=$codex_m ;; agy) m=$agy_m ;; esac
  printf '%s=%s %s\n' "$s" "$m" "$(cat "status.d/$s")"
done >> panel.txt
cat panel.txt
grep -q $'\tok$' status.tsv || exit 1
