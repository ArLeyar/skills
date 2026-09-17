#!/usr/bin/env bash
# Exercises the installer's target-selection and staging logic against fake homes.
# uv and ffmpeg are stubbed: this checks the shell logic, not the python.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
SRC="$(cd "$HERE/.." && pwd)"
STUB="$SB/stub"
mkdir -p "$STUB"
printf '#!/bin/sh\nexit 0\n' > "$STUB/uv";     chmod +x "$STUB/uv"
printf '#!/bin/sh\nexit 0\n' > "$STUB/ffmpeg"; chmod +x "$STUB/ffmpeg"
export PATH="$STUB:$PATH"
# The installer honours CLAUDE_CONFIG_DIR, which points at the real config in a live session:
# without this the test writes into it. Overriding HOME alone is not isolation.
unset CLAUDE_CONFIG_DIR

pass=0; fail=0
check() { # <description> <condition-result>
  if [ "$2" = "0" ]; then pass=$((pass+1)); echo "  ok   $1"
  else fail=$((fail+1)); echo "  FAIL $1"; fi
}
fresh_home() { rm -rf "$1"; mkdir -p "$1"; }

echo "1. fresh install into two hosts"
H="$SB/h1"; fresh_home "$H"; mkdir -p "$H/.agents" "$H/.claude"
HOME="$H" bash "$SRC/install.sh" >"$SB/h1.log" 2>&1; rc=$?
check "exit 0" "$([ $rc -eq 0 ] && echo 0 || echo 1)"
check "installed into ~/.agents" "$([ -f "$H/.agents/skills/transcribe/SKILL.md" ] && echo 0 || echo 1)"
check "installed into ~/.claude" "$([ -f "$H/.claude/skills/transcribe/SKILL.md" ] && echo 0 || echo 1)"
check "placeholder substituted" "$(grep -q '__SKILL_DIR__' "$H/.agents/skills/transcribe/SKILL.md" && echo 1 || echo 0)"
check "destination path written in" "$(grep -q "$H/.agents/skills/transcribe" "$H/.agents/skills/transcribe/SKILL.md" && echo 0 || echo 1)"
check "README shipped alongside" "$([ -f "$H/.agents/skills/transcribe/README.md" ] && echo 0 || echo 1)"
check "no staging dir left behind" "$([ -z "$(find "$H" -name '.transcribe.incoming.*' 2>/dev/null)" ] && echo 0 || echo 1)"

echo "1b. the version is read from metadata, so a re-run recognises the install"
HOME="$H" bash "$SRC/install.sh" >"$SB/h1b.log" 2>&1
check "reports the version, not an empty string" "$(grep -qE 'v[0-9]+\.[0-9]+\.[0-9]+' "$SB/h1b.log" && echo 0 || echo 1)"
check "second run says it is already current" "$(grep -q 'Already on the latest version' "$SB/h1b.log" && echo 0 || echo 1)"

echo "2. home under version control still installs"
H="$SB/h2"; fresh_home "$H"; mkdir -p "$H/.agents"
git -C "$H" init -q 2>/dev/null
HOME="$H" bash "$SRC/install.sh" >"$SB/h2.log" 2>&1; rc=$?
check "exit 0" "$([ $rc -eq 0 ] && echo 0 || echo 1)"
check "installed anyway" "$([ -f "$H/.agents/skills/transcribe/SKILL.md" ] && echo 0 || echo 1)"

echo "3. destination tracked by git is left alone"
H="$SB/h3"; fresh_home "$H"; mkdir -p "$H/.agents/skills/transcribe"
git -C "$H" init -q 2>/dev/null
echo "mine" > "$H/.agents/skills/transcribe/SKILL.md"
git -C "$H" add -f .agents/skills/transcribe/SKILL.md >/dev/null 2>&1
git -C "$H" -c user.email=t@t -c user.name=t commit -qm x >/dev/null 2>&1
HOME="$H" bash "$SRC/install.sh" >"$SB/h3.log" 2>&1; rc=$?
check "exits non-zero when everything was skipped" "$([ $rc -ne 0 ] && echo 0 || echo 1)"
check "tracked file untouched" "$([ "$(cat "$H/.agents/skills/transcribe/SKILL.md")" = "mine" ] && echo 0 || echo 1)"
check "says nothing was installed" "$(grep -qi 'nothing was installed' "$SB/h3.log" && echo 0 || echo 1)"

echo "4. symlinked destination is refused, not overwritten"
H="$SB/h4"; fresh_home "$H"; mkdir -p "$H/.agents/skills" "$H/checkout"
cp -R "$SRC" "$H/checkout/transcribe"
ln -s "$H/checkout/transcribe" "$H/.agents/skills/transcribe"
HOME="$H" bash "$SRC/install.sh" >"$SB/h4.log" 2>&1
check "symlink still a symlink" "$([ -L "$H/.agents/skills/transcribe" ] && echo 0 || echo 1)"
check "checkout SKILL.md not rewritten" "$(grep -q '__SKILL_DIR__' "$H/checkout/transcribe/SKILL.md" && echo 0 || echo 1)"
check "explains why" "$(grep -qi 'cannot be installed by symlink' "$SB/h4.log" && echo 0 || echo 1)"

echo "5. installer run from inside its own destination substitutes in place"
H="$SB/h5"; fresh_home "$H"; mkdir -p "$H/.agents/skills"
cp -R "$SRC" "$H/.agents/skills/transcribe"
HOME="$H" bash "$H/.agents/skills/transcribe/install.sh" >"$SB/h5.log" 2>&1; rc=$?
check "exit 0" "$([ $rc -eq 0 ] && echo 0 || echo 1)"
check "placeholder gone" "$(grep -q '__SKILL_DIR__' "$H/.agents/skills/transcribe/SKILL.md" && echo 1 || echo 0)"
check "no SKILL.md.new left" "$([ ! -f "$H/.agents/skills/transcribe/SKILL.md.new" ] && echo 0 || echo 1)"

echo "6. a path containing & and a backslash survives the substitution"
H="$SB/h6 & co"; fresh_home "$H"; mkdir -p "$H/.agents"
HOME="$H" bash "$SRC/install.sh" >"$SB/h6.log" 2>&1
check "literal path written, & not expanded" "$(grep -qF "$H/.agents/skills/transcribe/scripts" "$H/.agents/skills/transcribe/SKILL.md" && echo 0 || echo 1)"

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
