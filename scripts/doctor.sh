#!/usr/bin/env bash
# team-memory install check — run through `mem.sh doctor`, which passes the project root.
#   bash doctor.sh <root>
# Checks the skill copies, agent hooks, AGENTS.md/CLAUDE.md block, git pre-commit check and gitignore
# rules, and finds leftovers of the skill's old name (project-memory). Reads only; changes nothing.
# Exit 1 when something is broken (✗), 0 otherwise (warnings are ! lines).
set -u
export LC_ALL=C
ROOT="$1"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1
NAME="team-memory"; OLD="project-memory"; TL='~'
FIX="npx team-memory@latest"   # re-running the installer repairs everything below
BAD=0; WARN=0
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; WARN=$((WARN + 1)); }
bad()  { printf '  ✗ %s\n' "$*"; BAD=$((BAD + 1)); }
home() { printf '%s' "${1/#"$HOME"/$TL}"; }
ver()  { sed -n 's/^  version: *//p' "$1/SKILL.md" 2>/dev/null | head -n1; }
IS_GIT=""; git rev-parse --git-dir >/dev/null 2>&1 && IS_GIT=1

echo "team-memory doctor — $(home "$ROOT")"
echo "this script: $(home "$(cd "$HERE/.." && pwd)") (v$(ver "$HERE/.."))"

echo "• skill"
SK=".agents/skills/$NAME"; PV=""
if [ -f "$SK/SKILL.md" ]; then PV="$(ver "$SK")"; ok "$SK (v$PV)"
else warn "no project copy in $SK: hooks and the AGENTS.md commands need it — run $FIX"; fi
if [ -f ".claude/skills/$NAME/SKILL.md" ]; then
  cv="$(ver ".claude/skills/$NAME")"
  [ -n "$PV" ] && [ "$cv" != "$PV" ] && warn ".claude/skills/$NAME is v$cv, $SK is v$PV — run $FIX" || ok ".claude/skills/$NAME (Claude Code)"
else warn ".claude/skills/$NAME is missing: Claude Code will not see the skill — run $FIX"; fi
GLOBALS="$HOME/.agents/skills $HOME/.claude/skills ${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills $HOME/.gemini/antigravity/skills"
for d in $GLOBALS; do
  [ -f "$d/$NAME/SKILL.md" ] || continue
  gv="$(ver "$d/$NAME")"
  if [ -n "$PV" ] && [ "$gv" != "$PV" ]; then warn "global copy $(home "$d/$NAME") is v$gv, this project has v$PV — update it: $FIX --global"
  else ok "global copy $(home "$d/$NAME") (v$gv)"; fi
done

