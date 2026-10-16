#!/usr/bin/env bash
# project-memory self-test. Runs everything in a throwaway repo; touches nothing of yours.
#   bash scripts/selftest.sh
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t pmtest)"
P="$TMP/my project"                      # space on purpose
export PM_USER_MEMORY="$TMP/home/.agents/memory/user.md" PM_HOOKS=on
pass=0; fail=0
ok()   { pass=$((pass + 1)); printf '  ✓ %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  ✗ %s\n' "$1"; [ -n "${2:-}" ] && printf '      got: %s\n' "$(printf '%s' "$2" | head -c 300)"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }
valid_json() { if command -v python3 >/dev/null 2>&1; then printf '%s' "$1" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; else case "$1" in \{*\}) return 0;; *) return 1;; esac; fi; }
H() { # H <event> <agent> <json>  — run the hook the way the agent would (from a subfolder)
  local out; out="$(cd "$P/src" && printf '%s' "$3" | bash "$P/.agents/skills/project-memory/hooks/pm-hook.sh" "$1" "$2")"
  valid_json "$out" || bad "valid JSON from $1/$2" "$out"; printf '%s' "$out"; }
RUN="t$$$(date +%s)"                     # unique session ids per run
J() { printf '{"session_id":"%s","cwd":"%s"%s}' "$RUN-$1" "$P" "${2:-}"; }

echo "project-memory self-test  (bash $BASH_VERSION, awk: $(awk --version 2>/dev/null | head -n1 || echo system))"
mkdir -p "$P/src/api" "$P/logs" && cd "$P" || exit 1
git init -q && git config user.email t@t && git config user.name t
echo "x" > src/app.js; echo "x" > src/api/client.js; echo "logs/" > .gitignore
mkdir -p .claude && printf '{"permissions":{"allow":["Bash(ls)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo mine"}]}]}}\n' > .claude/settings.json

echo "• install"
out="$(bash "$SRC/scripts/install.sh" 2>&1)"; check "installer exits cleanly" '[ $? -eq 0 ]' "$out"
for f in .agents/skills/project-memory/SKILL.md .claude/skills/project-memory/SKILL.md .memory/index.md AGENTS.md CLAUDE.md .claude/settings.json .codex/hooks.json .gitattributes "$PM_USER_MEMORY"; do
  check "exists: ${f#$TMP/}" "[ -e \"$f\" ]"; done
bash "$SRC/scripts/install.sh" >/dev/null 2>&1
check "re-install does not duplicate hooks" '[ "$(grep -c pm-hook.sh .claude/settings.json)" = 4 ] && [ "$(grep -c pm-hook.sh .codex/hooks.json)" = 4 ]'
check "existing settings and hooks kept" 'valid_json "$(cat .claude/settings.json)" && grep -q "echo mine" .claude/settings.json && grep -q "Bash(ls)" .claude/settings.json'
check "re-install does not duplicate bootstrap" '[ "$(grep -c project-memory:start AGENTS.md)" = 1 ]'
check "pre-commit secret check installed" 'grep -q "mem.sh secrets --staged" "$(git rev-parse --git-path hooks)/pre-commit"'

# seed memory
cat > .memory/gotchas.md <<'X'
# Gotchas

## User directives
1. **[2026-10-14] Jeda antar request ke API minimal 1 detik** #api @src/ (user, seen: 1)
   Do instead: pakai sleep(1000) di setiap loop create/publish produk.

## Build, test & tooling
1. **[2020-01-01] Old invoice tests** #invoice @src/invoice/ (agent, seen: 1)
   Do instead: ignore.
X
printf -- '- 2026-10-14 · Client API frozen; headers must match the browser. #api @src/api/ #hold (user)\n- 2026-10-10 · Produk diinput lewat array, bukan CSV. #produk (user)\n' >> .memory/decisions.md
mkdir -p .memory/topics; printf -- '- netPrice sama dengan basePrice kecuali ada diskon. #harga #produk\n' > .memory/topics/harga.md
printf -- '- topics/harga.md — aturan harga\n' >> .memory/index.md
printf -- '- Selalu jawab dalam Bahasa Indonesia.\n' >> "$PM_USER_MEMORY"
git add -A >/dev/null 2>&1; git commit -qm init >/dev/null 2>&1

echo "• session start"
for a in claude codex; do
  o="$(H session-start $a "$(J s-$a ',"source":"startup"')")"
  check "$a: memory injected" 'printf "%s" "$o" | grep -q "additionalContext"' "$o"
done
check "user memory injected" 'printf "%s" "$o" | grep -q "Bahasa Indonesia"' "$o"
check "new-project summary prompt" 'printf "%s" "$o" | grep -q "no Project summary yet"' "$o"

