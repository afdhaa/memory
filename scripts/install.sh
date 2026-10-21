#!/usr/bin/env bash
# project-memory v3 installer
#
#   bash /path/to/project-memory/scripts/install.sh               # per project (run from project root)
#   bash /path/to/project-memory/scripts/install.sh --no-hooks    # per project, instructions only
#   bash /path/to/project-memory/scripts/install.sh --remove-hooks   # agent hooks + git pre-commit block
#   bash /path/to/project-memory/scripts/install.sh --global      # skill for every project (no hooks)
#
# Skill locations (Agent Skills / SKILL.md standard):
#   Claude Code  : .claude/skills/   ~/.claude/skills/
#   Codex        : .agents/skills/   ~/.agents/skills/
#   OpenCode     : .agents/skills/   ~/.config/opencode/skills/
#   Antigravity  : .agents/skills/   ~/.gemini/antigravity/skills/
#   Pi / omp     : .agents/skills/ (omp also reads .claude/skills)
# Hooks: Claude Code -> .claude/settings.json, Codex -> .codex/hooks.json (project level).
set -euo pipefail

NAME="project-memory"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="project"; HOOKS="yes"
for a in "$@"; do case "$a" in
  --global) MODE="global" ;; --no-hooks) HOOKS="no" ;; --remove-hooks) MODE="remove-hooks" ;;
  -h|--help) sed -n '2,16p' "$0"; exit 0 ;; *) echo "unknown option: $a"; exit 1 ;; esac; done

