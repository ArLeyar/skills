---
name: goal-prompt
description: Turn the task at hand into a well-formed condition for the native /goal command in Claude Code or Codex, and learn from how past goals actually went. Defaults to the work just discussed in this conversation when invoked with no arguments; `review` records the one thing no machine logs — whether the work was any good; `analyze` mines the hosts' own goal history for what keeps going wrong. Use when the user says "/goal-prompt", "make this a goal", "turn this into a goal", "write me a goal prompt", "run this until it's done", "поставь цель", "сделай из этого goal", "напиши промпт для цели", or wants Claude to keep working autonomously until something is finished. Asks only for what the repo and the conversation cannot answer, then emits a paste-ready condition. Does NOT run the goal itself.
---

# goal-prompt

Produce one paste-ready `/goal` condition, plus at most two lines of caveat. Nothing else.

Work with no finish line — watching CI, babysitting a PR, reacting to new commits — is not a goal at all. There is no end state for an evaluator to confirm, so it belongs in `loop-prompt`, which covers `/loop` and event monitors. Hand it over and stop.

A bare invocation, or one whose argument describes work, means compose. The words `review` and `analyze` as the entire argument select those modes instead and skip the whole compose procedure — they are not goals to write conditions about.

## Why conditions fail (the one mechanic that governs everything)

`/goal` is a session-scoped prompt-based Stop hook. After every turn Claude Code sends the condition plus the conversation to a small fast model (Haiku by default). It answers yes/no with a short reason; "no" starts another turn and the reason becomes guidance.

**The evaluator runs no commands and reads no files. It sees the transcript only.**

Everything below follows from that:

- A condition is checkable only if the main model *prints the proof* during the run. "`src/api.ts` is under 200 lines" is unverifiable unless something printed the line count. Rewrite as "`wc -l src/api.ts` prints a number under 200".
- The evaluator's "no" reason steers the next turn. A condition whose failure mode is diagnostic ("which tests fail") outperforms one that just says no.
- The agent optimizes exactly what the condition measures. Anything unmeasured degrades freely.

Everything above describes Claude Code. **Codex has its own `/goal` built differently**: a durable background objective that runs until Codex judges itself done, not a small model re-reading the transcript each turn. It has no 4000-character limit (an over-long objective becomes an attachment), it enforces a token budget, and a run can end `blocked`, `usage_limited` or `budget_limited` rather than merely met-or-not.

Write one condition that satisfies both — Claude's constraints are the stricter set, and a condition built for a transcript-only evaluator loses nothing under Codex. Where this file names a Claude tool, read it as an example of the capability, not a requirement.

## Where the goal comes from

The skill is usually invoked bare, right after the work was already discussed. Resolve the target in this order and stop at the first hit:

1. **Arguments passed to the skill.** `/goal-prompt migrate the payments module` → that is the goal.
2. **The task established earlier in this conversation** — the plan just approved, the spec just written, the failing tests just diagnosed, the issue just read, the todo list just built. This is the default case. Read back through the conversation and take the most recent piece of work that was agreed on but not finished.
3. **Work already in flight** — a plan-mode plan, an active todo list, a branch with uncommitted changes plus a stated intent.
4. **Nothing found** → ask what the goal is. One question, not an interview.

When the conversation holds more than one candidate and they are not the same job, ask which one, using whatever the host offers for a structured question (`AskUserQuestion` in Claude Code). Do not merge them: one goal per session, and a condition covering two jobs flips to "met" on partial work.

The prior conversation is also the cheapest source of constraints. What was already established there — the failing test names, the file the user said not to touch, the decision to skip a case, the command that reproduces the bug — belongs in the condition. Never re-ask for something already said in this session.

Restating the target back to the user is not a step. The emitted condition shows what was understood; if it is wrong, the user says so.

## Procedure

### 1. Gather from the repo before asking the user

Cheap and usually sufficient: `package.json` scripts / `Makefile` / `pyproject.toml` / `justfile` for the real test, lint and build commands; `CLAUDE.md` for house rules; `git status` for the working tree. Never ask for something a single Read or Bash call answers.

