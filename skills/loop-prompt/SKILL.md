---
name: loop-prompt
description: Set up unattended watching — picks between a Monitor (react to events as they happen), a /loop (re-run a prompt on a schedule or model-paced), and a loop.md repo default, then writes the prompt or watch script so it survives firing dozens of times with nobody looking. Defaults to the work just discussed in this conversation when invoked with no arguments. Use when the user says "/loop-prompt", "make this a loop", "turn this into a loop", "write me a loop prompt", "keep checking this", "react to new commits", "watch for X and do Y", "поставь на луп", "сделай из этого loop", "следи за X", "реагируй на новые коммиты", or wants Claude to keep watching something while they are away. Arms the watch itself once it is written, confirming first when a tick can push, merge, deploy or message anyone. For work with a finish line, use goal-prompt instead.
license: MIT
---

# loop-prompt

Produce one paste-ready artifact — a `/loop` invocation, a `Monitor` call, a `loop.md` file, or a monitor paired with a loop — plus at most two lines of caveat. Nothing else.

## Pick the primitive first

All of these run unattended; they are not interchangeable.

| The work is | Primitive | Why |
|---|---|---|
| Finished at some point — "tests pass", "migration done" | `/goal` | An evaluator judges completion. Hand off to `goal-prompt` and stop. |
| Reacting to something that *happens* — a commit lands, a log line appears, a file changes, CI flips | **`Monitor`** | The event wakes the session. No polling by the model, no wasted ticks. |
| A survey with no event to hook — "triage the queue", "review open PRs", "sweep for stale branches" | `/loop` | The same prompt re-runs on a rhythm. |
| Done once and never again | none | Say so instead of emitting. |

**Reach for `Monitor` before `/loop` whenever an event exists.** A shell one-liner can watch almost anything, and each line it prints wakes the session for free — while a `/loop` pays a full model turn per tick just to find out nothing changed. The common shape is both: a monitor as the wake signal, a model-paced `/loop` behind it as a slow fallback heartbeat.

Two nearby tools that are neither: for **one** notification ("tell me when the build finishes"), a background Bash command that exits on the condition is enough. For events pushed from outside the machine, see Channels in the Claude Code docs — CI can post into the session instead of being polled.

## The one mechanic that governs everything

**`/loop` has no evaluator.** Unlike `/goal`, nothing judges the result. The prompt fires, the turn runs, the turn ends. Then it fires again, unchanged.

Everything below follows from that:

- **The prompt must be idempotent.** It runs 5, 50, 500 times. Anything not safe to do twice — send a message, deploy, open a PR, append a line, comment on an issue — needs an "already done?" check inside the prompt, or it does not belong in a loop.
- **There is no memory between ticks except the transcript.** Once the session compacts, "continue what you were doing" points at nothing. State lives in observable places: `git`, `gh pr checks`, a file, a queue. Write the prompt so it re-derives its state every tick.
- **The prompt says what to do when there is nothing to do.** Without that line, a quiet tick becomes an essay about everything that was checked, every time.
- **Cost multiplies by frequency.** A tick that re-reads half the repo costs that much every interval. One heavy tick can cost more than ten light ones.

## Modes

| Mode | Emit | When |
|---|---|---|
| Fixed interval | `/loop 15m <prompt>` | The thing changes on a knowable rhythm, and a missed beat is cheap |
| Model-paced | `/loop <prompt>` | The right delay depends on what the last tick saw (build finishing vs. quiet PR) |
| `loop.md` | a file at `.claude/loop.md` | The same watch job every session in this repo; bare `/loop` then runs it |

Default to model-paced. It costs nothing extra, it stretches its own delay when things go quiet, and it can end itself — a fixed cron cannot.

Choose fixed interval when the user asked for a cadence outright, or when the tick must line up with an external rhythm (a nightly job, a 5-minute deploy window).

Choose `loop.md` only when the user wants a repo default, not a one-off. It replaces the built-in maintenance prompt for bare `/loop` and is ignored whenever a prompt is typed on the command line.

## Writing the monitor

A `Monitor` runs a script in the background; **every stdout line becomes an event that wakes the session.** The script is the whole design — get it wrong and the watch is either silent or a firehose.

Rules that decide whether it works:

