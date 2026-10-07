# Consilium on Codex

`SKILL.md` is the skill. This file is the host adapter: it says what each Claude Code tool
name in that document means here, and nothing else. Read `SKILL.md` first and follow it —
the brief, the isolation, the hunt lists, the synthesis order and the exit codes are
identical, because the panel is a plain shell script that does not know which host called it.

## Tool translation

| `SKILL.md` says | On Codex |
|---|---|
| `Write` the brief with the Write tool, never `echo`/heredoc | `apply_patch` with `*** Add File: <DIR>/brief.md`. The reason holds here too: a heredoc mangles quotes and backslashes in the artifact |
| `Read` a seat answer | `sed -n '1,400p' <DIR>/<seat>.md`. A transcript (`codex.log`, `agy.log`) is read with `tail -n 30`, never whole |
| `${CLAUDE_SKILL_DIR}/run.sh` | `~/.codex/skills/consilium/run.sh` — expand it to the absolute path before running |
| `run_in_background: true`, do not poll, wait for the notification | Codex has no completion notification. Detach and poll: see below |
| `Artifact` publish (`--artifact`) | Not available. Degrade to `--save <path>` and say in the report that the artifact was written as a file instead |
| `Skill` tool (`artifact-design`) | Not applicable; only reachable from the `--artifact` path, which is gone |
| `WebSearch` / `WebFetch` to settle a decisive claim | Codex web search where the session has it; otherwise leave the claim marked `[unverified]` rather than voting on it |

## Fan-out and waiting

The seats take minutes and a shell call that blocks that long is at the mercy of the
command timeout. Detach the runner and poll its output file:

```bash
nohup bash ~/.codex/skills/consilium/run.sh "/absolute/run/dir" medium > "/absolute/run/dir/run.out" 2>&1 &
```

Then poll, spaced — `sleep 60; cat "/absolute/run/dir/status.tsv" 2>/dev/null || echo running`
— until `status.tsv` exists. It is written once, after every seat has finished or hit its
deadline, so its presence is the finish line. `run.out` carries the runner's own refusals
(exit 2), and those appear within a second: check it on the first poll, before sleeping
through a run that never started.

`CONSILIUM_TIMEOUT` defaults to 540 s and is capped at 570 because Claude Code's tool cap is
600. Detached here, that ceiling is not binding, but leave it alone anyway: a seat still
thinking after nine minutes is a seat that will not produce a usable answer.

## Network

Every seat is an outbound call. A Codex shell sandbox with network access off fails all three
within seconds — `exit:1` across the board, with a connection error in `<DIR>/<seat>.err`.
That reads exactly like three model failures and is not one. Check the `.err` tail before
reporting a dead panel, and re-run the session with network access if that is what it says.

## Accounts

Where the machine maps directories to accounts (`SKILL.md`, the `profile=` rule), the runner reads
the CALLER'S cwd. **Launch it from the directory the work belongs to and it is already right** — a
runner started from `/tmp` while the session works in a project picks the ordinary account
silently. A `cd` made for some unrelated reason is how that happens.

Never try to reach a second account by calling a `claude-<name>` wrapper: it is typically a shell
function and resolves to nothing from a script. Verify by reading `profile=` in `panel.txt`, not
by inspecting the command.

## The codex seat, called from Codex

`codex exec --ephemeral --ignore-user-config --ignore-rules` in its own empty directory is a
separate process with its own session: nesting it inside a Codex session is fine and it
inherits nothing from the caller. Two things do reach it, both by design and both worth
remembering: `CODEX_HOME` from the profile above, which is how it gets its account, and nothing
else. It is still a seat like any other and its answer gets no extra weight for having come from
the same vendor as the chair.