**Procedural rules the repo already states do not get retyped into the condition.** Branch naming, merge flags, labels, the worktree requirement, commit style — if `CLAUDE.md` or `AGENTS.md` carries them, one line covers it: `Follow CLAUDE.md; it governs git, branches and merges.` The agent reads that file every turn. Repeating it burns the budget the actual task needs, and a paraphrase that drifts from the file is worse than the reference.

Two exceptions, both because **the evaluator cannot read that file** — it sees the transcript and nothing else:

- Anything destructive or outward-facing (force-push, `--admin` merge, deploy, migration, prod data, money, messages to real people) is named in the condition even when the repo already forbids it. A prohibition the evaluator cannot see cannot be enforced by it.
- A rule that narrows the repo default for this run (`this run merges nothing`, `stay on one branch`) is spelled out, since the file says otherwise.

**Read the permission rules too — they decide what the run can physically do.** `~/.claude/settings.json`, `~/.claude/settings.local.json`, and the project's `.claude/settings*.json` carry `ask` and `deny` lists:

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

**An `ask` rule beats auto mode.** The run stops on a permission prompt that nobody is there to answer, and the goal dies there — not failed, just frozen mid-run. A `deny` rule is cleaner but no better: the command simply cannot run. Either way, a condition that requires such a command cannot be satisfied.

**The `ask` list is not the only prompt source — auto mode itself runs a classifier over every command, and its blocks kill unattended runs the same way.** Three mechanics, all observed in real runs:

- **Prompt-prone commands.** The classifier flags `git stash` (all subcommands: `apply`, `pop`, `list`), `git reflog`, and `cd` to a path outside the session's project dir — a sibling worktree, another repo. Bundling `cd` into a compound invites the classifier even inside the project tree: a real run got 6 consecutive blocks on `cd .worktrees/x && git status` where the bare command would pass. Worktree needed → the host's own tool (`isolation: "worktree"` on agents, `EnterWorktree`), never a raw `cd`; path needed → `git -C <path>` / absolute paths.
- **The block streak.** Blocks accumulate per agent: after ~5 consecutive blocks the harness gates that agent's *every* command, even `git status`. Retrying a blocked command or rephrasing it into a synonym digs the hole — each attempt is another block on the streak. So the condition says it outright: `a blocked command is never retried or paraphrased — treat it as a blocker: stop that line of work and report`. In multi-agent runs, add: an agent with 2+ blocks is finished and replaced by a fresh agent in the same worktree — the streak dies with the agent.
- **The classifier itself can fall over** (`Stage 2 classifier error`, `claude-sonnet temporarily unavailable`) — transient, blocks safe commands too. Nothing to encode in the condition beyond the no-retry rule above, which already covers it.

Build the run's workflow out of the set that passes clean: package-manager scripts, `git add/commit/push/fetch/merge/diff/show/log/status`, `gh pr *`, `rg`, plain interpreters. Everything outside it — `stash`, `reflog`, `reset --hard`, `clean`, `checkout -- .`, `restore .`, `rebase` — is banned by name when agents are involved. (`stash` is doubly poisoned in worktrees: one `.git` means one shared stash, and parallel agents pop each other's WIP — set work aside via a WIP commit instead.) The general rule: any command whose approval needs a human is banned from the condition, whatever list it is or isn't on.

So: read those lists, and build the condition out of what is left. Today that means force-push in all its spellings (`--force`, `-f`, `--force-with-lease`), `reset --hard`, `clean -f`, `checkout -- .`, `restore .`, and the Jira and Confluence write operations. Whatever the lists say when you read them wins over this sentence.

**Force-push is never necessary, so never require the thing that leads to it.** A branch falling behind main is fixed by merging main into it, which pushes normally. Only a rebase of already-pushed commits forces a force-push — so the condition says `merge main into the branch` and never `rebase onto main`. This matters even when the condition says nothing about pushing: `rebase` alone is enough to walk the run into a prompt three steps later.

### 2. Ask only for what is genuinely unknowable