- **Silence is not success.** The filter must match every terminal state, not the happy path. A watch that greps only for `PASSED` stays quiet through a crash, a hang, and an OOM — and quiet looks exactly like "still running". Widen the alternation rather than narrow it.
- **Line-buffer every stage.** `grep --line-buffered`, `awk` with `fflush()`. `head -N` cannot flush at all and delivers nothing until N matches accumulate.
- **Poll intervals inside the script:** 30s or more for remote APIs (rate limits), 0.5–1s for local checks.
- **Survive transient failure.** `|| true` on the network call, so one 500 does not end the watch.
- **Emit what you'd act on, nothing else.** Every line is a message in the conversation. Monitors that flood are stopped automatically.
- **`persistent: true`** for a session-length watch; otherwise it dies at `timeout_ms` (default 5 minutes, max 1 hour). `TaskStop` cancels it.
- **State that must not repeat lives in the script**, not in the model: track the last SHA, the last timestamp, the last comment ID, and emit only the delta. This is the monitor's version of idempotency.

**The monitor only wakes the session — it does not say what to do.** The reaction comes from the conversation, so state it in the same breath as arming the watch: *"when a commit event arrives, run `<check>` and report only failures."* Without that sentence, an event three hours later lands in a session that has forgotten why it was watching.

### Worked example: react to new commits on GitHub

The script tracks the last seen SHA and emits one line per new commit:

```bash
R=owner/repo; B=main
last=$(gh api "repos/$R/commits/$B" --jq .sha)
while true; do
  sleep 60
  cur=$(gh api "repos/$R/commits/$B" --jq .sha 2>/dev/null || true)
  if [ -n "$cur" ] && [ "$cur" != "$last" ]; then
    gh api "repos/$R/compare/$last...$cur" \
      --jq '.commits[] | "\(.sha[0:7]) \(.commit.author.name): \(.commit.message | split("\n")[0])"'
    last=$cur
  fi
done
```

Armed as `Monitor({command: <above>, description: "new commits on owner/repo main", persistent: true})`, paired with a stated reaction: *"on each commit event: `git fetch`, run the test and lint scripts against it, and report only what fails; stay quiet on green."*

For a local repository the same shape is cheaper — poll `git ls-remote origin main` instead of the API, and no token is involved. For a pull request rather than a branch, `gh pr checks <n> --json name,bucket` in the same loop emits each check as it lands and can `break` when none are pending, which ends the watch on its own.

Add a model-paced `/loop` behind it only when something must happen even with no events — a daily summary, a re-check that the monitor is still alive. Its delay is then 1200–1800s, because it is a fallback, not the wake signal.

## Where the loop task comes from

Resolve in this order, stop at the first hit:

1. **Arguments to the skill.** `/loop-prompt watch the deploy` → that is the task.
2. **The work established earlier in this conversation** — the PR just opened, the build just kicked off, the queue just described. This is the default case.
3. **Work in flight** — a branch with an open PR, a background task, a monitor already armed.
4. **Nothing found** → ask what to watch. One question.

Everything already said in this session — the PR number, the failing job name, the command that shows status — belongs in the prompt. Never re-ask for it.

## Procedure

### 1. Gather before asking

Cheap and usually enough: the status command the loop will run (`gh pr checks`, `gh run list`, a test script from `package.json`/`Makefile`/`justfile`), `git status`, `CLAUDE.md` for house rules.

**Read the permission lists — a tick that hits a prompt freezes forever, because nobody is watching:**

```bash
python3 -c "
import json,sys
for p in sys.argv[1:]:
    try: d=json.load(open(p))
    except Exception: continue
    pm=d.get('permissions',{})
    print(p, 'ask:', pm.get('ask',[]), 'deny:', pm.get('deny',[]))
" ~/.claude/settings.json ~/.claude/settings.local.json .claude/settings.json .claude/settings.local.json
```

Build the prompt out of what is left. Today that means no force-push in any spelling, no `reset --hard`, no `clean -f`, no `checkout -- .`, no `restore .`, and no Jira or Confluence writes — whatever the lists actually say when you read them wins over this sentence. A branch behind main is fixed by merging main into it, never by a rebase of pushed commits.

Procedural rules the repo already states are not retyped. One line covers them: `Follow CLAUDE.md.` The exception is anything destructive or outward-facing, which is named in the prompt regardless — see Safety.

### 2. Ask only what cannot be derived

At most 2 questions, and only when the answer changes the prompt:

- **Blast radius** — the loop may push, deploy, comment publicly, message a person, or spend on a paid API. Never guess this one.
- **Stop** — when nothing in the repo says what "finished" looks like and the loop would otherwise run for seven days.

If the repo answers everything and nothing is risky, ask nothing.

### 3. Compose

```text
<the check>, then <the action on what it finds>. If <quiet condition>, say so in one line and stop.
Do not <risky action>. <Ping rule>.
```

Every loop prompt carries five things:

