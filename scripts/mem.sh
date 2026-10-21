#!/usr/bin/env bash
# project-memory helper (v3) — pure bash/awk.
#   mem.sh search <words…>      ranked search across .memory/ and user memory
#   mem.sh path <file-or-dir>   entries tagged @path that apply to it
#   mem.sh lint                 size, caps, secrets, map, missing @paths, stale & duplicate entries, filler wording
#   mem.sh secrets [--staged]   secret scan only (exit 1 if found); --staged = what git would commit
#   mem.sh stats                entry counts per file + injection hits
#   mem.sh approve <path> [min]  allow edits in a #hold area for N minutes (default 60) — only after the user approves
#   mem.sh scan [--print]       index the repo into .memory/topics/codebase.md (+ Map, empty Key facts);
#                               in a project without .memory/, creates it here from the templates first
# Env: PM_STALE_DAYS (default 120), PM_SCAN_STALE (commits, default 150), PM_USER_MEMORY (default ~/.agents/memory/user.md)
set -u
export LC_ALL=C   # byte semantics: memory files with odd encodings never crash awk; same cut/sort as the hooks
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIG="$(pwd)"; ROOT="$ORIG"
while [ "$ROOT" != "/" ] && [ ! -d "$ROOT/.memory" ]; do ROOT="$(dirname "$ROOT")"; done
if [ ! -d "$ROOT/.memory" ]; then
  case "${1:-}" in
    secrets) exit 0 ;;   # nothing to scan (e.g. pre-commit after .memory/ was removed)
    scan) ROOT="$ORIG"
      if [ "$ROOT" = "/" ] || [ "$(cd "$ROOT" && pwd -P)" = "$(cd "$HOME" 2>/dev/null && pwd -P)" ]; then
        echo "Refusing to create .memory/ in $ROOT — run mem.sh scan from the project root." >&2; exit 1
      fi
      [ "${2:-}" = "--print" ] || { cp -R "$HERE/../assets/templates" "$ROOT/.memory" && echo "+ $ROOT/.memory/ (from templates)"; } ;;
    *) echo "No .memory/ found in this or any parent directory. New project? Run: mem.sh scan" >&2; exit 1 ;;
  esac
fi
cd "$ROOT" || exit 1
USER_MEM="${PM_USER_MEMORY:-$HOME/.agents/memory/user.md}"
STALE_DAYS="${PM_STALE_DAYS:-120}"
SECRET_RE='(eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{10,}|sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY|[Bb]earer [A-Za-z0-9._-]{20,}|(password|passwd|secret|api[_-]?key|token)[[:space:]]*[:=][[:space:]]*[^[:space:]<>\[]{8,}|([Tt]oken|TOKEN|[Bb]earer|[Kk]ey|KEY|[Ss]ecret|[Aa]uth[A-Za-z]*)[^[:alnum:]]{1,6}[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'