Ask at most 3 questions, and only for gaps that change the condition:

- **Done-signal** — when no test/lint/build command exists and success is judged some other way. Offer concrete candidates found in the repo.
- **Blast radius** — when the work could touch deploys, migrations, prod data, external sends, or paid APIs. Never guess this one. (Force-push and its neighbours are already settled by the permission lists above; they are out, not up for discussion.)
- **Off-limits** — when it is unclear which paths must stay untouched (tests? generated files? another package?).
- **Scope end** — when "all of them" is ambiguous (whole repo vs one directory vs one label).

If the repo answers everything and no action is risky, ask nothing and emit the condition.

**Whatever stays unresolved at emit time gets resolved by the agent, silently and in its own favour.** Agents take a specification at face value: they do not surface its contradictions, do not name the assumption they just made, and do not stop to check which reading was meant. And an unattended run has nobody to ask — the question that would have been cheap now is unaskable in twenty minutes. So every ambiguity is either asked about here or written into the condition as a decision already taken. Leaving it out is not neutrality; it is delegating the call to whichever reading is easiest to satisfy.

### 3. Compose

```text
<measurable end state>, proven by <command whose output lands in the transcript>
and by <a check of a different kind>, both re-run after the last edit and printed.
<what must hold when something fails>, printed by <the check that covers it>.
Do not <hard limits>. A third identical command is a blocker: stop and report.
Stop after <N> turns if not met.
```

Every condition carries four parts:

| Part | Rule |
|---|---|
| End state | Exactly one. Test result, exit code, file count, empty queue. Not an adjective. |
| Proof | A command the main model will run, whose output the evaluator can read. |
| Limits | What must not change, and every risky action explicitly forbidden. |
| Cap | A turn or time bound, written into the condition rather than left to an external limit — an agent that cannot see its budget prioritises as if it had none. Claude enforces no token budget of its own; Codex does, and can end a run `budget_limited`. |

**Three items are mandatory in `Done when`, and each answers a measured failure mode of long unattended runs:**

- **Re-verification after the last edit.** Not `tests pass` but `after the final change, <check> was run again and printed exit 0`. On ultra-long-horizon benchmarks 99.6% of failed runs carried a validation signal the agent could have seen and never looked at, and 19% of unfinished runs ended in a self-declared finish with work still left. Agents overestimate completion and under-invest in the final check; a green run from earlier in the session is the specific thing they mistake for proof.
- **Two proofs of different kinds.** One command is one thing to game, and prompt-level prohibitions decay over hour-scale runs — an agent with a shell probes any single check until it gives. Pair the test run with something of another nature: a typecheck, a lint, a behavioural check, a count.
- **One failure-path item, proven the same way as the rest.** The agent optimises exactly what is measured and nothing else, so a condition naming only the happy path gets the happy path — no error handling, no edge case, and the work is technically complete. Name the behaviour on failure *and* the command that prints it: `the malformed-input case is covered — <test> names it and prints a pass`. An adjective about robustness is the failure mode this whole file exists to prevent, and it is easiest to smuggle back in through this item.

**All three attach to the same end state, not to new ones.** Two proofs mean two lenses on one outcome, not two outcomes joined by "and": `tests pass and the API returns 400 on bad input` is the stitched form that fails on partial work. Write one end state, then the checks that see it from different angles.

These three do not extend the budget, they replace part of it: their characters come out of the repo boilerplate the condition should never have carried. They are cheaper than they look — a minimal condition carrying all of them, plus the turn cap and the risky-action prohibitions, measures near 1000 characters, so the 2500-3000 aim holds with the new floor in place.

**Idle spin is a blocker, and catching it is cheaper than the turn cap.** Repeated identical tool calls are the strongest observed predictor of a run dying by timeout — one measured harness produced 63 of its 83 timeouts, and pass rate fell from 41.9% to 3.2% as consecutive identical calls accumulated. One line covers it: `the same command with the same arguments a third time is a blocker — stop that line of work and report`.

