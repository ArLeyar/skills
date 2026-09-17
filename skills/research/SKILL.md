---
name: research
description: Deep internet research with parallel search, source verification, and structured synthesis. Use when the user asks to research a topic, compare options, find best practices, or gather information from the web. Triggers on "research", "find out", "compare", "what are the best", "how does X work".
allowed-tools: WebSearch, WebFetch, Agent, Read, Write, Edit, Glob, Grep, Bash
user_invocable: true
metadata:
  short-description: Structured web research, verified against sources, saved as a memo
---

# Deep Research

Systematic internet research with parallel search, cross-referencing, and a saved report.

The failure this skill exists to prevent is confident synthesis of things nobody checked. Everything below serves one rule: **no source, no claim.**

## Usage

```
/research <topic>                       # standard: 3-5 search angles
/research deep <topic>                  # 5-8 angles, two rounds, gap-filling
/research quick <topic>                 # 1-2 angles, answer in chat, no file
/research compare <A> vs <B> [vs <C>]   # option comparison
/research <topic> --save <path>         # explicit destination
```

## Two hosts

Tool names in this file are Claude Code's. **Codex runs the same workflow** with its own equivalents, and nothing here needs dropping for it:

| Capability | Claude Code | Codex |
|---|---|---|
| Web search | `WebSearch` | built-in web search (`--search`, or `web_search` enabled in `config.toml`) |
| Fetch one page with a question | `WebFetch` | the same search tool, asked for the specific page; or a fetch MCP |
| Parallel sub-research | `Agent` subagents | Codex subagents — same fan-out, same "they cannot ask follow-ups" limit |
| Save, commit | `Write`, `Bash` | shell access |

Where this file names a Claude tool, read it as the capability, not the requirement. One difference worth planning around: Codex charges a token budget against a run and can end it `budget_limited`, so in `deep` mode prefer fewer, better-aimed fetches over a wide sweep.

## Pipeline

```
PHASE 0  FRAME ......... professional lens → reframed sub-questions → show the user
PHASE 1  DECOMPOSE ..... search angles + one extraction question per source
PHASE 2  SEARCH ........ parallel search → fetch → find gaps → follow-up round
PHASE 3  SYNTHESIZE .... merge by theme, cite inline, flag weak claims
PHASE 4  PERSIST ....... save by the repo's own convention, commit if allowed
```

## Phase 0: Frame

Identify the **professional lens** before decomposing. The right role produces the right vocabulary, and vocabulary is what decides which half of the internet answers you.

1. **Name the role.** Not "developer" or "consultant" — specific: "Shopify Solutions Architect", "EU Regulatory Compliance Specialist", "DTC Growth Strategist". The test: who gets *paid* to know this?
2. **Reframe as 2-3 sub-questions that professional would ask.** Industry terms, not lay ones: TCO rather than "how much it costs", CAC rather than "cost of getting customers". Split a vague ask into concrete concerns — architecture, pricing benchmark, compliance, vendor evaluation.
3. **Show the frame** — role, sub-questions, and a preliminary take of what you already believe before searching. Then proceed.

Skip this phase in `quick` mode.

**Example.** "I need to figure out Shopify for a wellness brand" becomes:

- **Role:** Shopify Solutions Architect
- **Q1 architecture:** Liquid themes vs headless (Hydrogen) — which, for a DTC wellness brand at 5-10K SKU
- **Q2 practice:** mandatory app stack, checkout optimization, EU compliance
- **Q3 money:** agency implementation rates — setup, custom theme, integrations, ongoing support

## Phase 1: Decompose

1. **What does the user actually need?** Decision support, an overview, a comparison, or an implementation guide. These produce different reports.
2. **What do you already know?** Separate confident knowledge from guesswork. Guesswork becomes a search angle.
3. **Generate search angles.** Each is a different lens: landscape (what exists), implementation (how), alternatives (decision support), recent developments (freshness), community experience (what breaks in practice). For `deep`, add academic sources, edge cases, and a deliberately contrarian angle.
4. **Write one extraction question per source.** This is the highest-leverage step in the skill.
   - Bad: "what does this page say?" — a vague question returns noise and wastes the call.
   - Good: "what are the pricing tiers and what exactly differs between free and paid?"
   - Good: "what benchmark numbers does this report for X vs Y, and on what hardware?"
5. **Decide the output shape** — the headers the report will have.

## Phase 2: Search

**Standard.** Fire 3-5 searches in parallel, each on a different angle, then fetch the top 5-10 results with their own extraction questions.

```
search("<topic> overview 2026")
search("<topic> best practices comparison")
search("<topic> open source implementation github")
search("<topic> reddit experience review")
search("<topic> arxiv survey")          # technical topics
```

**Deep.** Round one is broad: 5-8 parallel searches, 8-12 fetches, then stop and list what is missing or contradictory. Round two is targeted: 3-5 searches that close those specific gaps, cross-check the contested claims, and find a primary source for every number that matters.

**Compare.** One or two searches per option (pricing, features, limits, community size, maintenance status), plus head-to-head articles, plus official docs for each.

