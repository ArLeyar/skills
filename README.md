# goal-prompt / loop-prompt

Two companion skills for Claude Code (and Codex) that turn the work you just discussed into something that runs while you are away.

They split on one question: **does the work finish?**

| The work | Skill | Primitive |
|---|---|---|
| Ends at a checkable state — "tests pass", "migration done" | `goal-prompt` | `/goal` |
| Never ends — watch CI, babysit a PR, react to new commits | `loop-prompt` | `Monitor`, `/loop`, `loop.md` |

Each skill hands off to the other when the task turns out to be the other kind.

## goal-prompt

Writes a paste-ready condition for the native `/goal` command, and learns from how past goals actually went.

`/goal` runs your agent unattended until a condition is met. The condition is the whole game: it is judged by a small model that reads **only the transcript** — it runs no commands and opens no files. Most goals fail because the condition asks for something that never gets printed, measures the wrong thing, or requires a command that trips a permission prompt nobody is there to answer.

**Compose** (default) — reads the repo (test/lint/build commands, `CLAUDE.md`, permission `ask`/`deny` lists) and the current conversation, asks at most three questions for what genuinely cannot be derived, and emits one condition under the 4000-character cap:

```text
<measurable end state>, proven by <command whose output lands in the transcript>.
Do not <hard limits>. Stop after <N> turns if not met.
```

It does not run the goal, and it cannot: `/goal` is a built-in local command that installs a Stop hook, not a skill and not a tool, so nothing the model can call sets it. You paste it yourself.

**`review`** — after a run ends, records the one thing no machine logs: whether the work was any good. One question, one line appended to `~/.claude/goal-quality.jsonl`.

**`analyze`** — mines the hosts' own goal history (Codex's `~/.codex/goals_1.sqlite`, Claude Code's session transcripts) joined with those quality notes, and proposes concrete edits to the skill itself when a failure pattern hits three times.

### Why the conditions look the way they do

In Claude Code, `/goal` is a session-scoped prompt-based Stop hook. After each turn the condition plus the conversation go to a fast model that answers yes/no with a reason; "no" starts another turn and the reason becomes guidance.

- A condition is checkable only if the main model **prints the proof** during the run. "`src/api.ts` is under 200 lines" is unverifiable; "`wc -l src/api.ts` prints a number under 200" is.
- The agent optimizes exactly what the condition measures. Anything unmeasured degrades freely — so the condition blocks the obvious cheats (editing the tests, deleting the failing case, weakening the assertion).
- A command on an `ask` or `deny` list freezes the run mid-flight. Force-push in particular is never necessary: merge main into the branch instead of rebasing onto it.
- Anything destructive or outward-facing gets named in the condition even when the repo already forbids it, because the evaluator cannot read the repo.

## loop-prompt

Sets up unattended watching. It picks the primitive first, writes the prompt or the watch script, then arms it.

- **`Monitor`** when an event exists — a commit lands, a log line appears, CI flips. Each line the script prints wakes the session, so nothing is spent finding out that nothing changed.
- **`/loop`** when there is no event to hook, only a survey to repeat: triage the queue, review open PRs. Fixed cron interval, or model-paced so the delay stretches when things go quiet.
- **`loop.md`** when the same watch job belongs to a repo, as the default for a bare `/loop`.

The common shape is a monitor as the wake signal with a model-paced loop behind it as a slow fallback heartbeat.

Unlike `/goal`, these can be armed by the model, and the skill does that rather than leaving you with a tool call you cannot paste — after one confirmation when a tick can push, merge, deploy or message a person.

### What the prompts are built around

`/loop` has **no evaluator**. The prompt fires, the turn runs, the turn ends, and then it fires again unchanged. Everything follows from that:

- The prompt must be idempotent. Anything not safe to do twice needs an "already done?" check inside it.
- There is no memory between ticks except the transcript, which compacts. State is re-derived from `git`, `gh`, a file — never from "continue what you were doing".
- The prompt says what a tick with nothing to do looks like, or every quiet fire becomes an essay.
- For a monitor, silence is not success: a filter matching only the happy path stays quiet through a crash, and quiet looks exactly like "still running".

## Install

```bash
git clone https://github.com/ArLeyar/goal-prompt.git
mkdir -p ~/.claude/skills
cp -r goal-prompt/skills/goal-prompt goal-prompt/skills/loop-prompt ~/.claude/skills/
```

Then invoke either one bare, right after discussing the work:

```
/goal-prompt
/loop-prompt
```

Or with an explicit target: `/goal-prompt migrate the payments module`, `/loop-prompt watch main for new commits and review them`.

Codex: point your skills/prompt directory at the same `SKILL.md`. `goal-prompt` writes one condition that satisfies both hosts — Claude's constraints are the stricter set. `loop-prompt` is Claude Code only; its primitives have no Codex equivalent.

## Docs

- Claude Code `/goal`: https://code.claude.com/docs/en/goal
- Claude Code scheduled tasks and `/loop`: https://code.claude.com/docs/en/scheduled-tasks
- Anthropic on loop design: https://claude.com/blog/getting-started-with-loops
- Codex goals: https://learn.chatgpt.com/use-cases/follow-goals

## License

MIT