echo "• prompt recall & capture"
o="$(H prompt claude "$(J s-claude ',"prompt":"tambahkan harga diskon untuk produk baru"')")"
check "relevant entry recalled" 'printf "%s" "$o" | grep -q "netPrice"' "$o"
o="$(H prompt claude "$(J s-claude ',"prompt":"tambahkan harga diskon untuk produk baru"')")"
check "same entry not repeated in a session" '! printf "%s" "$o" | grep -q "netPrice"' "$o"
o="$(H prompt claude "$(J s-claude ',"prompt":"buatkan README singkat"')")"
check "unrelated prompt injects nothing" '[ "$o" = "{}" ]' "$o"
fake_bearer="abcdefghijklmnop""1234567890"   # split so secret scanners don't flag this fixture
o="$(H prompt claude "$(J s-claude ',"prompt":"jangan pakai axios ya, pakai fetch. Bearer '"$fake_bearer"' token=hunter2secret eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abc"')")"
check "correction detected" 'printf "%s" "$o" | grep -q "correction"' "$o"
check "captured to inbox" 'grep -q "axios" .memory/inbox.md'
check "secrets redacted in inbox" '! grep -qE "abcdefghijklmnop|hunter2secret|eyJzdWIi" .memory/inbox.md' "$(cat .memory/inbox.md)"
o="$(H prompt codex "$(J s-codex ',"prompt":"say \"hello\" then stop"')")"
check "escaped quotes in prompt handled" 'valid_json "$o"' "$o"
o="$(H session-start claude "$(J s-new ',"source":"startup"')")"
check "inbox triage reminder at next session" 'printf "%s" "$o" | grep -q "inbox.md holds 1"' "$o"

echo "• before edit"
o="$(H pre-edit claude "$(J e1 ",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P/src/app.js\"}")")"
check "path-tagged entry injected" 'printf "%s" "$o" | grep -q "Jeda antar request"' "$o"
o="$(H pre-edit claude "$(J e1 ",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P/README.md\"}")")"
check "file without notes: silent" '[ "$o" = "{}" ]' "$o"
for i in 1 2; do
  o="$(H pre-edit claude "$(J e1 ",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P/src/api/client.js\"}")")"
  check "claude: #hold asks (edit $i)" 'printf "%s" "$o" | grep -q "\"permissionDecision\":\"ask\""' "$o"
done
o="$(H pre-edit codex "$(J e2 ',"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: src/api/client.js\n@@\n-a\n+b\n*** End Patch"}')")"
check "codex: #hold denies with instructions" 'printf "%s" "$o" | grep -q "\"permissionDecision\":\"deny\"" && printf "%s" "$o" | grep -q "mem.sh approve"' "$o"
check "codex: never returns unsupported ask" '! printf "%s" "$o" | grep -q "\"ask\""' "$o"
o="$(H pre-edit codex "$(J e3 ',"tool_name":"apply_patch","tool_input":{"command":"*** Update File: src/app.js\n@@\n*** Update File: src/api/client.js\n"}')")"
check "codex: multi-file patch into #hold denies" 'printf "%s" "$o" | grep -q "\"permissionDecision\":\"deny\""' "$o"
check "mem.sh path from a subfolder" '(cd src && bash ../.agents/skills/project-memory/scripts/mem.sh path api/client.js) | grep -q "Client API frozen"'
bash .agents/skills/project-memory/scripts/mem.sh approve src/api/ 5 >/dev/null
o="$(H pre-edit codex "$(J e2 ',"tool_name":"apply_patch","tool_input":{"command":"*** Update File: src/api/client.js\n"}')")"
check "approved #hold area no longer blocks" '! printf "%s" "$o" | grep -q permissionDecision' "$o"
o="$(H pre-edit codex "$(J e4 ',"tool_name":"apply_patch","tool_input":{"command":"*** Update File: src/app.js\n@@\n*** Update File: src/api/client.js\n"}')")"
check "approval covers held files in a multi-file patch" '! printf "%s" "$o" | grep -q permissionDecision' "$o"
printf -- '- 2026-10-14 · Detail page frozen. #web @src/pages/[id]/ #hold (user)\n' >> .memory/decisions.md
check "@path with [id] stays specific" '! bash .agents/skills/project-memory/scripts/mem.sh path src/pages/other.js | grep -q "Detail page" && bash .agents/skills/project-memory/scripts/mem.sh path "src/pages/[id]/x.js" | grep -q "Detail page"'
git checkout -q -- .memory/decisions.md

