#!/usr/bin/env bash
# project-memory v3 hook runner — pure bash + awk (no jq/python/node).
# Claude Code and Codex share this hook JSON schema.
# Usage: pm-hook.sh <session-start|prompt|pre-edit|stop> [claude|codex]
# Disable: export PM_HOOKS=off      Tune: PM_RECALL_MAX (5), PM_MAX_NUDGES (3)
set -u

EVENT="${1:-}"
AGENT="${2:-claude}"
INPUT="$(cat 2>/dev/null || true)"
INPUT_1L="$(printf '%s' "$INPUT" | tr '\n' ' ')"
TODAY="$(date +%Y-%m-%d)"
USER_MEM="${PM_USER_MEMORY:-$HOME/.agents/memory/user.md}"

emit_empty() { printf '{}\n'; exit 0; }
[ "${PM_HOOKS:-on}" = "off" ] && emit_empty

json_escape() {
  local s="$1"
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\t'/\\t}; s=${s//$'\r'/}; s=${s//$'\n'/\\n}
  printf '%s' "$s"
}
json_str() { # first occurrence of a simple string field
  printf '%s' "$INPUT_1L" | grep -oE '"'"$1"'"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed 's/^[^:]*:[[:space:]]*"//; s/"$//'
}
json_long_str() { # first occurrence of a string field that may contain escapes; lightly unescaped
  printf '%s' "$INPUT_1L" | grep -oE '"'"$1"'"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -n1 |
    sed -e 's/^[^:]*:[[:space:]]*"//' -e 's/"$//' -e 's/\\[nrt]/ /g' -e 's/\\"/"/g' -e 's/\\\\/\\/g'
}
cap() { local t="$1" n="$2"
  if [ "${#t}" -gt "$n" ]; then printf '%s\n…[truncated — open the file for the rest]' "${t:0:$n}"; else printf '%s' "$t"; fi; }
hash() { printf '%s' "$1" | cksum | cut -d' ' -f1; }
redact() { sed -E \
  -e 's/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}(\.[A-Za-z0-9_-]+)?/[REDACTED]/g' \
  -e 's/(sk-|gh[pousr]_|xox[baprs]-|AKIA)[A-Za-z0-9_-]{10,}/[REDACTED]/g' \
  -e 's/[Bb]earer [A-Za-z0-9._-]{16,}/Bearer [REDACTED]/g' \
  -e 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/[REDACTED]/g' \
  -e 's/(([Pp][Aa][Ss][Ss]([Ww][Oo][Rr][Dd]|[Ww][Dd])|[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn])[[:space:]]*[:=][[:space:]]*)[^[:space:]]{6,}/\1[REDACTED]/g'; }

# @path tag: letters, digits, _ . / - and the ( ) [ ] used by route folders such as app/[id]/ or app/(auth)/
export PM_TAG_RE='(^|[ 	(])@[A-Za-z0-9_.]([A-Za-z0-9_./()-]|\[|\])*'
# ---- project root: nearest ancestor with .memory/ ----
CWD="$(json_str cwd)"; [ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$(pwd)"
ROOT="$CWD"
while [ "$ROOT" != "/" ] && [ -n "$ROOT" ] && [ ! -d "$ROOT/.memory" ]; do ROOT="$(dirname "$ROOT")"; done
[ -d "$ROOT/.memory" ] || emit_empty
MEM="$ROOT/.memory"
# write mode: "Memory writes: confirm|auto" in index.md Rules (project) wins over user.md (all projects); default auto
write_mode() {
  local f m
  for f in "$MEM/index.md" "$USER_MEM"; do
    m="$(grep -iE '^[[:space:]]*[-*][[:space:]]*Memory writes:[[:space:]]*(auto|confirm)' "$f" 2>/dev/null | head -n1 | tr 'A-Z' 'a-z')"
    case "$m" in *confirm*) echo confirm; return;; *auto*) echo auto; return;; esac
  done
  echo auto
}
MODE="$(write_mode)"
STATS="$MEM/.stats.tsv"     # gitignored: date <TAB> hash of entry line, one row per injection

SID="$(json_str session_id)"; SID="${SID//[^A-Za-z0-9_-]/}"; [ -n "$SID" ] || SID="nosession"
STATE="${TMPDIR:-/tmp}/project-memory-$(id -u 2>/dev/null || echo u)/$SID"
mkdir -p "$STATE" 2>/dev/null || emit_empty

