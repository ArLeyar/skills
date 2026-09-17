#!/usr/bin/env bash
# Installs the "transcribe" skill into every agent host on this machine.
# Usage:  curl -fsSL https://raw.githubusercontent.com/ArLeyar/skills/main/skills/transcribe/install.sh | bash
#    or:  ./skills/transcribe/install.sh    (from a checkout of this repo)
#    add: --ru-model   to build the Russian fine-tune without being asked
#         (piped: curl -fsSL <url> | bash -s -- --ru-model)
set -euo pipefail

REPO_URL="https://github.com/ArLeyar/skills.git"
RAW_URL="https://raw.githubusercontent.com/ArLeyar/skills/main/skills/transcribe/install.sh"
SKILL_SUBDIR="skills/transcribe"
say() { printf '\033[1;32m==>\033[0m %s\n' "$1"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$1" >&2; exit 1; }

# --- platform: checked before anything is downloaded ---
[ "$(uname -s)" = "Darwin" ] || die "macOS is required (the local engine only runs on Apple Silicon)."
if [ "$(uname -m)" != "arm64" ]; then
  echo "WARNING: not Apple Silicon. The local engine will not run; only the cloud engines will work."
fi

# --- source: this checkout if SKILL.md sits next to the script, else a throwaway clone ---
# -f on BASH_SOURCE itself rather than -n: read from a pipe it is empty or the shell's own name,
# and either way its dirname is ".", so any directory holding a SKILL.md would be taken for ours.
SRC=""
if [ -f "${BASH_SOURCE[0]:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/SKILL.md" ]; then
  SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  command -v git >/dev/null || die "git is required. Install the Xcode Command Line Tools: xcode-select --install"
  TMP_ROOT="$(mktemp -d)"
  trap 'rm -rf "$TMP_ROOT"' EXIT        # a clone per install would otherwise pile up in /var/folders
  say "Downloading the skills repo..."
  git clone --depth 1 --quiet "$REPO_URL" "$TMP_ROOT/skills"
  SRC="$TMP_ROOT/skills/$SKILL_SUBDIR"
fi

for f in SKILL.md scripts/transcribe.py scripts/convert.py; do
  [ -f "$SRC/$f" ] || die "source is incomplete: $SRC/$f is missing."
done

# Frontmatter only, first match, or a stray "version: " in the body makes this multi-line.
NEW_VER="$(sed -n '/^version:/{s/^version:[[:space:]]*//p;q;}' "$SRC/SKILL.md")"
[ -n "$NEW_VER" ] || die "no version field in $SRC/SKILL.md; refusing to install an unversioned skill."

# --- ffmpeg (mandatory, all engines) ---
if command -v ffmpeg >/dev/null; then
  say "ffmpeg already installed"
else
  command -v brew >/dev/null || die "Homebrew not found. Install it from https://brew.sh, then run this installer again."
  say "Installing ffmpeg (takes a couple of minutes)..."
  brew install ffmpeg
fi

# --- uv (runs the script + its python deps) ---
if command -v uv >/dev/null; then
  say "uv already installed"
else
  say "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
command -v uv >/dev/null || die "uv installed but is not on PATH. Close and reopen your terminal, then run this again."

# --- targets: every agent host that exists. ~/.agents is the shared location, the other two
#     are the per-host ones; CLAUDE_CONFIG_DIR moves Claude's whole config, so honour it. ---
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TARGETS=()
[ -d "$HOME/.agents" ] && TARGETS+=("$HOME/.agents/skills/transcribe")
[ -d "$HOME/.codex" ] && TARGETS+=("$HOME/.codex/skills/transcribe")
[ -d "$CLAUDE_DIR" ] && TARGETS+=("$CLAUDE_DIR/skills/transcribe")
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=("$HOME/.agents/skills/transcribe")

# sed replacement, not a path: & and \ are special on the right-hand side, | is our delimiter.
esc_repl() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

write_skill_md() {   # <source SKILL.md> <destination SKILL.md> <dir the skill will live in>
  sed "s|__SKILL_DIR__|$(esc_repl "$3")|g" "$1" > "$2"
  # This substitution is the one thing that makes the skill runnable; a silent miss is worse
  # than a failed install, because it surfaces as a broken command hours later.
  grep -q '__SKILL_DIR__' "$2" && die "placeholder substitution failed for $3"
  return 0
}

INSTALLED=0
for DEST in "${TARGETS[@]}"; do
  PARENT="$(dirname "$DEST")"

  # A dotfiles repo that tracks this path manages it; overwriting would show up as a dirty
  # worktree in someone's config repo. Tested on the path itself, not on its ancestors —
  # a home directory under version control must not disable every install.
  # ls-files lists tracked paths under a directory; --error-unmatch would not do, it takes
  # file paths and fails on a directory, which is how this guard first went unnoticed.
  if [ -n "$(git -C "$PARENT" ls-files -- "$DEST" 2>/dev/null)" ]; then
    echo "SKIPPED: $DEST is tracked by a git repo, leaving it alone."
    echo "         To install there anyway: rm -rf \"$DEST\" and re-run this."
    continue
  fi

  # Symlinked into a checkout: rewriting SKILL.md there would edit the repo, and copying over
  # it would silently replace the link with a copy. Neither is ours to decide.
  if [ -L "$DEST" ]; then
    echo "SKIPPED: $DEST is a symlink. transcribe cannot be installed by symlink — its SKILL.md"
    echo "         carries a __SKILL_DIR__ placeholder that has to be rewritten per destination."
    echo "         Remove the link and re-run this to install a real copy."
    continue
  fi

  OLD_VER="$(sed -n '/^version:/{s/^version:[[:space:]]*//p;q;}' "$DEST/SKILL.md" 2>/dev/null || true)"
  if [ -z "$OLD_VER" ]; then
    say "Installing transcribe v$NEW_VER -> $DEST"
  elif [ "$OLD_VER" = "$NEW_VER" ]; then
    say "Already on the latest version (v$NEW_VER) -> $DEST"
  else
    say "Updating transcribe v$OLD_VER -> v$NEW_VER -> $DEST"
  fi

  # Running the installer from inside its own destination: nothing to copy, but the placeholder
  # still needs rewriting, and skipping outright used to leave the skill inert.
  if [ "$(cd "$SRC" && pwd -P)" = "$(cd "$DEST" 2>/dev/null && pwd -P || echo "")" ]; then
    write_skill_md "$DEST/SKILL.md" "$DEST/SKILL.md.new" "$DEST"
    mv "$DEST/SKILL.md.new" "$DEST/SKILL.md"
    INSTALLED=$((INSTALLED + 1))
    continue
  fi

  # Staged next door, then swapped in: an interrupted or failed copy leaves the working
  # installation untouched rather than half-replaced.
  STAGE="$PARENT/.transcribe.incoming.$$"
  rm -rf "$STAGE"
  mkdir -p "$STAGE/scripts"
  cp "$SRC/scripts/transcribe.py" "$SRC/scripts/convert.py" "$STAGE/scripts/"
  write_skill_md "$SRC/SKILL.md" "$STAGE/SKILL.md" "$DEST"
  # SKILL.md points at the README for the optional extras, so it travels with it
  [ -f "$SRC/README.md" ] && cp "$SRC/README.md" "$STAGE/README.md"
  rm -rf "$DEST"
  mv "$STAGE" "$DEST"
  INSTALLED=$((INSTALLED + 1))
done

if [ "$INSTALLED" -eq 0 ]; then
  die "nothing was installed: every target was skipped (see the lines above)."
fi

# --- optional: build the Russian fine-tune (much better on Russian speech) ---
RU_DIR="$HOME/.cache/whisper-models/whisper-large-v3-russian-mlx"
ANY_SCRIPT="${TARGETS[0]}/scripts/convert.py"
[ -f "$ANY_SCRIPT" ] || ANY_SCRIPT="$SRC/scripts/convert.py"

build_ru_model() {
  say "Building the Russian model (downloads ~3GB, takes a while)..."
  uv run --quiet "$ANY_SCRIPT" \
      --torch-name-or-path antony66/whisper-large-v3-russian \
      --mlx-path "$RU_DIR" || { echo "Conversion failed. The skill still works on the default model."; return 0; }
  # mlx_whisper looks for weights.safetensors; the converter emits model.safetensors
  [ -f "$RU_DIR/model.safetensors" ] && mv "$RU_DIR/model.safetensors" "$RU_DIR/weights.safetensors"
  if [ -f "$RU_DIR/weights.safetensors" ]; then
    say "Russian model ready: $RU_DIR"
  else
    echo "Conversion produced no weights file. The skill still works on the default model."
  fi
  return 0    # an optional extra must never take the installer down with it
}

RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))