echo "• before stop"
H session-start claude "$(J st ',"source":"startup"')" >/dev/null
o="$(H stop claude "$(J st ',"stop_hook_active":false')")"; check "no changes: silent" '[ "$o" = "{}" ]' "$o"
sleep 1; echo "log" > logs/run.log
o="$(H stop claude "$(J st ',"stop_hook_active":false')")"; check "gitignored change: silent" '[ "$o" = "{}" ]' "$o"
echo "y" >> src/app.js
o="$(H stop claude "$(J st ',"stop_hook_active":false')")"; check "code changed: reminder" 'printf "%s" "$o" | grep -q "\"decision\":\"block\""' "$o"
o="$(H stop claude "$(J st ',"stop_hook_active":true')")"; check "stop_hook_active: no loop" '[ "$o" = "{}" ]' "$o"
o="$(H stop claude "$(J st ',"stop_hook_active":false')")"; check "no new change: silent" '[ "$o" = "{}" ]' "$o"
sleep 1; echo z >> src/app.js; sleep 1; echo "- progress" >> .memory/progress.md
o="$(H stop codex "$(J st ',"stop_hook_active":false')")"; check "memory updated after change: silent" '[ "$o" = "{}" ]' "$o"

echo "• lint & secrets"
M=".agents/skills/project-memory/scripts/mem.sh"
o="$(bash $M lint 2>&1)"
check "missing @path flagged" 'printf "%s" "$o" | grep -q "@src/invoice/"' "$o"
check "stale entry flagged" 'printf "%s" "$o" | grep -q "stale?"' "$o"
check "template placeholders not flagged" '! printf "%s" "$o" | grep -q "@path/"' "$o"
printf '1. **[2020-01-01] Kafka flaky** #kafka (agent, seen: 1)\n   Do instead: restart broker.\n' >> .memory/gotchas.md
H prompt claude "$(J s-kafka ',"prompt":"kafka flaky lagi"')" >/dev/null
check "short entry used by hooks is not stale" '! bash $M lint 2>&1 | grep -q "Kafka flaky"'
git checkout -q -- .memory/gotchas.md
printf -- '- 2026-10-15 · Product id 6a868c9e-a941-41a1-801d-e92487000000 is the test clinic. #produk (user)\n' >> .memory/decisions.md
check "plain UUID is not a secret" 'bash $M secrets >/dev/null'
printf -- '- 2026-10-15 · token: eyJhbGciOiJSUzI1NiJ9.eyJhdWQiOiIxIiwianRpIjoiYWI4 (user)\n' >> .memory/decisions.md
git add .memory/decisions.md; git commit -qm leak >/dev/null 2>&1
check "pre-commit blocks a leaked token" '[ "$(git log --oneline | wc -l | tr -d " ")" = 1 ]'
git reset -q; git checkout -q -- .memory/decisions.md

echo "• team merge"
base="$(git rev-parse --abbrev-ref HEAD)"
git checkout -qb other; printf -- '- 2026-10-16 · A. #x (user)\n' >> .memory/decisions.md; git commit -qam a
git checkout -q "$base"; printf -- '- 2026-10-16 · B. #y (user)\n' >> .memory/decisions.md; git commit -qam b
git merge -q other -m m >/dev/null 2>&1; check "parallel additions merge without conflict" '[ -z "$(git diff --name-only --diff-filter=U)" ] && grep -q "· A\." .memory/decisions.md && grep -q "· B\." .memory/decisions.md'

echo "• switches"
o="$(cd "$P" && printf '{"prompt":"jangan x"}' | PM_HOOKS=off bash .agents/skills/project-memory/hooks/pm-hook.sh prompt)"; check "PM_HOOKS=off" '[ "$o" = "{}" ]' "$o"
o="$(printf '{"cwd":"%s","prompt":"jangan x"}' "$TMP" | bash "$P/.agents/skills/project-memory/hooks/pm-hook.sh" prompt)"; check "outside a project: silent" '[ "$o" = "{}" ]' "$o"
bash "$SRC/scripts/install.sh" --remove-hooks >/dev/null 2>&1
check "--remove-hooks cleans agent hooks" '! grep -q pm-hook.sh .claude/settings.json .codex/hooks.json'
check "--remove-hooks cleans pre-commit" '! grep -q "project-memory" "$(git rev-parse --git-path hooks)/pre-commit" 2>/dev/null'
check "--remove-hooks keeps other hooks and settings" 'valid_json "$(cat .claude/settings.json)" && grep -q "echo mine" .claude/settings.json && grep -q "Bash(ls)" .claude/settings.json'