# inject_new <lines "file:line: text"> → prints only lines not yet injected this session; records hits
inject_new() {
  local out="" h key
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    key="$(hash "$h")"
    grep -qx "$key" "$STATE/injected" 2>/dev/null && continue
    printf '%s\n' "$key" >> "$STATE/injected"
    printf '%s\t%s\n' "$TODAY" "$(hash "$(printf '%s' "$h" | sed 's/^[^:]*:[0-9]*: //; s/ ↳ .*//' | head -n1 | LC_ALL=C cut -c1-60)")" >> "$STATS" 2>/dev/null
    out="$out$h"$'\n'
  done
  printf '%s' "$out"
}

PRUNE=(-path "$ROOT/.git" -o -path "$ROOT/.memory" -o -path "$ROOT/node_modules" -o -path "$ROOT/.venv" \
       -o -path "$ROOT/venv" -o -path "$ROOT/dist" -o -path "$ROOT/build" -o -path "$ROOT/target" \
       -o -path "$ROOT/.next" -o -path "$ROOT/vendor" -o -path "$ROOT/.cache" -o -name "__pycache__" \
       -o -path "$ROOT/.agents" -o -path "$ROOT/.claude" -o -path "$ROOT/.codex" -o -path "$ROOT/.omp")

case "$EVENT" in
# ---------------------------------------------------------------------------
session-start)
  touch "$STATE/start"; rm -f "$STATE/nudged" "$STATE/nudges" "$STATE/injected" 2>/dev/null
  SOURCE="$(json_str source)"
  idx=""; [ -f "$MEM/index.md" ] && idx="$(cat "$MEM/index.md")"
  prog=""; [ -f "$MEM/progress.md" ] && prog="$(cat "$MEM/progress.md")"
  files="$(cd "$MEM" && find topics procedures -type f -name '*.md' 2>/dev/null | sort | head -n 60)"
  ctx="[project-memory] Persistent memory for this project is in .memory/ (follow the project-memory skill).
--- .memory/index.md ---
$(cap "$idx" 12000)
--- .memory/progress.md ---
$(cap "$prog" 4000)"
  if [ -f "$USER_MEM" ] && grep -qvE '^[[:space:]]*(#|>|<!--|$)' "$USER_MEM"; then
    ctx="$ctx