mem_files() { find .memory -type f -name '*.md' ! -name inbox.md 2>/dev/null | sort; }
FILES=(); while IFS= read -r f; do FILES+=("$f"); done < <(mem_files)
hash() { printf '%s' "$1" | cksum | cut -d' ' -f1; }
# path argument (relative to where the user ran mem.sh, or absolute) → path relative to the repo root
relpath() {
  local a="$1" slash="" rp
  case "$a" in /*) ;; *) a="$ORIG/$a" ;; esac
  case "$a" in */) slash=/ ;; esac
  a="$(printf '%s\n' "$a" | awk -F/ '{ n = 0
    for (i = 1; i <= NF; i++) { if ($i == "" || $i == ".") continue; if ($i == "..") { if (n) n--; continue }; s[++n] = $i }
    o = ""; for (i = 1; i <= n; i++) o = o "/" s[i]; print (o == "" ? "/" : o) }')$slash"
  if [ -d "$a" ]; then a="$(cd "$a" && pwd)/"
  elif [ -d "$(dirname "$a")" ]; then a="$(cd "$(dirname "$a")" && pwd)/$(basename "$a")"; fi
  rp="$(pwd -P)"   # cwd is ROOT here; also accept paths given through the physical root (/private/var/…)
  case "$a" in "$ROOT"/*) a="${a#"$ROOT"/}" ;; "$rp"/*) a="${a#"$rp"/}" ;; esac
  printf '%s' "$a"
}
# @path tag: letters, digits, _ . / - and the ( ) [ ] used by route folders such as app/[id]/ or app/(auth)/
export PM_TAG_RE='(^|[ 	(])@[A-Za-z0-9_.]([A-Za-z0-9_./()-]|\[|\])*'

cmd="${1:-help}"; shift || true
case "$cmd" in
search)
  [ $# -gt 0 ] || { echo "usage: mem.sh search <words…>"; exit 1; }
  S=(${FILES[@]+"${FILES[@]}"}); [ -f "$USER_MEM" ] && S+=("$USER_MEM")
  awk -v q="$*" -v home="$HOME" '
    BEGIN { n = split(tolower(q), W, /[^a-z0-9#@\/._-]+/) }
    FNR == 1 { inc = 0 }
    /^[[:space:]]*<!--/ { inc = 1 } inc { if (/-->/) inc = 0; next }
    /^[[:space:]]*$/ || /^>/ { next }
    { l = tolower($0); s = 0
      for (i = 1; i <= n; i++) if (W[i] != "" && index(l, W[i])) s++
      f = FILENAME; if (index(f, home) == 1) f = "~" substr(f, length(home) + 1)
      if (s) printf "%d\t%s:%d: %s\n", s, f, FNR, $0 }' ${S[@]+"${S[@]}"} /dev/null \
  | sort -t"$(printf '\t')" -k1,1nr -s | head -n "${PM_SEARCH_LIMIT:-25}" | cut -f2-
  ;;
path)
  [ $# -gt 0 ] || { echo "usage: mem.sh path <file-or-dir>"; exit 1; }
  p="$(relpath "$1")"; p="${p%/}"
  awk -v p="$p" '
    BEGIN { tagre = ENVIRON["PM_TAG_RE"] }
    FNR == 1 { gen = 0 }
    /^<!-- scan:start/ { gen = 1; next } gen { if (/^<!-- scan:end/) gen = 0; next }   # generated scan: no @path tags
    { line = $0
      while (match(line, tagre)) {
        tag = substr(line, RSTART, RLENGTH); sub(/^[ \t(]*@/, "", tag); sub(/[.,;:]+$/, "", tag)
        while (tag ~ /\)$/ && gsub(/\(/, "(", tag) < gsub(/\)/, ")", tag)) { tag = substr(tag, 1, length(tag) - 1); sub(/[.,;:]+$/, "", tag) }
        sub(/\/$/, "", tag)
        line = substr(line, RSTART + RLENGTH)
        if (p == tag || index(p, tag "/") == 1 || index(tag, p "/") == 1) { print FILENAME ":" FNR ": " $0; next }
      } }' ${FILES[@]+"${FILES[@]}"} /dev/null
  ;;
secrets)
  found=""
  if [ "${1:-}" = "--staged" ]; then
    while IFS= read -r -d '' f; do
      case "$f" in .memory/local.md|*/.memory/local.md) continue ;; esac
      r="$(git show ":$f" 2>/dev/null | grep -nE "$SECRET_RE" | F="$f" awk '{ print ENVIRON["F"] ":" $0 }')"
      [ -n "$r" ] && found="$found$r"$'\n'
    done < <(git -c core.quotePath=false diff --cached --name-only -z --diff-filter=ACM -- .memory 2>/dev/null)
  else
    found="$(grep -rnE "$SECRET_RE" .memory 2>/dev/null | grep -vE '^\.memory/(local|inbox)\.md:')"
  fi
  if [ -n "${found//$'\n'/}" ]; then
    echo "✗ project-memory: possible secrets in memory files — remove them (and rotate the credential):"
    printf '%s\n' "$found" | sed '/^$/d' | cut -c1-160 | head -n 20
    echo "  (false positive? reword the entry; to bypass once: git commit --no-verify)"
    exit 1
  fi
  ;;