**Hard cap: 4000 characters in Claude Code, counted, not eyeballed.** `/goal` rejects anything longer outright (`Goal condition is limited to 4000 characters`) and the whole emission is wasted — this has already happened eight times, at 4010, 4119, 4368, 4929, 5901, 6305, 9084 and 15217 characters. Codex has no such limit; it stores an over-long objective as an attachment. Write to the Claude cap regardless, so one condition serves both.

Measure by writing the condition to a scratch file and reading it back:

```bash
python3 -c "import sys;print(len(open(sys.argv[1]).read()))" <scratch>/goal.txt
```

Write that file with the host's file-writing tool, never with a heredoc: a condition may legitimately contain a line reading `EOF`, which ends the heredoc early and hands the remainder to the shell as commands. Count the condition without the leading `/goal ` and keep 100 characters of headroom — the trailing newline and the prefix are exactly the kind of off-by-a-little that turns 3990 into a rejection.

Aim for 2500-3000. The cap is where the command fails, not where a good condition lands: half the emitted conditions sat at 3700-3990, which is text expanding to fill the space available, and every one that broke the cap did so because nothing was ever kept in reserve. A condition that needs 3900 characters is usually carrying repo boilerplate — see below.

Over 3900 → cut, in this order, until it fits: repeated rationale, examples inside `Context`, prohibitions already covered by a broader one, per-item wording collapsed into one rule. Never cut `Done when`, the turn cap, the idle-spin line, or a risky-action prohibition — the idle-spin line sits outside `Done when` in both templates, which is exactly how it gets trimmed by a composer working to fit. Long recipes (how to type a catch block, how to name a helper) belong in a file the condition points at, not in the condition.

**Do not spend the budget on scaffolding that stopped paying.** Heavy XML tagging for structure, role preambles (`You are an experienced SRE`) and reasoning incantations (`think step by step`) bought measurable points on older models and buy none now: current models were tuned against those exact tics, and extended thinking covers the third. Tags stay only where something must be machine-extracted from the transcript. Everything else is plain declarative sentences, one per rule — the characters saved are the ones the mandatory items above need.

For large work, use the five-block form and keep `On block` — without it the agent invents a workaround or spins:

```text
Goal: <one verifiable outcome>
Context: <facts the agent cannot derive: paths, source of truth, decisions>
Constraints: <hard limits, out of scope>
Done when: 1) <binary check, a shell command> 2) <a check of a different kind>
          3) <the checks re-run after the last edit, printing their result>
          4) <what must hold when something fails: the error path, the edge case>,
             printed by the check that covers it
On block: fail fast, <where to escalate>, <what to do with an unspecifiable item>.
          The same command with the same arguments a third time is a blocker.
Stop after <N> turns.
```

**The condition carries no bookkeeping at all.** No "log the outcome", no "record how it went", no `Done when` item about filing a note. Three reasons, each sufficient: finishing the work and filing a note about it are two end states where the rule above allows exactly one; the evaluator cannot read a log file, so any claim about one is self-attested; and both hosts already record the run themselves, as the history section below shows.

Above all, **never make the condition invoke a tool that asks the user a question** — `/goal-prompt review`, or anything else that opens a prompt. A question has no timeout. The final turn of an unattended run has nobody to answer it, so the run stops there and stays stopped.

### 4. Self-check before emitting

Reject your own draft if any answer is no:

1. One measurable end state, not several stitched with "and also"?
2. Will the proof actually be printed during the run?
3. Does `Done when` require the checks re-run *after the last edit*, rather than accepting a green run from earlier in the session?
4. Are there two proofs of different kinds, or is one command carrying the whole verdict — and do both attach to the same end state rather than adding a second one?
5. Is there an item about what happens on failure — an error path, an edge case — with a command that prints it, not an adjective about robustness?
6. Would a lazy-but-literal agent satisfy this while doing bad work? If yes, the condition measures the wrong thing — add the quality anchor (a reference doc, a mockup, an example output), not an adjective.
7. Are the obvious cheats blocked: editing tests instead of code, deleting the failing case, weakening the assertion, writing code to fit a known test manifest rather than the requirement, satisfying the check from a cached or stale run, reaching around the check through the environment instead of through the code?
8. Is there a turn cap, stated in the condition rather than left implicit?
9. Is the idle-spin rule present — third identical command is a blocker?
10. Is every risky action forbidden by name?
11. Does the condition require anything on an `ask` or `deny` list — force-push, `reset --hard`, `clean -f`, a Jira write — or anything the auto-mode classifier flags: `stash`, `reflog`, `cd` into another worktree or repo? A prompt nobody answers freezes the run. Replace it (merge instead of rebase, WIP commit instead of stash, `git -C` / host worktree tool instead of `cd`) or drop it, and state the no-retry rule: a blocked command is never retried or paraphrased.
12. Is the measured length at or under 3900 characters — the cap minus its headroom, measured with the command above, not estimated?
13. Is this actually worth a goal? A task finishing in one or two turns should stay a normal prompt — say so instead of emitting.

### 5. Emit

Output, in this order, nothing more:

1. The condition in a `text` code block, starting with `/goal `, ready to paste.
2. One line: whether the run needs permissions raised. Setting a goal does not change them — in Claude Code that means auto mode, in Codex a sandbox and approval policy wide enough for the work. Without it the run stops at the first prompt nobody is there to answer.
3. One line only if something is genuinely at stake: what was forbidden and why.

Do not explain the framework. The user pastes it themselves — not out of caution, but because there is no other way in: `/goal` is a built-in local command that installs a Stop hook, not a skill and not a tool, so nothing the model can call sets it. (`loop-prompt` is the opposite case and arms its own watch; do not carry that habit over here.)

The one alternative, when the user wants it running without pasting, is a separate non-interactive session — the command declares non-interactive support, so `claude -p '/goal …'` with a permission mode wide enough for the work starts one. That is a different session with a different transcript, not this one; offer it only when the user asks to hand the run off, and say plainly that this conversation will not be the one working.

## Where the history actually lives

Two sources, both on disk, both retroactive — no hook, no daemon, no bookkeeping during the run.

Write nothing at emit time. An entry written when the condition is handed over records what was *offered*, which is a different thing from what ran: of 28 such entries in the abandoned `~/.claude/goal-log.jsonl`, eight were conditions the CLI had rejected outright, three were summaries rather than the text, and none ever got an outcome. That file is dead — do not append to it.

**Codex** keeps goals in SQLite, one row per thread. Take the whole objective and the identity, not a preview:

```bash
sqlite3 -header ~/.codex/goals_1.sqlite \
  "select thread_id, goal_id, status, token_budget, tokens_used, time_used_seconds,
          datetime(created_at_ms/1000,'unixepoch','localtime') started,
          datetime(updated_at_ms/1000,'unixepoch','localtime') updated,
          length(objective) len, objective from thread_goals order by created_at_ms desc;"
```

`status` is one of `active`, `paused`, `blocked`, `usage_limited`, `budget_limited`, `complete`. The first two are current state, not outcomes — exclude them from any analysis of how runs end. An objective reading `pasted text file: <path>` is a pointer; the real text is that file under `~/.codex/attachments/`, and its length is what matters for length analysis. `thread_id` is the primary key, so a thread that ran several goals in sequence keeps only the last: the table under-counts runs and never over-counts them.

**Claude Code** keeps no goal state, but the transcript holds the invocation, the verdict on it, and the timing. Transcripts live in `~/.claude/projects/<slug>/<session>.jsonl`; skip `subagents/`.

Parse the JSON, do not grep the raw text: transcripts quote other transcripts, skill definitions and past errors, so a text scan invents runs that never happened. Two record shapes matter, and a parser that knows only the first silently reports zero rejections:

- The invocation — a user record whose `message.content` begins with `<command-name>/goal</command-name>`, closing tag included. Matching the bare prefix also catches `/goal-prompt`, which is this skill, not a run. The condition is verbatim inside `<command-args>`.
- The verdict — a `type: "system"`, `subtype: "local_command"` record with the marker in its **top-level** `content`: `Goal set: …` means the run started, `Goal condition is limited to 4000 characters (got N)` means it never did. Nothing else distinguishes a condition that was merely written from one that ran. Accept only that shape: across all transcripts, 9 rejection records are real and 30 further copies of the same string sit nested inside assistant messages, quoted transcripts and attachments. Counting those inflates the failure rate roughly fourfold.

