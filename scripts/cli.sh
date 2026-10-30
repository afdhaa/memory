#!/usr/bin/env bash
# team-memory command (npm bin): `npx team-memory [options]`
#   npx team-memory                 install into the current project (same as scripts/install.sh)
#   npx team-memory --no-hooks      … without agent hooks
#   npx team-memory --here          install in a subfolder of a git repository (one package of a monorepo)
#   npx team-memory --with=gemini,cursor,copilot   also add these agents' hooks (or --with=all)
#   npx team-memory --global        skill for every project + user memory
#   npx team-memory --remove-hooks  remove the agent hooks and the pre-commit block
#   npx team-memory doctor          check this project's install (hooks, AGENTS.md, pre-commit, old-name leftovers)
#   npx team-memory quiz [--md]     questions on this project's decisions, gotchas and rules (onboarding)
#   npx team-memory gaps            busy folders (git log, 90 days) that memory says nothing about
#   npx team-memory selftest        run the self-test in a temporary repo
#   npx team-memory --version
set -euo pipefail

# npm runs this through a symlink in node_modules/.bin: resolve it to find the package
src="${BASH_SOURCE[0]}"
while [ -L "$src" ]; do
  dir="$(cd -P "$(dirname "$src")" && pwd)"; src="$(readlink "$src")"
  case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
HERE="$(cd -P "$(dirname "$src")" && pwd)"

case "${1:-}" in
  doctor) exec bash "$HERE/mem.sh" doctor ;;
  quiz|gaps) c="$1"; shift; exec bash "$HERE/mem.sh" "$c" "$@" ;;
  selftest) shift; exec bash "$HERE/selftest.sh" "$@" ;;
  -v|--version) sed -n 's/^  version: *//p' "$HERE/../SKILL.md" | head -n1 ;;
  -h|--help|help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) exec bash "$HERE/install.sh" "$@" ;;
esac
