# goal-prompt

A skill for Claude Code (and Codex) that turns the work you just discussed into a paste-ready condition for the native `/goal` command — and learns from how past goals actually went.

`/goal` runs your agent unattended until a condition is met. The condition is the whole game: it is judged by a small model that reads **only the transcript** — it runs no commands and opens no files. Most goals fail because the condition asks for something that never gets printed, measures the wrong thing, or requires a command that trips a permission prompt nobody is there to answer.

This skill writes conditions that survive that evaluator.

## What it does

**Compose** (default) — reads the repo (test/lint/build commands, `CLAUDE.md`, permission `ask`/`deny` lists) and the current conversation, asks at most three questions for what genuinely cannot be derived, and emits one condition under the 4000-character cap:

```text
<measurable end state>, proven by <command whose output lands in the transcript>.
Do not <hard limits>. Stop after <N> turns if not met.
```

It does not run the goal. You paste it yourself.

**`review`** — after a run ends, records the one thing no machine logs: whether the work was any good. One question, one line appended to `~/.claude/goal-quality.jsonl`.

**`analyze`** — mines the hosts' own goal history (Codex's `~/.codex/goals_1.sqlite`, Claude Code's session transcripts) joined with those quality notes, and proposes concrete edits to the skill itself when a failure pattern hits three times.

## Install

Claude Code:

```bash
git clone https://github.com/ArLeyar/goal-prompt.git
mkdir -p ~/.claude/skills
cp -r goal-prompt/skills/goal-prompt ~/.claude/skills/
```

Then invoke it bare, right after discussing the work:

```
/goal-prompt
```

Or with an explicit target: `/goal-prompt migrate the payments module`.

Codex: point your skills/prompt directory at the same `SKILL.md`. The skill writes one condition that satisfies both hosts — Claude's constraints are the stricter set.

## Why the conditions look the way they do

Everything in `SKILL.md` follows from one mechanic: in Claude Code, `/goal` is a session-scoped prompt-based Stop hook. After each turn the condition plus the conversation go to a fast model that answers yes/no with a reason; "no" starts another turn and the reason becomes guidance.

Consequences the skill is built around:

- A condition is checkable only if the main model **prints the proof** during the run. "`src/api.ts` is under 200 lines" is unverifiable; "`wc -l src/api.ts` prints a number under 200" is.
- The agent optimizes exactly what the condition measures. Anything unmeasured degrades freely — so the condition blocks the obvious cheats (editing the tests, deleting the failing case, weakening the assertion).
- A command on an `ask` or `deny` list freezes the run mid-flight. Force-push in particular is never necessary: merge main into the branch instead of rebasing onto it.
- Anything destructive or outward-facing gets named in the condition even when the repo already forbids it, because the evaluator cannot read the repo.

## Docs

- Claude Code `/goal`: https://code.claude.com/docs/en/goal
- Codex goals: https://learn.chatgpt.com/use-cases/follow-goals

## License

MIT
