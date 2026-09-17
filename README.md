# skills

Agent skills for **Claude Code** and **Codex**. One repo, one install, no plugin machinery: each skill is a `SKILL.md` (plus whatever scripts it actually needs) that both hosts read the same way.

| Skill | What it does | Hosts |
|---|---|---|
| [research](#research) | Web research with parallel search, source verification, and a saved report | Claude, Codex |
| [consilium](#consilium) | The same brief to three models at once, answered blind, then synthesized — a question, or an artifact to tear apart | Claude, Codex |
| [transcribe](#transcribe) | Audio and video to text, locally on a Mac. Tuned for Russian with English tech jargon | Claude, Codex |
| [stop-slop](#stop-slop) | Strip AI tells from prose (vendored from [hardikpandya/stop-slop](https://github.com/hardikpandya/stop-slop)) | Claude, Codex |
| [goal-prompt](#goal-prompt) | Write a `/goal` condition for work that finishes | Claude, Codex |
| [loop-prompt](#loop-prompt) | Set up a monitor or a `/loop` for work that does not | Claude |

## Install

```bash
git clone https://github.com/ArLeyar/skills.git
cd skills

skill=research                                 # or consilium, stop-slop, goal-prompt, …

mkdir -p ~/.claude/skills ~/.agents/skills
cp -R "skills/$skill" ~/.claude/skills/        # Claude Code
cp -R "skills/$skill" ~/.agents/skills/        # Codex
```

`~/.agents/skills` is the shared location Codex documents; older Codex installs read `~/.codex/skills`, and copying to both costs nothing if you are unsure which yours uses. If `CLAUDE_CONFIG_DIR` is set, Claude's half lives under that instead of `~/.claude`.

Symlinks work too, and keep one copy current in both hosts:

```bash
ln -s "$PWD/skills/$skill" ~/.claude/skills/"$skill"
ln -s "$PWD/skills/$skill" ~/.agents/skills/"$skill"
```

Every skill here declares `name`, `description` and `license` per the [Agent Skills spec](https://agentskills.io/specification), so both hosts read the same file; `tests/validate_skills.py` checks that on demand.

Invoking them differs by host: Claude Code takes `/research`, Codex takes `$research` or `/skills`. Both also trigger on plain requests that match the skill's description, which is how most of these get used.

**`transcribe` is the exception — copying it by hand leaves it broken.** Its `SKILL.md` ships a `__SKILL_DIR__` placeholder that only the installer substitutes, and the installer also pulls ffmpeg, uv and the model:

```bash
curl -fsSL https://raw.githubusercontent.com/ArLeyar/skills/main/skills/transcribe/install.sh | bash
```

It installs into every host directory that exists (`~/.agents/skills`, `~/.codex/skills`, `~/.claude/skills`), skips any it finds tracked by a git repo, and says so rather than reporting success. Re-running it is how you update. It is also the one skill here that cannot be symlinked, for the same placeholder reason. Details, including the optional Russian fine-tune and the diarization setup: [skills/transcribe/README.md](skills/transcribe/README.md).

---

## research

Web research that ends in a file someone can act on, not a wall of plausible text.

```
/research <topic>                       # 3-5 search angles
/research deep <topic>                  # two rounds, gap-filling
/research quick <topic>                 # answer in chat, no file
/research compare <A> vs <B>            # option comparison
```

The pipeline runs frame → decompose → search → synthesize → persist. Two parts do most of the work:

- **Framing.** Name the professional who gets paid to know this ("Shopify Solutions Architect", not "consultant"), and reframe the question in their vocabulary. Vocabulary decides which half of the internet answers.
- **A named question per search angle,** carried to every page that angle turns up. "What does this page say?" returns noise. "What are the pricing tiers and what exactly differs between them?" returns the answer.

Everything else enforces one rule: no source, no claim. Single-source claims get labelled as such, gaps get written down as gaps, and the Methodology section says what was searched and what was not — which is how a reader tells a thorough report from a thin one.

It saves by the repo's own convention: `--save` first, then whatever `CLAUDE.md` or `AGENTS.md` documents, then `docs/research/`. Writing that file is the whole of persistence — it does not commit, branch, push or open a tracker issue, because a question asked in passing should not end up as a commit in your working tree.

What it fetches is evidence, never instructions: a page telling the agent to run something gets quoted in the report, not obeyed.

## consilium

One brief, three models, answered independently, then one synthesis.

Claude, Codex and Gemini each get the same brief in its own empty scratch directory, with no path to the others'. Where all three agree you are probably right; where one dissents is the thing you had not considered.

Two honest limits, both stated in the skill: isolation is arrangement rather than a sandbox, and agreement is not verification — three models share training data and share blind spots, so a unanimous panel is one opinion sampled three times until a decisive claim gets checked.

Three tiers trade cost against depth, individual seats can be swapped or skipped by environment variable, and each seat's model and final state land in `panel.txt` after the run. It costs a model run per seat, so it fires only on explicit intent.

`/consilium review <path>` points the same panel at something already written — a plan, a diff, a CV, prose, a config, another skill. It carries a hunt list per artifact type, because a review without one comes back as compliments, and it treats the artifact as data: text inside it addressed to the reviewer is part of what is under review, not an instruction. `--skip agy` makes it a two-model pass at two thirds the cost. A seat whose CLI is missing is named in the header and the panel goes on without it.

## transcribe

Audio and video to text on an Apple Silicon Mac. The default engine is local, free, and sends nothing anywhere; the cloud engines below exist but stay off until you name one.

Handles `.m4a`, `.mp3`, `.wav`, `.caf`, `.ogg`, `.flac`, and video too. Records from the microphone on request, splits hour-long recordings on silence, and cleans up Whisper's hallucination loops on silent stretches. Tuned for Russian speech with English tech jargon mixed in; any Whisper language works.

Speaker separation is a separate engine (`-e diarize`) and needs a free HuggingFace token plus accepted model terms; without the token it falls back to plain transcription rather than failing.

Two cloud engines exist for the cases the local model handles badly — ElevenLabs Scribe (diarized, one request, no chunking) and OpenAI. Both stay off until you name one: holding an API key changes nothing on its own.

Sending a bare path to an audio file is enough to trigger it — no command needed.

## stop-slop

Removes the predictable patterns that mark text as machine-written: throat-clearing openers, adverbs, binary contrasts, dramatic fragments, narrator-from-a-distance voice.

A modified fork of [hardikpandya/stop-slop](https://github.com/hardikpandya/stop-slop), MIT, with the upstream license kept alongside the skill. Divergence from upstream, so nobody has to diff for it: a section on slop versus intentional rhetoric (anaphora, antithesis and climax are craft — the skill kills the unconscious version and keeps the deliberate one), a CV and cover-letter fingerprint list, and edits throughout the three reference files.

## goal-prompt

Writes a paste-ready condition for the native `/goal` command, and learns from how past goals actually went.

`/goal` runs your agent unattended until a condition is met. The condition is the whole game: it is judged by a small model that reads **only the transcript** — it runs no commands and opens no files. Most goals fail because the condition asks for something that never gets printed, measures the wrong thing, or requires a command that trips a permission prompt nobody is there to answer.

**Compose** (default) — reads the repo (test/lint/build commands, `CLAUDE.md`, permission `ask`/`deny` lists) and the current conversation, asks at most three questions for what genuinely cannot be derived, and emits one condition under the 4000-character cap:

```text
<measurable end state>, proven by <command whose output lands in the transcript>
and by <a check of a different kind>, both re-run after the last edit and printed.
<what must hold when something fails>, printed by <the check that covers it>.
Do not <hard limits>. A third identical command is a blocker: stop and report.
Stop after <N> turns if not met.
```

Three of those lines are not style. Each answers a measured failure of long unattended runs: agents treat a green check from earlier in the session as proof of work done since, a single check is a single thing to game over an hour, and a condition naming only the happy path gets code with no error handling and calls it finished.

It does not run the goal, and it cannot: `/goal` is a built-in local command that installs a Stop hook, not a skill and not a tool, so nothing the model can call sets it. You paste it yourself.

**`review`** — after a run ends, records the one thing no machine logs: whether the work was any good. One question, one line appended to `~/.claude/goal-quality.jsonl`.

**`analyze`** — mines the hosts' own goal history (Codex's `~/.codex/goals_1.sqlite`, Claude Code's session transcripts) joined with those quality notes, and proposes concrete edits to the skill itself when a failure pattern hits three times.

### Why the conditions look the way they do

In Claude Code, `/goal` is a session-scoped prompt-based Stop hook. After each turn the condition plus the conversation go to a fast model that answers yes/no with a reason; "no" starts another turn and the reason becomes guidance.

- A condition is checkable only if the main model **prints the proof** during the run. "`src/api.ts` is under 200 lines" is unverifiable; "`wc -l src/api.ts` prints a number under 200" is.
- The agent optimizes exactly what the condition measures. Anything unmeasured degrades freely — so the condition blocks the obvious cheats (editing the tests, deleting the failing case, weakening the assertion).
- A command on an `ask` or `deny` list freezes the run mid-flight. Force-push in particular is never necessary: merge main into the branch instead of rebasing onto it.
- Auto mode blocks more than those lists: a classifier flags `git stash`, `git reflog` and `cd` outside the session's tree, blocks accumulate per agent until every command is gated, and retrying a blocked command extends the streak. So the condition builds on commands that pass clean and says outright that a blocked command is never retried or paraphrased.
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

`loop-prompt` is Claude Code only; its primitives have no Codex equivalent.

---

## Use cases

| You just | Say | You get |
|---|---|---|
| Need to decide something and the answer is on the internet | `/research compare Postgres vs ClickHouse for event storage` | a cited report saved where this repo keeps them |
| Need a second and third opinion that have not read each other | `/consilium` | three independent answers plus the consensus and the divergence |
| Have a plan or a diff you want torn apart | `/consilium review plan.md` | each model's findings, what they agree on, and what only one of them caught |
| Have an hour of recorded conversation | drop the file path in chat | a cleaned-up transcript, offline; speaker labels once diarization is set up |
| Agreed on a plan and want it finished unattended | `/goal-prompt` | one pasteable `/goal` condition built from this conversation plus the repo |
| Want a reaction to an event while you are away | `/loop-prompt watch main for new commits and review them` | a `Monitor` script with a last-seen marker, armed |

Russian walkthrough of the goal and loop scenarios, with the usual failure modes: [USECASES.ru.md](USECASES.ru.md).

## Docs

- Claude Code skills: https://code.claude.com/docs/en/skills
- Claude Code `/goal`: https://code.claude.com/docs/en/goal
- Claude Code scheduled tasks and `/loop`: https://code.claude.com/docs/en/scheduled-tasks
- Anthropic on loop design: https://claude.com/blog/getting-started-with-loops
- Codex goals: https://learn.chatgpt.com/use-cases/follow-goals

## License

MIT, except `skills/stop-slop`, which carries its upstream MIT license and copyright.