**Quick.** One or two searches, two or three fetches, answer in chat. No file, no methodology section.

### Search quality

- **Put the year in the query.** "best X 2026", not "best X" — undated queries surface undated content.
- **Scope with `site:`** where it helps: `site:github.com`, `site:reddit.com`.
- **Quote exact strings** for error messages and specific phrases.
- **Library and framework docs:** prefer a docs MCP (Context7 or similar) over web search — versioned answers beat blog posts.
- **JS-heavy pages** that come back empty: a browser MCP (Playwright or similar) renders what a plain fetch cannot.

## Phase 3: Synthesize

**Merge by theme, never by source.** A report organized source-by-source makes the reader do the synthesis you were asked for.

Lead with the answer, then the evidence. Every factual claim carries its source inline: `[Title](URL)`. A claim confirmed by two independent sources outranks one repeated by five sites quoting the same press release — check whether "multiple sources" are actually one source wearing hats.

### Source trust

| Signal | Trust |
|---|---|
| Official docs, primary announcement, the spec itself | HIGH |
| Recent post with reproducible benchmarks or code | HIGH |
| Accepted Stack Overflow answer, recent | MEDIUM-HIGH |
| Community discussion with engagement | MEDIUM |
| Generic "top 10 tools" listicle | LOW |
| Single uncorroborated claim | FLAG IT |

### Anti-hallucination rules

1. **No source, no claim.** Your training data is stale by definition. Use what you know for framing, never for facts.
2. **Name single-source claims as such:** "according to [one source]". Let the reader price the risk.
3. **Separate sourced fact from your analysis.** Both are welcome; blending them is not.
4. **Date everything time-sensitive,** including the access date.
5. **"No reliable data found on X" is a finding.** It beats a plausible guess, and it tells the next person where to dig.
6. **Paraphrase with attribution.** Direct quotes only for definitions and contested statements.

### Report template

```markdown
# <Topic>

> Date: YYYY-MM-DD | Sources: N | Queries: N

## TL;DR

<3-5 bullets. Someone reading only this gets 80% of the value.>

## Findings

### <Theme>
<Content with inline citations.>

## Comparison

| Criterion | A | B | C |
|---|---|---|---|

## Recommendations

1. <What to do, and why this rather than the alternative.>

## Sources

| # | Title | URL | Accessed | Trust |
|---|---|---|---|---|

## Methodology

- Angles searched: <queries>
- Tools: <what was used>
- Gaps: <what was not found, and what would close it>
```

The Methodology section is accountability, not decoration: it is how a reader tells a thin report from a thorough one.

## Phase 4: Persist

Research that is not saved is research that gets repeated. Everything except `quick` mode writes a file.

**Where.** In this order, first hit wins:

1. `--save <path>` if given.
2. The repo's own documented convention — check `CLAUDE.md` / `AGENTS.md` for where research notes go, and match the existing filenames in that folder (date format, slug style, frontmatter). A repo with twenty research files has already decided this; read one before writing the twenty-first.
3. `docs/research/YYYY-MM-DD-<slug>.md` in the current repo.
4. No repo → ask where to put it rather than inventing a path.

**Frontmatter.** If the destination folder's existing files carry YAML frontmatter, match their schema exactly and do not invent new tag values — an unmatched tag is invisible to whatever reads those files. If they carry none, add none.

**Git.** Commit the file following the repo's rules for commits, which the repo states and this skill does not override. Absent an explicit rule, commit on a branch and stop there: do not push, do not open a PR, do not merge. Never commit alongside unrelated working-tree changes.

**Trackers.** Create an issue only if the repo actually runs on one *and* the user asked for tracked work. Automatic issue creation turns a reading session into someone else's inbox.

**Machine-readable last line.** End the run with:

```
OUTPUT_FILE=<absolute path to the saved file>
```

so a calling pipeline can find the artifact without parsing prose.

## Subagents

Delegate to parallel subagents when the topic has 3+ genuinely independent sub-topics, or `deep` mode will run 10+ fetches, or the session context is already loaded with other work.

```
Agent("Research <sub-topic>. Search the web, fetch primary sources.
       Return: findings as markdown sections, every claim with its source URL.
       Do not synthesize across sub-topics — that happens upstream.")
```

Then synthesize their returns yourself. Do not let a subagent write the final report: it saw one slice and will present it as the whole.

Skip subagents for `quick` mode, for narrow topics, and whenever the research needs iterative refinement — a subagent cannot come back with a follow-up question, so anything ambiguous comes back wrong rather than unanswered.

## Rules

- **Search before claiming, even about things you know.** Especially about those.
- **Parallel by default.** Sequential search is the single biggest waste of wall-clock in this skill.
- **A fetch without a specific question is a wasted fetch.**
- **TL;DR is not optional.** First five lines carry the value.
- **Save by default.** `quick` is the only exception.
- **Match the user's language** in the report.
- **No padding.** Three sources agreeing is one paragraph with three citations, not three paragraphs.