A `/goal` invocation with an empty or `clear` argument is a status check or a cancellation, not a run — decide by the argument's content, never by its length, since a short condition is legitimate. The run's window ends at the next `/goal` invocation, a `clear`, or the end of the session, whichever comes first; without that upper bound, wall time silently absorbs everything that happened afterwards.

**Turns are not recoverable on the Claude side.** `stop_hook_summary` records track ordinary stops — roughly one per prompt in normal use — but not goal continuations: one measured run produced 137 assistant records and a single summary. `promptId` likewise stays constant across continuations. Report wall time, and take turn cost from Codex, which records `tokens_used` and `time_used_seconds` outright.

What neither source records is whether the *work* was any good. That is the one thing worth asking a human, and the only reason `review` exists.

## Mode: `review` — the one field no machine has

Invoked as `/goal-prompt review` after a run ends. Optional: skipping it costs the quality note, nothing else, because everything mechanical is recoverable later.

First locate the run in the source above and take its identity from there — `thread_id` for Codex, the transcript path plus the invocation record's `uuid` for Claude. Without an identifier the note attaches to whichever run happens to look similar, and templated goals in one directory look identical for their first several hundred characters.

Then ask the user one question: was the work good — good / met the letter but the result was wrong / wrong end state entirely. Only when the answer is not `good`, ask what the condition failed to measure, and derive the tag from that answer. Append one line to `~/.claude/goal-quality.jsonl`:

```json
{"ts": "...", "host": "claude|codex", "run_id": "<thread_id | transcript path + uuid>", "cwd": "...",
 "quality": "good|letter-only|wrong-target", "gap": null, "tag": null}
```

`gap` and `tag` stay `null` when the work was good — a run with nothing wrong has no failure to name, and a tag invented to fill the field is what makes the whole history unreadable later. Reuse an existing tag before inventing one: `unverifiable-proof`, `self-attested`, `no-cap`, `missing-prohibition`, `wrong-tree`, `multi-goal`, `too-vague`, `cheatable`.

Build the JSON in Python; never string-concatenate shell. Read the condition from the source that has it — SQLite or the transcript — and never retype it by hand. There is no separate condition file to rely on; the scratch file used for measuring is gone by now.

Never invoke this from inside a running goal. It asks a question, and an unattended final turn has nobody to answer it.

Reply with one line confirming what was recorded. Nothing else.

## Mode: `analyze` — turn the history into better conditions

Invoked as `/goal-prompt analyze`. Read both sources above, join them with the quality notes where those exist, and report only what the data carries:

Keep the two hosts in separate columns. They answer different questions, and a table that mixes them produces a correlation neither one supports:

- **Codex** carries how runs ended (`complete` vs `blocked`, `usage_limited`, `budget_limited`) and what they cost. Ask there: what do the `blocked` objectives share that the `complete` ones do not — a proof nothing printed, a missing cap, two jobs in one — and where cost ran away.
- **Claude** carries whether the condition was accepted at all, its exact length, and wall time. Ask there: how often a condition was rejected outright, and whether length tracks with the runs the quality notes call bad.
- **Quality notes** carry the only human judgment. Failure tags by frequency, each with the condition that produced it.

**A correlation needs at least three runs behind it.** Below that, say the data is thin and stop. Pattern-matching two data points produces confident noise, which is worse than no analysis.

Then produce the payoff: **concrete edits to this file.** A pattern hitting three times means the checklist missed it — propose the new checklist line or anti-pattern row, in full text, and apply it if the user agrees. A report nobody acts on is a diary.

Never invent a pattern to have something to say. "Nine runs, no shared failure mode" is a valid result.