lint)
  issues=0; w() { echo "⚠ $*"; issues=$((issues + 1)); }
  # sizes
  [ -f .memory/index.md ] && { n=$(wc -l < .memory/index.md); [ "$n" -gt 150 ] && w ".memory/index.md has $n lines (limit ~150) → consolidate"; }
  for f in ${FILES[@]+"${FILES[@]}"}; do case "$f" in .memory/index.md) continue;; esac
    n=$(wc -l < "$f"); [ "$n" -gt 300 ] && w "$f has $n lines (limit ~300) → move detail into topics/"; done
  # category caps
  if [ -f .memory/gotchas.md ]; then
    while IFS= read -r m; do w "$m"; done < <(awk '/^## /{sec=$0; c=0} /^(- |[0-9]+\. )/{c++; if(c==11) print ".memory/gotchas.md: \"" sec "\" has more than 10 entries → drop the least valuable"}' .memory/gotchas.md)
  fi
  # secrets
  out="$(bash "$0" secrets 2>&1)" || { echo "$out" | sed 's/^✗/⚠/'; issues=$((issues + 1)); }
  # map coverage
  if [ -f .memory/index.md ]; then
    while IFS= read -r f; do grep -qF "$f" .memory/index.md || w "$f is not listed in the Map section of index.md"
    done < <(find .memory/topics .memory/procedures -type f -name '*.md' 2>/dev/null | sed 's#^\.memory/##' | sort)
  fi
  # entries without a date
  while IFS= read -r m; do w "entry without date: $m"; done < <(grep -nE '^(- |[0-9]+\. )' .memory/decisions.md .memory/gotchas.md 2>/dev/null | grep -vE '[0-9]{4}-[0-9]{2}-[0-9]{2}|superseded' | head -n 10)
  # @paths that no longer exist (renamed/deleted code → memory may be wrong)
  while IFS=$'\t' read -r loc tag; do
    [ -e "$ROOT/${tag%/}" ] || w "$loc refers to @$tag, which no longer exists → update the path or retire the entry"
  done < <(awk 'BEGIN { tagre = ENVIRON["PM_TAG_RE"] }
      FNR == 1 { inc = 0; gen = 0 }
      /^<!-- scan:start/ { gen = 1; next } gen { if (/^<!-- scan:end/) gen = 0; next }
      /^[[:space:]]*<!--/ { inc = 1 } inc { if (/-->/) inc = 0; next }
      /^>/ { next }
      { line = $0
      while (match(line, tagre)) {
        tag = substr(line, RSTART, RLENGTH); sub(/^[ \t(]*@/, "", tag); sub(/[.,;:]+$/, "", tag)
        while (tag ~ /\)$/ && gsub(/\(/, "(", tag) < gsub(/\)/, ")", tag)) { tag = substr(tag, 1, length(tag) - 1); sub(/[.,;:]+$/, "", tag) }
        line = substr(line, RSTART + RLENGTH)
        if (tag ~ /\// || tag ~ /\.[a-z]+$/) print FILENAME ":" FNR "\t" tag } }' ${FILES[@]+"${FILES[@]}"} /dev/null 2>/dev/null | sort -u)
  # duplicates (e.g. after merge=union)
  while IFS= read -r m; do w "duplicate entry: $m"; done < <(awk '/^(- |[0-9]+\. )/ { k = $0; sub(/^[0-9]+\. /, "", k); sub(/^- /, "", k); if (seen[k]++) print FILENAME ":" FNR ": " substr($0, 1, 90) }' .memory/decisions.md .memory/gotchas.md 2>/dev/null)
  # filler / generated-sounding wording (see "Anti-slop" in SKILL.md); not in comments, quotes, code blocks or the scan block
  SLOP_RE="it'?s (important|worth) (to note|noting|mentioning)|it is (important|worth) (to note|noting|mentioning)|in order to|as mentioned (above|earlier|before)|in summary|in conclusion|basically|plays? an? (key|crucial|vital|pivotal|important) role|best practices|robust|seamless(ly)?|comprehensive|powerful|cutting-edge|state-of-the-art|game-chang(er|ing)|leverag(e|es|ed|ing)|utiliz(e|es|ed|ing|ation)|delv(e|es|ed|ing)|streamlin(e|es|ed|ing)|crucial|pivotal|holistic|various|great news|let me know|feel free|as an ai|successfully"
  while IFS= read -r m; do w "filler wording: $m → say concretely what it does or delete it"; done < <(SLOP_RE="$SLOP_RE" awk '
      BEGIN { re = "(^|[^a-z0-9_])(" ENVIRON["SLOP_RE"] ")([^a-z0-9_]|$)" }
      FNR == 1 { inc = 0; gen = 0; code = 0 }
      /^<!-- scan:start/ { gen = 1; next } gen { if (/^<!-- scan:end/) gen = 0; next }
      /^[[:space:]]*(```|~~~)/ { code = !code; next } code { next }
      /^[[:space:]]*<!--/ { inc = 1 } inc { if (/-->/) inc = 0; next }
      /^>/ { next }
      { l = tolower($0); gsub(/`[^`]*`/, "", l)
        ws = ""; while (match(l, re)) { wd = substr(l, RSTART, RLENGTH); gsub(/^[^a-z]+|[^a-z]+$/, "", wd)
          ws = ws (ws != "" ? ", " : "") "\"" wd "\""; l = substr(l, RSTART + RLENGTH - 1) }
        if (ws != "") print FILENAME ":" FNR ": " ws " in: " substr($0, 1, 70) }' ${FILES[@]+"${FILES[@]}"} /dev/null | head -n 10)
  # stale gotchas: older than PM_STALE_DAYS, seen ≤ 1, not #hold, never injected by hooks in that period
  today="$(date +%Y-%m-%d)"
  if [ -f .memory/gotchas.md ]; then
    while IFS=$'\t' read -r loc text; do
      h="$(hash "$(printf '%s' "$text" | cut -c1-60)")"
      if [ -f .memory/.stats.tsv ] && awk -F'\t' -v h="$h" -v t="$today" -v d="$STALE_DAYS" '
          function dn(s,  y,m,dd){ y=substr(s,1,4)+0; m=substr(s,6,2)+0; dd=substr(s,9,2)+0; if(m<3){y--;m+=12}; return 365*y+int(y/4)-int(y/100)+int(y/400)+int((153*(m-3)+2)/5)+dd }
          $2 == h && dn(t) - dn($1) <= d { found = 1 } END { exit !found }' .memory/.stats.tsv; then continue; fi
      w "stale? $loc (older than $STALE_DAYS days, seen once, not used by hooks since) → confirm, update or remove"
    done < <(awk -v t="$today" -v d="$STALE_DAYS" '
        function dn(s,  y,m,dd){ y=substr(s,1,4)+0; m=substr(s,6,2)+0; dd=substr(s,9,2)+0; if(m<3){y--;m+=12}; return 365*y+int(y/4)-int(y/100)+int(y/400)+int((153*(m-3)+2)/5)+dd }
        /^(- |[0-9]+\. )/ && !/#hold/ && match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) {
          dt = substr($0, RSTART, 10); seen = 1
          if (match($0, /seen: *[0-9]+/)) { s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); seen = s + 0 }
          if (seen <= 1 && dn(t) - dn(dt) > d) print FILENAME ":" FNR "\t" $0 }' .memory/gotchas.md)
  fi
  # repo scan out of date
  sc="$(sed -n 's/^<!-- scan:start.* at commit \([0-9a-f]*\);.*/\1/p' .memory/topics/codebase.md 2>/dev/null | head -n1)"
  if [ -n "$sc" ] && git rev-parse --git-dir >/dev/null 2>&1; then
    n="$(git rev-list --count "$sc..HEAD" 2>/dev/null || echo 0)"
    [ "$n" -gt "${PM_SCAN_STALE:-150}" ] && w ".memory/topics/codebase.md was scanned $n commits ago → run mem.sh scan"
  fi
  # inbox waiting
  [ -f .memory/inbox.md ] && { n=$(grep -c '^- ' .memory/inbox.md); [ "$n" -gt 0 ] && w ".memory/inbox.md has $n untriaged item(s)"; }
  # git hygiene
  if git rev-parse --git-dir >/dev/null 2>&1; then
    for f in .memory/local.md .memory/inbox.md .memory/.stats.tsv .memory/.approvals; do
      [ -e "$f" ] && ! git check-ignore -q "$f" && w "$f is NOT gitignored"; done
  fi
  [ "$issues" -eq 0 ] && echo "✓ memory lint: no issues" || echo "— $issues issue(s)"
  [ "$issues" -eq 0 ]
  ;;
approve)
  [ $# -gt 0 ] || { echo "usage: mem.sh approve <path> [minutes]"; exit 1; }
  p="$(relpath "$1")"; mins="${2:-60}"
  case "$mins" in ''|*[!0-9]*) echo "minutes must be a number"; exit 1;; esac
  printf '%s\t%s\n' "$(( $(date +%s) + mins * 60 ))" "$p" >> .memory/.approvals
  echo "✓ #hold lifted for '$p' for $mins minutes (this machine only)"
  ;;
scan)
  SECRET_RE="$SECRET_RE" bash "$HERE/scan.sh" "$ROOT" "${1:-}"
  ;;
stats)
  for f in ${FILES[@]+"${FILES[@]}"}; do
    printf '%5s lines  %4s entries  %s\n' "$(wc -l < "$f" | tr -d ' ')" "$(grep -cE '^(- |[0-9]+\. |### )' "$f")" "$f"; done
  [ -f .memory/.stats.tsv ] && echo "hook injections recorded: $(wc -l < .memory/.stats.tsv | tr -d ' ') (last: $(tail -n1 .memory/.stats.tsv | cut -f1))"
  [ -f "$USER_MEM" ] && echo "user memory: $USER_MEM ($(wc -l < "$USER_MEM" | tr -d ' ') lines)"
  ;;
*) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
