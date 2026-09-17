#!/usr/bin/env -S uv run --quiet --with pyyaml python
"""Checks every SKILL.md against the Agent Skills spec: https://agentskills.io/specification

Run: tests/validate_skills.py   (or: uv run --with pyyaml python tests/validate_skills.py)

The reason this exists: cross-review's description contained ": /cross-review", which YAML
reads as a mapping value, so its frontmatter was invalid for months while the skill still
loaded. Lenient hosts hide that; a stricter one would drop the skill entirely.
"""
import re
import sys
from pathlib import Path

import yaml

SPEC = {"name", "description", "license", "compatibility", "metadata", "allowed-tools"}
# Claude Code's superset, accepted here without complaint:
HOST = {
    "when_to_use", "argument-hint", "arguments", "disable-model-invocation", "user-invocable",
    "disallowed-tools", "model", "effort", "context", "agent", "background", "hooks", "paths",
    "shell",
}
NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")

root = Path(__file__).resolve().parent.parent
problems = []

for skill_md in sorted(root.glob("skills/*/SKILL.md")):
    d = skill_md.parent.name
    say = lambda msg: problems.append(f"{d}: {msg}")
    text = skill_md.read_text()

    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        say("no YAML frontmatter delimited by --- lines")
        continue
    try:
        fm = yaml.safe_load(m.group(1))
    except yaml.YAMLError as e:
        # The usual cause is an unquoted ": " inside description.
        say(f"frontmatter is not valid YAML: {str(e).splitlines()[0]}")
        continue
    if not isinstance(fm, dict):
        say("frontmatter is not a mapping")
        continue

    name = fm.get("name")
    if not name:
        say("no name field")
    else:
        if name != d:
            say(f"name '{name}' does not match its directory '{d}'")
        if not NAME_RE.match(str(name)) or len(str(name)) > 64:
            say(f"name '{name}' is not [a-z0-9-], 1-64 chars, no leading/trailing/double hyphen")

    desc = fm.get("description")
    if not desc:
        say("no description field")
    elif len(desc) > 1024:
        say(f"description is {len(desc)} characters, over the 1024 limit")

    compat = fm.get("compatibility")
    if compat is not None and len(str(compat)) > 500:
        say(f"compatibility is {len(str(compat))} characters, over the 500 limit")

    meta = fm.get("metadata")
    if meta is not None:
        if not isinstance(meta, dict):
            say("metadata must be a map")
        else:
            for k, v in meta.items():
                if not isinstance(v, str):
                    say(f"metadata.{k} is {type(v).__name__}, the spec says string values")
                if k in SPEC | HOST:
                    say(f"metadata.{k} reuses a frontmatter field name")

    for k in set(fm) - SPEC - HOST:
        say(f"unknown field '{k}' — not in the spec and not a host field")

    body = text[m.end():]
    if len(body.splitlines()) > 500:
        say(f"body is {len(body.splitlines())} lines; the spec suggests splitting past 500")

count = len(list(root.glob("skills/*/SKILL.md")))
if problems:
    print(f"{len(problems)} problem(s) across {count} skills:\n")
    print("\n".join("  " + p for p in problems))
    sys.exit(1)
print(f"{count} skills, frontmatter valid")