**Once the history is thick enough — roughly 20 runs carrying quality notes — this mode has a better algorithm available than reading them by hand.** Reflective prompt optimisers beat expert-written prompts by keeping *competing* instruction variants alive instead of one lineage that drifts — in the published case, instruction text alone moved a benchmark from 67% to 93%. What that buys here is one concrete change of behaviour, and only above the threshold:

Take the rule carrying the most failure tags and propose **two** rewrites of it, not one. Emit them alternately on the next runs and, once each has five, keep the one with fewer failure tags and delete the other from this file. Which variant a run used is recoverable from the condition itself — SQLite for Codex, the transcript for Claude — so this needs no bookkeeping at emit time, and the rule against writing any is unchanged. One variant edited in place cannot be compared with anything, which is why every past `analyze` pass produced improvements nobody could confirm.

Below the threshold there is nothing to compare against, and two variants over four runs is noise with extra steps: read them by hand, propose the single edit as described above, and say the data is thin.

## Safety

Any condition touching deploys, releases, force-push, schema or data migrations, production data, money, or outbound messages to real people gets an explicit prohibition in the text, even when the user did not raise it. Repo rules (`CLAUDE.md`) that require human approval for an action mean that action is forbidden inside a goal, not merely gated — an unattended loop cannot hold an approval.

**When the risky action *is* the end state** — "the release is deployed", "the message is sent" — a blanket prohibition would make the condition unsatisfiable, and the run would burn turns trying to obey both halves. Instead the user authorizes exactly that action and nothing wider: name the one thing permitted, its target, and its bound (`deploy to staging only`, `send to the one address named here`), and forbid everything adjacent. If the user has not authorized it in this conversation, ask — this is the blast-radius question, and it is the one thing never worth guessing.

## Anti-patterns

| Bad | Why | Fix |
|---|---|---|
| `improve the dashboard` | nothing to evaluate | name the tests and a size or perf budget |
| `the app is production-ready` | no observable proof | list the specific checks that stand for readiness |
| `all tests pass` (no limits) | agent edits the tests | forbid touching test files |
| `all tests pass`, proven once | the green run predates the last edit, and the agent treats it as proof anyway | require the check re-run *after* the final change |
| one command carrying the whole verdict | a single check is a single thing to game, and an hour-long run finds the way | pair it with a check of another kind (typecheck, behaviour, count) |
| happy path only | error handling and edge cases were never measured, so they were never written | one `Done when` item about behaviour on failure |
| no idle rule | repeated identical calls are the top predictor of death by timeout | third repeat of the same command = blocker, stop and report |
| XML scaffolding, role preamble, `think step by step` | measured gain is gone on current models, and the characters come out of a hard 4000 | plain declarative sentences |
| `refactor X` with no cap | runs until interrupted | add `stop after N turns` |
| a philosophical end state | burns tokens forever | reject and ask for the observable |
| `rebase onto main, then force-push` | `ask` rule fires, run freezes on a prompt nobody sees | merge main into the branch and push normally |
| `cd` into another worktree/repo mid-run | built-in prompt fires even in auto mode, run freezes | stay in the session's tree; `git -C <path>`; new worktree via host tool (`isolation: "worktree"`, `EnterWorktree`) |
| `git stash` in a multi-worktree run | classifier blocks it, and one shared `.git` means agents pop each other's WIP | set work aside via a WIP commit on the branch |
| retry a blocked command / find a synonym | each attempt extends the block streak until every command is gated | one block = stop that line, report; 2+ blocks on an agent = replace the agent |
| three goals joined by "and" | evaluator flips on partial work | pick one, queue the rest |

## Reference

Claude Code: https://code.claude.com/docs/en/goal — one active goal per session, `/goal` alone shows status, `/goal clear` cancels, condition capped at 4000 characters, restored on `--resume` with counters reset, unavailable when hooks are disabled or the workspace is untrusted.

Codex: https://learn.chatgpt.com/use-cases/follow-goals — a durable background objective that runs until Codex is confident it is done, rather than a per-turn evaluator; state lives in `~/.codex/goals_1.sqlite`, over-long objectives become attachments, and a run can end blocked or limited by usage or budget.