| Part | Rule |
|---|---|
| Check | A command whose output is the state. Not "see how things are going". |
| Action | What to do about each outcome the check can produce, including the bad one. |
| Quiet rule | What a tick with nothing to do looks like: one line, no recap of what was checked. |
| Stop | The condition that ends the loop, in the prompt's own words. |
| Limits | Risky actions forbidden by name; when to wake the user. |

For a monitor the same five parts apply, split across two places: the check and the quiet rule live in the script (which emits nothing when nothing happened), the action, stop and limits live in the sentence stated alongside it.

Keep it short. This text is re-sent every tick, so a paragraph of preamble is a paragraph per tick, forever. If the recipe is long, put it in a skill or a script and have the prompt invoke that — a slash command is a legal `/loop` prompt (`/loop 20m /review-pr 1234`), and a script is cheaper than re-reasoning the same steps.

**Pings are for the user's decisions, not for progress.** Wake the user when the loop is blocked on something only they can decide, or when something landed that changes their plans (CI went red, a review rewrote the approach). Progress the loop made itself is already in the transcript. One ping per state, not per tick.

### 4. Self-check before emitting

Reject the draft if any answer is no:

1. Safe to run 50 times? Every irreversible action gated by an "already done?" check?
2. Does the prompt re-derive its state from the world, not from memory of the last tick?
3. Does it say what to do when there is nothing to do?
4. Is there a stop condition the loop itself can reach?
5. Is every risky action forbidden by name?
6. Does it avoid anything on an `ask` or `deny` list?
7. Is the tick cheap — a focused command, not a repo-wide re-read?
8. Is the interval matched to how fast the watched thing actually changes? An 8-minute CI run gets one check at ~8 minutes, not eight checks a minute apart.
9. Is this actually a loop, and not a goal, a one-shot, or an event a monitor would catch for free?

For a monitor, four more:

10. If the watched thing crashed right now, would the filter emit anything?
11. Does the script track its own last-seen marker, so one event is not re-emitted every cycle?
12. Is the reaction stated alongside the watch, so an event arriving hours later still knows what to do?
13. Is it `persistent: true` if it should outlive five minutes?

### 5. Emit

Output, in this order, nothing more:

1. The artifact in a `text` code block: a line starting with `/loop `, the watch script for a monitor, the file contents plus path for `loop.md`. For the paired shape, the monitor first and the fallback loop second.
2. One line: whether the run needs permissions raised (auto mode), since a permission prompt with nobody watching stops the loop dead.
3. One line only if something is at stake: what was forbidden and why.

### 6. Arm it

This skill can start the watch itself, and usually should — a user who asked for a loop wants a loop, not homework.

| Artifact | How to arm |
|---|---|
| Monitor | Call `Monitor` directly with the script, `description`, and `persistent`. State the reaction in the same message. |
| Fixed-interval loop | `Skill({skill: "loop", args: "15m <prompt>"})` — the bundled skill parses the interval, converts it to cron and schedules it. `CronCreate` directly works too, when the cron expression needs to be exact. |
| Model-paced loop | `Skill({skill: "loop", args: "<prompt>"})`. Do not call `ScheduleWakeup` by hand: it belongs to a running loop, not to this skill. |
| `loop.md` | Write the file. Nothing to arm — bare `/loop` picks it up. |

**A `Monitor` block is not pasteable.** It is a tool call, not text the user can type. Handing one over as a code fence and stopping leaves the user with nothing they can act on. Either arm it, or write the watch as a plain instruction they can say back.

Arm without asking when the loop only reads, checks and reports. **Confirm in one line first** — and wait — when a tick can push, merge, deploy, comment publicly, message a person, or spend money. Naming the primitive, the cadence and how to stop it (`Esc`, `TaskStop`, `CronDelete`) is enough; a second interrogation after the questions in step 2 is not.

Say what was armed and how to kill it. Then stop — do not run the first tick by hand unless the user asked for it, and do not narrate what the loop will do next.

## Host facts worth knowing

Verified against the CLI and the official docs; re-check if behavior contradicts this.