echo "• scan (new project)"
S="$TMP/shop"; mkdir -p "$S/src/app" "$S/tests" && cd "$S" && git init -q && git config user.email t@t && git config user.name t
printf '{"name":"shop","packageManager":"pnpm@9.0.0","scripts":{"dev":"next dev","test":"vitest run"},"dependencies":{"next":"^14.2.3"}}\n' > package.json
printf '[project]\nname = "api"\ndependencies = ["fastapi>=0.110", "pytest"]\n' > pyproject.toml
printf 'DATABASE_URL=postgres://u:p@h/db\nexport API_TOKEN=\n' > .env.example; printf 'API_TOKEN=livevalue123456\n' > .env; echo .env > .gitignore
printf '# Shop\n\nStorefront for the clinic shop.\n' > README.md; echo x > src/app/page.tsx; echo x > tests/cart.test.ts
git add -A && git commit -qm init
out="$(bash "$SRC/scripts/mem.sh" scan 2>&1)"; check "scan creates .memory/ and codebase.md" '[ -f .memory/index.md ] && [ -f .memory/topics/codebase.md ]' "$out"
cb="$(cat .memory/topics/codebase.md)"
check "scan: package manager, framework, scripts" 'printf "%s" "$cb" | grep -q "Next.js 14.2.3" && printf "%s" "$cb" | grep -q "pnpm test" && printf "%s" "$cb" | grep -q "FastAPI"' "$cb"
check "scan: env names only, no values" 'printf "%s" "$cb" | grep -q "DATABASE_URL, API_TOKEN" && ! grep -rqE "livevalue|postgres://" .memory' "$cb"
check "scan: Key facts and Map filled" 'grep -q "^- Commands: .pnpm dev" .memory/index.md && grep -q "^- topics/codebase.md" .memory/index.md'
printf -- '- Prices are in IDR.\n' >> .memory/topics/codebase.md
awk '{ print } /^## Key facts/ { print "- Deploy: manual" }' .memory/index.md > i.tmp && grep -v '^- Commands:' i.tmp > .memory/index.md && rm i.tmp
cp .memory/index.md idx.before; bash "$SRC/scripts/mem.sh" scan >/dev/null 2>&1
check "re-scan keeps notes and edited Key facts" 'grep -q "Prices are in IDR" .memory/topics/codebase.md && cmp -s idx.before .memory/index.md' "$(diff idx.before .memory/index.md)"
rm -f idx.before
check "scan: lint clean" 'bash "$SRC/scripts/mem.sh" lint >/dev/null' "$(bash "$SRC/scripts/mem.sh" lint 2>&1)"
o="$(printf '{"session_id":"%s-sc","cwd":"%s","prompt":"update readme storefront shop"}' "$RUN" "$S" | bash "$SRC/hooks/pm-hook.sh" prompt claude)"
check "scan block not used for prompt recall" '! printf "%s" "$o" | grep -q "codebase.md"' "$o"

echo "• monorepo"
Q="$TMP/mono"; mkdir -p "$Q/pkg" && cd "$Q/pkg" && git init -q .. && git config user.email t@t && git config user.name t
bash "$SRC/scripts/install.sh" >/dev/null 2>&1
mkdir -p sub; cmd="$(grep 'session-start codex' .codex/hooks.json | sed 's/^ *"command": "//; s/",\{0,1\}$//; s/\\"/"/g')"
o="$(cd sub && printf '{"session_id":"%s-m1","cwd":"%s","source":"startup"}' "$RUN" "$Q/pkg/sub" | sh -c "$cmd")"
check "codex hook command finds the skill from a monorepo subfolder" 'printf "%s" "$o" | grep -q additionalContext' "$o"
o="$(cd "$TMP" && printf '{}' | sh -c "$cmd")"; check "codex hook command outside a project: {}" '[ "$o" = "{}" ]' "$o"
printf '{ broken\n' > .claude/settings.json; out="$(bash "$SRC/scripts/install.sh" 2>&1)"
check "invalid settings.json left untouched" '[ "$(cat .claude/settings.json)" = "{ broken" ] && printf "%s" "$out" | grep -q "NOT changed"' "$out"
printf 'token = ghp_%s\n' "abcdefghijklmnopqrstuvwxyz0123" >> .memory/index.md; git add -A >/dev/null 2>&1
check "pre-commit blocks a leak in a subfolder install" '! git commit -qm leak >/dev/null 2>&1'
git reset -q; rm -rf .memory; git add -A >/dev/null 2>&1
check "commits still work after .memory/ is removed" 'git commit -qm "no memory" >/dev/null 2>&1'

echo; echo "passed: $pass   failed: $fail"
rm -rf "$TMP" "${TMPDIR:-/tmp}/project-memory-$(id -u 2>/dev/null || echo u)/$RUN-"*
[ "$fail" -eq 0 ]