--- user memory (applies to all projects): ${USER_MEM/#$HOME/~} ---
$(cap "$(grep -vE '^[[:space:]]*<!--.*-->[[:space:]]*$' "$USER_MEM")" 4000)"
  fi
  [ -n "$files" ] && ctx="$ctx
--- other memory files (open when relevant; search: bash .agents/skills/project-memory/scripts/mem.sh search <words>) ---
$files"
  # sections still empty (only the template comment) → ask the agent to write them
  # (heading missing = custom layout: do not nag)
  section_empty() { LC_ALL=C awk -v h="## $1" '/^## /{ on = ($0 == h); if (on) seen = 1; next }
      on && /^[[:space:]]*<!--/ { c = !/-->/; next } on && c { if (/-->/) c = 0; next }
      on && /[^[:space:]]/ { full = 1 } END { exit (full || !seen) }'; }
  cbm=""; if [ -f "$MEM/topics/codebase.md" ]; then
    section_empty "How it fits together" < "$MEM/topics/codebase.md" && cbm="the \"How it fits together\" section (3–6 short paragraphs in full sentences: main parts, how a request or job flows through the code, where to start reading, non-obvious conventions)"
    section_empty "Project layout" < "$MEM/topics/codebase.md" && cbm="${cbm:+$cbm and }the \"Project layout\" section (one line per folder a newcomer needs: what lives there, where new code of that kind goes)"
  fi
  if printf '%s\n' "$idx" | section_empty "Project summary"; then
    scan="Read .memory/topics/codebase.md (generated repo scan)"
    [ -f "$MEM/topics/codebase.md" ] || scan="First run: bash .agents/skills/project-memory/scripts/mem.sh scan (indexes the repo into .memory/topics/codebase.md and fills Key facts), then read .memory/topics/codebase.md"
    ctx="$ctx
[project-memory] New project memory: index.md has no Project summary yet. Early in this session: $scan and README, then write a 3–5 sentence Project summary in index.md (what it is, who uses it, current stage)${cbm:+, write $cbm of .memory/topics/codebase.md}, check Key facts, and tell the user in one line."
  elif [ -n "$cbm" ]; then
    ctx="$ctx
[project-memory] .memory/topics/codebase.md is missing explanations. Early in this session, read its generated facts, the README and the main entry points, then write $cbm. Tell the user in one line."
  fi
  [ "$MODE" = confirm ] && ctx="$ctx
[project-memory] Memory writes: CONFIRM mode. Write the user's own corrections, standing instructions and explicit requests (\"remember…\", \"ingat…\", \"catat…\") right away. Everything you conclude yourself (gotchas, decisions, progress, topics, procedures, codebase.md) you only propose: at the end of a task, list the exact entries in one numbered message and write only what the user approves. Keep unanswered proposals in .memory/inbox.md."
  if [ -f "$MEM/inbox.md" ]; then
    n="$(grep -c '^- ' "$MEM/inbox.md" 2>/dev/null)"; n="${n:-0}"
    [ "$n" -gt 0 ] && ctx="$ctx
[project-memory] .memory/inbox.md holds $n captured user remark(s) that may be corrections. Triage them now: record durable ones (gotchas.md User directives, index.md Rules, or user memory if they apply to every project), skip duplicates and one-offs, then empty the inbox. Report in one line."
    [ "$n" -gt 0 ] && [ "$MODE" = confirm ] && ctx="$ctx
[project-memory] Confirm mode: lines marked \"proposed\" in the inbox are entries the user has not answered yet. Ask about them (and about the remarks) in one numbered message; write only what they approve."
  fi
  [ "$SOURCE" = "compact" ] && ctx="$ctx
[project-memory] The conversation was just compacted. If the summary contains decisions, user corrections or progress that are not yet in .memory/, record them now before continuing (confirm mode: add them to your next memory proposal instead)."
  printf '{"systemMessage":"📝 project-memory loaded","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$(json_escape "$ctx")"
  ;;
# ---------------------------------------------------------------------------
prompt)
  src="$(json_str source)"
  PROMPT="$(json_long_str prompt)"
  [ -n "$PROMPT" ] || emit_empty
  ctx=""
  # (a) correction / standing-instruction capture → inbox (local, redacted)
  if [ -z "$src" ] || [ "$src" = "user" ]; then
    if printf '%s' "$PROMPT" | grep -qiE "(^|[^a-z])(jangan|salah|keliru|bukan (begitu|itu|gitu|ini)|seharusnya|harusnya|mestinya|lain kali|ingat( ya|lah)?|tolong ingat|kok malah|kenapa malah|selalu|dont|don't|do not|never|always|instead|wrong|that's not|stop doing|remember|should have|next time)([^a-z]|$)"; then
      excerpt="$(printf '%s' "$PROMPT" | redact | cut -c1-300)"
      key="$(hash "$excerpt")"
      if ! grep -qF "<!-- $key -->" "$MEM/inbox.md" 2>/dev/null; then
        [ -f "$MEM/inbox.md" ] || printf '# Inbox\n\n> Captured automatically from user prompts (local, gitignored). Triaged by the agent: record durable items, then delete them.\n\n' > "$MEM/inbox.md"
        printf -- '- %s · "%s" <!-- %s -->\n' "$TODAY" "$excerpt" "$key" >> "$MEM/inbox.md"
      fi
      ctx="[project-memory] This message looks like a correction or standing instruction (captured in .memory/inbox.md). If it is durable, record it now (rewritten in the memory language — English unless index.md sets another — as a clear entry) as a User directive in .memory/gotchas.md (or a Rule in index.md; user memory if it applies to every project) and remove it from the inbox. If it is a one-off, just remove it from the inbox."
    fi
  fi
  # (b) prompt-based recall: rank memory entries against the prompt
  terms="$(printf '%s' "$PROMPT" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9\n' ' ' | tr ' ' '\n' | awk '
    BEGIN { split("the and for with that this from have what when where which will would could should there their them they then than into your you are was were been being can not but all any how why who use using make made also just like want need get got its it'"'"'s yang dan atau dengan untuk dari pada ini itu ada akan bisa saya kamu anda kita kami mau tidak juga sudah belum lagi apa apakah bagaimana gimana kenapa buat bikin tolong coba dong deh sih nya aja saja jadi kalau kalo karena agar supaya seperti dalam oleh lebih sama harus perlu baru tambahkan tambah ubah ubahkan ganti hapus buatkan perbaiki benerin cek lihat kasih pakai pake add fix update change please thanks makasih tolong", S, " "); for (i in S) stop[S[i]] = 1 }
    length($0) >= 3 && !($0 in stop) && !seen[$0]++ { print; if (++n >= 12) exit }' | tr '\n' ' ')"
  hits=""
  if [ -n "${terms// /}" ]; then
    FILES=()
    while IFS= read -r f; do FILES+=("$f"); done < <(find "$MEM" -type f -name '*.md' ! -name index.md ! -name progress.md ! -name inbox.md ! -name README.md 2>/dev/null | sort)
    [ "${#FILES[@]}" -gt 0 ] && hits="$(LC_ALL=C awk -v terms="$terms" -v k="${PM_RECALL_MAX:-5}" -v root="$ROOT/" '
      BEGIN { nt = split(terms, T, " ") }
      FNR == 1 { inc = 0; gen = 0 }
      {
        line = $0
        # generated repo scan (topics/codebase.md): reference material, too noisy for prompt recall
        if (line ~ /^<!-- scan:start/) { gen = 1; next }
        if (gen) { if (line ~ /^<!-- scan:end/) gen = 0; next }
        if (line ~ /^[[:space:]]*<!--/) inc = 1
        if (inc) { if (line ~ /-->/) inc = 0; next }
        if (line ~ /^[[:space:]]*$/ || line ~ /^>/ || line ~ /^#+ [^0-9]/) next
        if (n > 0 && F[n] == FILENAME && (line ~ /^[[:space:]]+(Do instead|Why|Rejected|Revisit if):/ || line ~ /^(Why|Rejected|Revisit if):/)) { sub(/^[[:space:]]+/, "", line); U[n] = U[n] " ↳ " line; next }
        n++; U[n] = line; F[n] = FILENAME; L[n] = FNR
      }
      END {
        for (i = 1; i <= n; i++) { low = tolower(U[i]); for (t = 1; t <= nt; t++) if (low ~ ("(^|[^a-z0-9])" T[t])) { M[i, t] = 1; DF[t]++ } }
        need = (nt >= 2) ? 2 : 1
        for (i = 1; i <= n; i++) {
          s = 0; c = 0; tag = 0; low = tolower(U[i])
          for (t = 1; t <= nt; t++) if ((i, t) in M) { s += log(1 + n / DF[t]); c++; if (index(low, "#" T[t]) || index(low, "/" T[t])) { s += 1; tag = 1 } }
          # accept: enough distinct terms, or a tag hit, or one specific term (≥5 chars, rare in memory)
          rare = 0; for (t = 1; t <= nt; t++) if ((i, t) in M && length(T[t]) >= 5 && DF[t] <= 2) rare = 1
          if (c >= need || (c >= 1 && (tag || rare))) S[i] = s
        }
        for (r = 1; r <= k; r++) {
          best = 0; bi = 0
          for (i in S) if (S[i] > best) { best = S[i]; bi = i }
          if (!bi) break
          f = F[bi]; if (index(f, root) == 1) f = substr(f, length(root) + 1)
          print f ":" L[bi] ": " U[bi]; delete S[bi]
        }
      }' "${FILES[@]}")"
  fi
  new="$(printf '%s\n' "$hits" | inject_new)"
  # unconfirmed agent entries are leads, not facts
  printf '%s' "$new" | grep -qE '\((user|agent)[^()]*unconfirmed[[:space:]]*\)' && new="$new
(Entries marked \"unconfirmed\" are an agent's unverified conclusion: check them against the code before relying on them; confirm, fix or remove them.)"
  [ -n "$new" ] && ctx="${ctx:+$ctx
}[project-memory] Memory entries that may be relevant to this request:
$new"
  [ -n "$ctx" ] || emit_empty
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$(json_escape "$(cap "$ctx" 4000)")"
  ;;
# ---------------------------------------------------------------------------
pre-edit)
  # edited paths → relative to ROOT. Absolute paths may use the logical or physical (/private/…) root;
  # relative ones (Codex apply_patch) are relative to the session cwd.
  ROOT_P="$(cd "$ROOT" && pwd -P)"; CWD_P="$(cd "$CWD" && pwd -P)"; CWD_REL="${CWD_P#"$ROOT_P"}"; CWD_REL="${CWD_REL#/}"
  rel_path() {   # (kept out of $(…): bash 3.2 cannot parse `case` patterns inside command substitution)
    local p="$1"
    case "$p" in
      "$ROOT"/*) p="${p#"$ROOT"/}" ;;
      "$ROOT_P"/*) p="${p#"$ROOT_P"/}" ;;
      /*) ;;
      *) p="${p#./}"; [ -n "$CWD_REL" ] && p="$CWD_REL/$p" ;;
    esac
    printf '%s\n' "$p"
  }
  paths="$(
    { printf '%s' "$INPUT_1L" | grep -oE '"(file_path|path|notebook_path)"[[:space:]]*:[[:space:]]*"[^"]+"' | sed 's/.*:[[:space:]]*"\(.*\)"/\1/'
      printf '%s' "$INPUT" | grep -oE '\*\*\* ((Update|Add|Delete) File|Move to): [^"\\]+' | sed 's/^\*\*\* [A-Za-z ]*: //'
    } | while IFS= read -r p; do rel_path "$p"; done | sort -u )"
  [ -n "$paths" ] || emit_empty
  all_hits="$(
    find "$MEM" -type f -name '*.md' ! -name inbox.md ! -name README.md 2>/dev/null | while IFS= read -r f; do
      PATHS="$paths" LC_ALL=C awk -v rel="${f#"$ROOT"/}" '
        BEGIN { n = split(ENVIRON["PATHS"], P, "\n"); tagre = ENVIRON["PM_TAG_RE"] }
        /^<!-- scan:start/ { gen = 1; next } gen { if (/^<!-- scan:end/) gen = 0; next }   # generated scan: no @path tags
        { line = $0
          while (match(line, tagre)) {
            tag = substr(line, RSTART, RLENGTH); sub(/^[ \t(]*@/, "", tag); sub(/[.,;:]+$/, "", tag)
            while (tag ~ /\)$/ && gsub(/\(/, "(", tag) < gsub(/\)/, ")", tag)) { tag = substr(tag, 1, length(tag) - 1); sub(/[.,;:]+$/, "", tag) }
            line = substr(line, RSTART + RLENGTH); t = tag; sub(/\/$/, "", t)
            for (i = 1; i <= n; i++) if (P[i] == t || index(P[i], t "/") == 1) { print rel ":" FNR ": " $0; next }
          } }' "$f"
    done )"
  [ -n "$all_hits" ] || emit_empty
  # #hold entries first so they are never cut off by the display limit
  hits="$( { printf '%s\n' "$all_hits" | grep '#hold'; printf '%s\n' "$all_hits" | grep -v '#hold'; } | head -n 15 )"
  new="$(printf '%s\n' "$hits" | inject_new)"
  # unconfirmed agent entries are leads, not facts
  printf '%s' "$new" | grep -qE '\((user|agent)[^()]*unconfirmed[[:space:]]*\)' && new="$new
(Entries marked \"unconfirmed\" are an agent's unverified conclusion: check them against the code before relying on them; confirm, fix or remove them.)"
  # the #hold gate applies on EVERY edit, unless the user approved each held path recently (mem.sh approve)
  holds_all="$(printf '%s\n' "$all_hits" | grep '#hold')"
  holds="$(printf '%s\n' "$holds_all" | head -n 3)"
  if [ -n "$holds" ] && [ -f "$MEM/.approvals" ]; then
    now="$(date +%s)"
    approved="$(PATHS="$paths" HOLDS="$holds_all" LC_ALL=C awk -F'\t' -v now="$now" '
      BEGIN { n = split(ENVIRON["PATHS"], P, "\n"); nh = split(ENVIRON["HOLDS"], H, "\n"); tagre = ENVIRON["PM_TAG_RE"]
        for (h = 1; h <= nh; h++) { line = H[h]
          while (match(line, tagre)) {
            t = substr(line, RSTART, RLENGTH); sub(/^[ \t(]*@/, "", t); sub(/[.,;:]+$/, "", t)
            while (t ~ /\)$/ && gsub(/\(/, "(", t) < gsub(/\)/, ")", t)) { t = substr(t, 1, length(t) - 1); sub(/[.,;:]+$/, "", t) }
            sub(/\/$/, "", t)
            line = substr(line, RSTART + RLENGTH)
            for (i = 1; i <= n; i++) if (P[i] == t || index(P[i], t "/") == 1) held[i] = 1 } } }
      $1 + 0 > now { t = $2; sub(/\/$/, "", t); for (i = 1; i <= n; i++) if (P[i] == t || index(P[i], t "/") == 1) ok[i] = 1 }
      END { for (i = 1; i <= n; i++) if (held[i] && !ok[i]) { print "no"; exit } print "yes" }' "$MEM/.approvals")"
    [ "$approved" = "yes" ] && holds=""
  fi
  [ -n "$new" ] || [ -n "$holds" ] || emit_empty
  ctx="[project-memory] Memory entries tagged for the file(s) you are about to edit:
${new:-$holds}"
  if [ -n "$holds" ]; then
    if [ "$AGENT" = "codex" ]; then
      # Codex does not support permissionDecision "ask": deny with instructions instead
      reason="[project-memory] Blocked: this area is marked #hold in project memory: $holds
Do not retry yet. Ask the user for explicit permission to edit it. Only if the user clearly approves in chat, run: bash .agents/skills/project-memory/scripts/mem.sh approve <path> (valid 60 minutes), then retry. Never approve on your own."
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
        "$(json_escape "$(cap "$reason" 1500)")"
    else
      reason="This area is marked #hold in project memory: $holds"
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s","additionalContext":"%s"}}\n' \
        "$(json_escape "$(cap "$reason" 600)")" "$(json_escape "$(cap "$ctx" 3000)")"
    fi
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$(json_escape "$(cap "$ctx" 3000)")"
  fi
  ;;
# ---------------------------------------------------------------------------
stop)
  printf '%s' "$INPUT_1L" | grep -qE '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && emit_empty
  [ -f "$STATE/start" ] || { touch "$STATE/start"; emit_empty; }
  nudges="$(cat "$STATE/nudges" 2>/dev/null || echo 0)"
  [ "$nudges" -ge "${PM_MAX_NUDGES:-3}" ] && emit_empty
  ref="$STATE/start"; [ -f "$STATE/nudged" ] && ref="$STATE/nudged"
  lastmem=""
  while IFS= read -r f; do
    if [ -z "$lastmem" ] || [ "$f" -nt "$lastmem" ]; then lastmem="$f"; fi
  done < <(find "$MEM" -type f -name '*.md' ! -name inbox.md -newer "$ref" 2>/dev/null)
  [ -n "$lastmem" ] && ref="$lastmem"
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    # tracked + untracked files git cares about (respects .gitignore), changed after ref
    changed="$(git -C "$ROOT" status --porcelain --untracked-files=all 2>/dev/null | cut -c4- | sed 's/.* -> //; s/^"//; s/"$//' |
      grep -vE '^(\.memory|\.agents|\.claude|\.codex|\.omp)/' | while IFS= read -r f; do
        [ -f "$ROOT/$f" ] && [ "$ROOT/$f" -nt "$ref" ] && printf '%s\n' "$f"; done | head -n 50)"
  else
    changed="$(find "$ROOT" \( "${PRUNE[@]}" \) -prune -o -type f -newer "$ref" -print 2>/dev/null | head -n 50)"
  fi
  [ -n "$changed" ] || emit_empty
  count="$(printf '%s\n' "$changed" | wc -l | tr -d ' ')"
  touch "$STATE/nudged"; echo $((nudges + 1)) > "$STATE/nudges"
  reason="[project-memory] ${count} file(s) changed since .memory/ was last updated. Before stopping: if this work produced a decision, a user correction, a gotcha or a reusable procedure, record it in .memory/ following the project-memory skill, and update .memory/progress.md. If nothing is worth recording, do not edit anything; just end your reply with: memory: nothing new."
  [ "$MODE" = confirm ] && reason="[project-memory] ${count} file(s) changed since .memory/ was last updated. Confirm mode: record the user's own corrections and instructions now if they are not in memory yet. If this work produced a decision, a gotcha, a reusable procedure or progress of your own worth keeping, do NOT write it yet. End your reply with a numbered memory proposal (target file + the exact entry) and ask the user which to save; save unanswered proposals as one line each in .memory/inbox.md. If nothing is worth recording, end your reply with: memory: nothing new."
  printf '{"decision":"block","reason":"%s"}\n' "$(json_escape "$reason")"
  ;;
*) emit_empty ;;
esac
exit 0