echo "• old name ($OLD)"
old=0
for d in .agents/skills .claude/skills $GLOBALS; do
  [ -e "$d/$OLD" ] || [ -L "$d/$OLD" ] || continue
  # a folder of that name that is not this skill is someone else's
  if [ -L "$d/$OLD" ] || grep -q "^name: $OLD\$" "$d/$OLD/SKILL.md" 2>/dev/null; then
    old=1; case "$d" in "$HOME"/*) bad "$(home "$d/$OLD") — the skill under its old name: run $FIX --global (installed from skills.sh: npx skills remove $OLD)" ;;
                          *) bad "$d/$OLD — the skill under its old name: run $FIX" ;; esac
  fi
done
for f in .claude/settings.json .claude/settings.local.json .codex/hooks.json AGENTS.md CLAUDE.md; do
  grep -q "$OLD" "$f" 2>/dev/null && { old=1; bad "$f still refers to $OLD — run $FIX"; }
done
[ "$old" = 0 ] && ok "no leftovers"

if [ ! -d .memory ] && [ ! -f "$SK/SKILL.md" ]; then
  echo; echo "team-memory is not installed in this project. Install it from the project root: npx team-memory"
  [ "$BAD" -gt 0 ] && exit 1; exit 0
fi

echo "• agent hooks"
hookcheck() { # <file> <agent>
  local f="$1" n
  if [ ! -f "$f" ]; then warn "$f is missing: no $2 hooks (recall before edits, #hold, capture) — run $FIX"; return; fi
  n="$(grep -c "$NAME/hooks/pm-hook.sh" "$f")"
  if [ "$n" -ge 4 ]; then ok "$f ($n hooks)"
  elif [ "$n" -gt 0 ]; then warn "$f has $n of 4 $NAME hooks — run $FIX"
  else warn "$f has no $NAME hooks — run $FIX"; fi
  [ -n "$IS_GIT" ] && git check-ignore -q --no-index "$f" 2>/dev/null && warn "$f is gitignored: teammates will not get the hooks"
}
hookcheck .claude/settings.json "Claude Code"
hookcheck .codex/hooks.json Codex
[ -f "$SK/hooks/pm-hook.sh" ] || { grep -qs "$NAME/hooks/pm-hook.sh" .claude/settings.json .codex/hooks.json && bad "the hooks call $SK/hooks/pm-hook.sh, which does not exist — run $FIX"; }
[ "${PM_HOOKS:-}" = off ] && warn "PM_HOOKS=off in this shell: hooks do nothing (unset PM_HOOKS to turn them on)"

echo "• agent instructions"
if grep -qF "<!-- $NAME:start -->" AGENTS.md 2>/dev/null; then ok "AGENTS.md has the $NAME block"
else warn "AGENTS.md has no $NAME block: agents without hooks will not know about .memory/ — run $FIX"; fi
if [ -L CLAUDE.md ]; then ok "CLAUDE.md links to $(readlink CLAUDE.md)"
elif grep -qE '(^|[[:space:](])@\.?/?AGENTS\.md([[:space:]).,;:]|$)' CLAUDE.md 2>/dev/null; then ok "CLAUDE.md imports AGENTS.md"
elif grep -qF "<!-- $NAME:start -->" CLAUDE.md 2>/dev/null; then ok "CLAUDE.md has the $NAME block"
elif [ -f CLAUDE.md ]; then warn "CLAUDE.md neither imports AGENTS.md nor has the $NAME block: Claude Code reads CLAUDE.md, not AGENTS.md — run $FIX"
else warn "no CLAUDE.md: Claude Code will not read AGENTS.md — run $FIX"; fi

echo "• git"
if [ -z "$IS_GIT" ]; then warn "not a git repository: memory is not shared, and there is no pre-commit secret check"
else
  # same lookup as the installer: core.hooksPath (husky 9: .husky/_ → .husky) or .git/hooks
  hp="$(git config core.hooksPath 2>/dev/null || true)"; top="$(git rev-parse --show-toplevel)"
  case "$hp" in *.husky/_|*.husky/_/) hp="${hp%/}"; hp="${hp%/_}" ;; esac
  if [ -n "$hp" ]; then case "$hp" in /*) ;; *) hp="$top/$hp" ;; esac; else hp="$(cd "$(git rev-parse --git-path hooks)" 2>/dev/null && pwd || echo "$top/.git/hooks")"; fi
  pc="$hp/pre-commit"
  if grep -qF "# $NAME:start" "$pc" 2>/dev/null; then
    case "$pc" in */.husky/*) ok "pre-commit secret check ($(home "${pc#"$top"/}"))" ;;
      *) [ -x "$pc" ] && ok "pre-commit secret check" || bad "$pc is not executable, so git skips it: chmod +x it" ;; esac
  elif grep -qF "# $OLD:start" "$pc" 2>/dev/null; then bad "pre-commit check still uses the old name ($OLD) — run $FIX"
  else warn "no pre-commit secret check in $(home "${pc#"$top"/}") — run $FIX"; fi
  miss=""
  for f in progress.md inbox.md local.md; do git check-ignore -q --no-index ".memory/$f" 2>/dev/null || miss="$miss .memory/$f"; done
  [ -z "$miss" ] && ok "personal files are gitignored" || bad "not gitignored:$miss — personal notes would be committed: run $FIX"
  git ls-files --error-unmatch .memory/progress.md >/dev/null 2>&1 && warn ".memory/progress.md is committed: git rm --cached .memory/progress.md"
  git check-ignore -q --no-index .memory/index.md 2>/dev/null && bad ".memory/ is gitignored: the team never gets it — add !.memory/ to .gitignore"
  [ "$(git check-attr merge -- .memory/decisions.md 2>/dev/null | sed 's/.*: //')" = union ] && ok "merge=union for decisions.md and gotchas.md" ||
    warn ".gitattributes has no merge=union for .memory/decisions.md: parallel branches will conflict — run $FIX"
fi

echo "• memory"
if [ -d .memory ]; then
  [ -f .memory/index.md ] && ok ".memory/index.md" || bad ".memory/index.md is missing — run: bash $SK/scripts/mem.sh scan"
  [ -f .memory/topics/codebase.md ] || warn "no .memory/topics/codebase.md yet — run: bash $SK/scripts/mem.sh scan"
else warn "no .memory/ here — run: bash $SK/scripts/mem.sh scan"; fi
U="${PM_USER_MEMORY:-$HOME/.agents/memory/user.md}"
[ -f "$U" ] && ok "user memory $(home "$U")" || warn "no user memory at $(home "$U") (optional; the installer creates it)"

echo
if [ "$BAD" -gt 0 ]; then echo "✗ $BAD problem(s), $WARN warning(s)"; exit 1; fi
[ "$WARN" -gt 0 ] && echo "✓ working, $WARN warning(s)" || echo "✓ all good"
exit 0