- **Session-scoped.** Ticks fire only while the session is running and idle. Closing the terminal stops them; backgrounding the session carries them over.
- **Seven-day expiry.** Recurring tasks fire one last time and delete themselves after 7 days. That is a backstop, not a plan.
- **No catch-up.** Fires missed during a long turn happen once when the session goes idle, not once per missed interval.
- **Jitter.** Recurring fires are deliberately offset, and the two sources disagree on the bound (the docs say up to 30 minutes or half the interval; `CronCreate` says 10% of the period, max 15 minutes). Either way, exact wall-clock timing is not on offer — pick a minute that is not `:00` or `:30` when timing matters at all.
- **Interval rounding.** Anything that does not divide its unit cleanly (`7m`, `90m`) is rounded, and Claude reports what it picked. Prefer intervals that divide 60 or 24.
- **Model-paced delays are clamped to 60–3600 seconds.** With a `Monitor` armed, the timer is only a fallback: 1200–1800s.
- **Stopping.** `Esc` while the loop is waiting clears the pending fire. In model-paced mode Claude can stop itself. A tick that neither reschedules nor stops gets one ~20-minute keepalive, then the loop ends.
- **Not everything runs on a scheduled fire.** Built-in commands (`/permissions`, `/model`, `/clear`), skills with `disable-model-invocation: true` (including `/verify`), skills hidden by `skillOverrides` or a `Skill` deny rule, and MCP prompts arrive as plain text and do nothing.
- **`loop.md`** lives at `.claude/loop.md` (wins) or `~/.claude/loop.md`, is truncated past 25,000 bytes, and is picked up on the next tick, so it can be edited while a loop runs.
- **Limits.** 50 scheduled tasks per session; 1 minute is the finest granularity; `CLAUDE_CODE_DISABLE_CRON=1` disables `/loop` entirely.

Monitors:

- **Every stdout line is one event**; lines within 200ms batch into a single notification. Stderr lands in the output file and wakes nothing — merge it with `2>&1` when the failure would otherwise be invisible.
- **Default `timeout_ms` is 5 minutes, max 1 hour.** `persistent: true` removes the deadline and runs until `TaskStop` or the end of the session.
- **A flooding monitor is stopped automatically.** Restart it with a tighter filter.
- **Monitors are never restored on `--resume`**, unlike scheduled tasks. A resumed session has no watch until it is armed again.
- **A `ws` source** streams WebSocket frames directly, no shell and no polling, when the service offers one.

## Safety

A loop is an unattended agent with a timer, so the blast radius is per tick, times the number of ticks.

Anything touching deploys, releases, force-push, migrations, production data, money, or outbound messages to real people gets an explicit prohibition in the prompt text, even when the user did not raise it, and even when the repo already forbids it. A repo rule requiring human approval means that action is forbidden inside a loop — a timer cannot hold an approval.

**When the risky action is the point** — "post the digest", "deploy when green" — a blanket ban makes the loop useless. Name the one action permitted, its target, and its bound (`deploy to staging only`, `comment on PR 1234 and nowhere else`), forbid everything adjacent, and require the "already done this tick?" check that keeps it from firing on every iteration. If the user has not authorized it in this conversation, ask.

## Anti-patterns

| Bad | Why | Fix |
|---|---|---|
| `/loop 5m keep improving the code` | nothing to check, no end | name the check and what a finished state looks like |
| `/loop continue what you were doing` | the transcript compacts and it points at nothing | re-derive state from a command every tick |
| `/loop 1m check CI` on an 8-minute build | seven wasted ticks per run | match the interval to the thing being watched |
| a tick that posts a status comment | posts on every fire | gate it: check for an existing comment first, or edit one comment |
| no quiet rule | a wall of "nothing to report" prose per tick | `if nothing changed, say so in one line` |
| `/loop` for a task with a finish line | there is no evaluator to notice it finished | that is a `/goal` — use `goal-prompt` |
| a prompt that runs `git rebase` or a force-push | permission prompt, run freezes | merge main in and push normally |
| `/loop 2m check for new commits` | a model turn every two minutes to learn nothing changed | a `Monitor` on the SHA; the event wakes the session |
| a monitor greping only the success marker | a crash is silent, and silence looks like "still running" | widen the filter to every terminal state |
| a monitor with no last-seen marker | the same commit fires every cycle forever | track the marker in the script, emit only the delta |
| a monitor armed with no reaction stated | the event lands in a session that forgot why it was watching | say what to do on an event in the same message |
| `tail -f app.log` piped straight in | every log line becomes a chat message, the monitor gets killed | filter to the lines worth acting on |
| handing over a `Monitor({...})` block and stopping | a tool call is not text the user can paste; nothing gets armed | arm it, or write the watch as an instruction they can say back |

## Reference

Claude Code: https://code.claude.com/docs/en/scheduled-tasks — modes, cron conversion, jitter, expiry, `loop.md`, limits. Monitor and the other tools: https://code.claude.com/docs/en/tools-reference

Anthropic on loop design: https://claude.com/blog/getting-started-with-loops — a loop defines its trigger, context, permissions, verification, state and stop condition; quantitative checks beat prose; match interval to how often the watched system changes.