log() { printf '  %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

copy_skill() {
  local dest="$1/$NAME"
  mkdir -p "$dest"
  if [[ "$(cd "$SRC" && pwd -P)" == "$(cd "$dest" && pwd -P)" ]]; then log "= $dest (source)"; return; fi
  rm -rf "$dest"; mkdir -p "$dest"
  cp -R "$SRC/SKILL.md" "$SRC/README.md" "$SRC/assets" "$SRC/references" "$SRC/scripts" "$SRC/hooks" "$dest/"
  chmod +x "$dest"/scripts/*.sh "$dest"/hooks/*.sh 2>/dev/null || true
  log "+ $dest"
}

link_skill() {
  local dir="$1" target="$2"
  mkdir -p "$dir"; rm -rf "${dir:?}/$NAME"
  if ln -s "$target" "$dir/$NAME" 2>/dev/null && [ -f "$dir/$NAME/SKILL.md" ]; then log "→ $dir/$NAME -> $target"
  else rm -rf "${dir:?}/$NAME"; cp -R "$SRC" "$dir/$NAME"; log "+ $dir/$NAME (copy; symlinks unavailable)"; fi
}

# merge_hooks <target.json> <snippet.json> <add|remove> — pure awk, see scripts/hooks-json.awk
merge_hooks() {
  local target="$1" snippet="$2" action="$3" in="/dev/null" err
  [ -f "$target" ] && in="$target"
  mkdir -p "$(dirname "$target")"
  if err="$(awk -v action="$action" -v mark="project-memory/hooks/pm-hook.sh" -f "$SRC/scripts/json.awk" -f "$SRC/scripts/hooks-json.awk" \
      "$in" "$snippet" 2>&1 > "$target.tmp")"; then
    [ -f "$target" ] && cp "$target" "$target.bak"
    mv "$target.tmp" "$target"
    if [ "$action" = add ]; then log "+ $target (project-memory hooks installed)"; else log "- $target (project-memory hooks removed)"; fi
  else
    rm -f "$target.tmp"
    log "! $target: ${err:-awk failed}; hooks NOT changed. Merge $snippet manually."
  fi
}

BLOCK_START="<!-- project-memory:start -->"
BLOCK=$(cat <<'MD'
<!-- project-memory:start -->
## Project memory
This project keeps persistent memory in `.memory/` (Markdown, shared by all agents) — follow the `project-memory` skill.
- Start of every task: read `.memory/index.md`, `.memory/progress.md` and, if present, `~/.agents/memory/user.md` (skip what a `[project-memory]` message already provided). Triage `.memory/inbox.md` if it has items.
- For a new request, look for related memory: `bash .agents/skills/project-memory/scripts/mem.sh search <keywords>`.
- Before editing an area: `bash .agents/skills/project-memory/scripts/mem.sh path <file>`; ask before touching anything tagged `#hold`.
- While working: record decisions, user corrections and gotchas immediately. Before finishing: update `.memory/progress.md`.
- Write memory in English (unless `.memory/index.md` sets another `Memory language:`), in plain, specific sentences without filler — see the skill's references/writing.md.
- If `.memory/index.md` Rules or `~/.agents/memory/user.md` say `Memory writes: confirm`, record the user's own instructions and corrections right away, but only propose what you concluded yourself (gotchas, decisions, progress) at the end of the task and write only what the user approves.
- Never write secrets into memory.
<!-- project-memory:end -->
MD
)

upsert_bootstrap() {
  local f="$1"
  if [[ -f "$f" ]] && grep -qF "$BLOCK_START" "$f"; then
    BLK="$BLOCK" awk -v start="$BLOCK_START" -v end="<!-- project-memory:end -->" '
      $0==start {print ENVIRON["BLK"]; skip=1; next} skip && $0==end {skip=0; next} !skip {print}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    log "~ $f (bootstrap block updated)"
  else
    { [[ -s "$f" ]] && printf '\n'; printf '%s\n' "$BLOCK"; } >> "$f"; log "+ $f (bootstrap block added)"
  fi
}

USER_MEM="${PM_USER_MEMORY:-$HOME/.agents/memory/user.md}"
ensure_user_memory() {
  if [ -f "$USER_MEM" ]; then log "= ${USER_MEM/#$HOME/~} (user memory exists)"
  else mkdir -p "$(dirname "$USER_MEM")"; cp "$SRC/assets/user/user.md" "$USER_MEM"; log "+ ${USER_MEM/#$HOME/~} (user memory, all projects)"; fi
}

add_line_once() { # file line
  grep -qxF "$2" "$1" 2>/dev/null || { [ -s "$1" ] && [ -n "$(tail -c1 "$1")" ] && printf '\n' >> "$1"; printf '%s\n' "$2" >> "$1"; return 0; }
  return 1
}

PC_START="# project-memory:start"; PC_END="# project-memory:end"
# Runs from the git root: checks every folder with staged .memory/ changes that has the skill installed.
PC_BLOCK='# project-memory:start
git diff --cached --name-only --diff-filter=ACM | sed -n '"'"'s#^\(.*/\)\{0,1\}\.memory/.*#\1#p'"'"' | sort -u | while IFS= read -r d; do
  if [ -f "./${d}.agents/skills/project-memory/scripts/mem.sh" ]; then
    (cd "./$d" && bash .agents/skills/project-memory/scripts/mem.sh secrets --staged) || exit 1
  fi
done || exit 1
# project-memory:end'

hooks_dir() {
  local hp top; hp="$(git -C "$ROOT" config core.hooksPath 2>/dev/null || true)"
  top="$(git -C "$ROOT" rev-parse --show-toplevel)"
  if [ -n "$hp" ]; then case "$hp" in /*) echo "$hp";; *) echo "$top/$hp";; esac   # relative hooksPath is relative to the git root
  else hp="$(git -C "$ROOT" rev-parse --git-path hooks)"; case "$hp" in /*) echo "$hp";; *) echo "$ROOT/$hp";; esac; fi
}

install_precommit() {
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { log "- git pre-commit skipped (not a git repo)"; return; }
  local dir f; dir="$(hooks_dir)"; f="$dir/pre-commit"; mkdir -p "$dir"
  local refreshed=""
  if [ -f "$f" ] && grep -qF "$PC_START" "$f"; then strip_precommit "$f"; refreshed=1; fi
  if [ -f "$f" ]; then
    if head -n1 "$f" | grep -qE '^#!.*(ba)?sh'; then
      BLK="$PC_BLOCK" awk 'NR==1{print; print ENVIRON["BLK"]; next} {print}' "$f" > "$f.tmp" && cat "$f.tmp" > "$f" && rm -f "$f.tmp"
      [ -n "$refreshed" ] && log "~ $f (secret check updated)" || log "+ $f (secret check inserted at the top of existing hook)"
    else log "! $f is not a shell script — add manually: bash .agents/skills/project-memory/scripts/mem.sh secrets --staged"; return; fi
  else printf '#!/bin/sh\n%s\n' "$PC_BLOCK" > "$f"; log "+ $f (blocks commits that put secrets in .memory/)"; fi
  chmod +x "$f"
}

remove_precommit() {
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || return 0
  local f; f="$(hooks_dir)/pre-commit"
  [ -f "$f" ] && grep -qF "$PC_START" "$f" || return 0
  strip_precommit "$f"
  log "- $f (secret check removed)"
}

strip_precommit() {
  awk -v s="$PC_START" -v e="$PC_END" '$0==s{skip=1;next} skip&&$0==e{skip=0;next} !skip{print}' "$1" > "$1.tmp" && cat "$1.tmp" > "$1" && rm -f "$1.tmp"
}

ROOT="$(pwd)"

if [[ "$MODE" == "remove-hooks" ]]; then
  echo "Removing project-memory hooks from: $ROOT"
  [ -f "$ROOT/.claude/settings.json" ] && merge_hooks "$ROOT/.claude/settings.json" "$SRC/hooks/claude-settings.snippet.json" remove
  [ -f "$ROOT/.codex/hooks.json" ] && merge_hooks "$ROOT/.codex/hooks.json" "$SRC/hooks/codex-hooks.snippet.json" remove
  remove_precommit
  exit 0
fi

if [[ "$MODE" == "global" ]]; then
  echo "Installing $NAME globally (skill only; hooks are per project):"
  copy_skill "$HOME/.agents/skills"
  copy_skill "$HOME/.claude/skills"
  copy_skill "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills"
  copy_skill "$HOME/.gemini/antigravity/skills"
  ensure_user_memory
  echo; echo "Done. Run this script without --global inside a project to add .memory/, the bootstrap lines and hooks."
  exit 0
fi

echo "Installing $NAME v3 into: $ROOT"
copy_skill "$ROOT/.agents/skills"
link_skill "$ROOT/.claude/skills" "../../.agents/skills/$NAME"

if [[ -d "$ROOT/.memory" ]]; then
  log "= .memory/ (exists, untouched)"
  [ -f "$ROOT/.memory/README.md" ] || { cp "$SRC/assets/templates/README.md" "$ROOT/.memory/README.md"; log "+ .memory/README.md (explains the memory files to people)"; }
  [ -f "$ROOT/.memory/topics/codebase.md" ] || log "  tip: index this repo with: bash .agents/skills/project-memory/scripts/mem.sh scan"
else
  cp -R "$SRC/assets/templates" "$ROOT/.memory"; log "+ .memory/ (from templates)"
  (cd "$ROOT" && bash .agents/skills/project-memory/scripts/mem.sh scan) | while IFS= read -r l; do log "$l"; done
fi

if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  for l in ".memory/local.md" ".memory/inbox.md" ".memory/.stats.tsv" ".memory/.approvals"; do
    add_line_once "$ROOT/.gitignore" "$l" && log "+ .gitignore ($l)"; done
  # team-safe merges: concurrent appends from two branches are combined instead of conflicting
  for l in ".memory/decisions.md merge=union" ".memory/gotchas.md merge=union"; do
    add_line_once "$ROOT/.gitattributes" "$l" && log "+ .gitattributes ($l)"; done
  install_precommit
fi
ensure_user_memory

upsert_bootstrap "$ROOT/AGENTS.md"
upsert_bootstrap "$ROOT/CLAUDE.md"

if [[ "$HOOKS" == "yes" ]]; then
  merge_hooks "$ROOT/.claude/settings.json" "$SRC/hooks/claude-settings.snippet.json" add
  merge_hooks "$ROOT/.codex/hooks.json"     "$SRC/hooks/codex-hooks.snippet.json"     add
  echo
  echo "Hooks: Claude Code may ask you to review/approve project hooks (/hooks), and Codex asks you"
  echo "to trust the project and its hooks the first time. Disable temporarily with: export PM_HOOKS=off"
fi

echo
echo "Done. Next, open your agent here and say: \"complete .memory/index.md from the scan\""