if [ -f "$RU_DIR/weights.safetensors" ]; then
  say "Russian model already present, skipping"
elif [ "$RAM_GB" -lt 12 ] && [ "${1:-}" != "--ru-model" ]; then
  # Conversion loads the full fp32 torch model (~6GB) and the fine-tune itself needs ~3GB
  # at runtime — both thrash swap on an 8GB machine. The quantized turbo is used instead.
  say "${RAM_GB}GB RAM: skipping the Russian fine-tune, the quantized turbo model will be used"
  say "  (force it anyway: curl -fsSL $RAW_URL | bash -s -- --ru-model)"
elif [ "${1:-}" = "--ru-model" ]; then
  build_ru_model
elif [ -r /dev/tty ]; then
  printf '\nBuild the Russian fine-tune? Noticeably better on Russian speech,\nbut downloads ~3GB and takes a while. You can always do it later. [y/N] '
  read -r ans < /dev/tty || ans="n"
  case "$ans" in [yY]*) build_ru_model ;; *) say "Skipped. Using the default model." ;; esac
fi

# --- pre-warm python deps so the first transcription doesn't stall on downloads ---
WARM_SCRIPT="${TARGETS[0]}/scripts/transcribe.py"
[ -f "$WARM_SCRIPT" ] || WARM_SCRIPT="$SRC/scripts/transcribe.py"
say "Installing Python dependencies (one time, a few GB of wheels)..."
uv run --quiet "$WARM_SCRIPT" --help >/dev/null \
  || echo "WARNING: dependency install failed; it will be retried on first use."

cat <<'EOF'

Done. Restart your agent and tell it:

    transcribe /path/to/file.m4a

The transcription model itself downloads on the first run. One time only,
then it works offline. Drag an audio file into the chat window to get its path.
EOF
