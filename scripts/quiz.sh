#!/usr/bin/env bash
# team-memory quiz — run through `mem.sh quiz`, which passes the project root.
#   bash quiz.sh <root> [-n N] [--md] [--since Nd] [@path]
# Asks N questions (default 5) from decisions.md, gotchas.md, the index.md Rules and topics/glossary.md, with the answer
# and the line it comes from. A question shows the decision or problem and asks for the reason, the
# fix or the rule, so the answer is never in the question. Entries you knew come up less often,
# entries you missed more; "unclear" marks wording to rewrite. Results stay on this machine
# (~/.cache/team-memory/quiz/). With --md, or when not run in a terminal: Markdown with the answers
# in <details>, for an onboarding page or for an agent quizzing the user.
set -u
export LC_ALL=C
ROOT="$1"; shift
cd "$ROOT" || exit 1
N=5; MD=""; SINCE=""; AT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -n) N="${2:-5}"; shift ;;
    -n*) N="${1#-n}" ;;
    --md) MD=1 ;;
    --since) SINCE="${2:-}"; shift ;;
    --since=*) SINCE="${1#--since=}" ;;
    @*) AT="${1#@}" ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "mem.sh quiz: unknown option $1 (see mem.sh quiz --help)" >&2; exit 2 ;;
  esac; shift
done
case "$N" in ''|*[!0-9]*) N=5 ;; esac
SINCE="${SINCE%d}"; case "$SINCE" in *[!0-9]*) SINCE="" ;; esac
[ -t 0 ] && [ -t 1 ] || MD=1
TODAY="$(date +%Y-%m-%d)"
HIST_DIR="${PM_UPDATE_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/team-memory}/quiz"
HIST="$HIST_DIR/$(printf '%s' "$(pwd -P)" | cksum | cut -d' ' -f1).tsv"   # date <TAB> y|n|u <TAB> entry hash

FILES=""; for f in .memory/decisions.md .memory/gotchas.md .memory/index.md .memory/topics/glossary.md; do [ -f "$f" ] && FILES="$FILES $f"; done
[ -n "$FILES" ] || { echo "No .memory/decisions.md, gotchas.md or index.md here: nothing to ask yet."; exit 0; }

# One record per question: score, file:line, kind, topic, question, answer, source, hash (\037 = line break)
POOL="$(awk -v today="$TODAY" -v since="$SINCE" -v at="$AT" -v hist="$HIST" -v seed="$$" '
  function trim(t) { sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t); return t }
  function dn(s,  y, m, d) { y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0; if (m < 3) { y--; m += 12 }
    return 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + d }
  function h(t,  i, x) { x = 0; for (i = 1; i <= length(t) && i <= 80; i++) x = (x * 31 + index(" abcdefghijklmnopqrstuvwxyz0123456789", substr(tolower(t), i, 1))) % 1000000007; return x }
  BEGIN { srand(seed); FS = "\t"
    while ((getline l < hist) > 0) { split(l, H, "\t"); if (dn(today) - dn(H[1]) <= 60) last[H[3]] = H[2] }
    close(hist); FS = " " }
  function flush(   t, src, date, tags, paths, hold, x, what, why, q, a, topic, kind, sc, p, ok, i, n, P) {
    if (txt == "") return
    t = txt; txt = ""
    if (t ~ /~~/ || t ~ /superseded/) return
    src = ""; if (match(t, /\((user|agent)[^()]*\)[ \t]*$/)) { src = substr(t, RSTART + 1, RLENGTH - 2); sub(/\)[ \t]*$/, "", src); t = substr(t, 1, RSTART - 1) }
    date = ""; if (match(t, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) date = substr(t, RSTART, 10)
    if (date == "" && match(src, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) date = substr(src, RSTART, 10)
    hold = (t ~ /#hold/)
    tags = ""; paths = ""; x = t
    while (match(x, /(^|[ \t(])[#@][^ \t,;)]+/)) {
      w = trim(substr(x, RSTART, RLENGTH)); sub(/^\(/, "", w); x = substr(x, RSTART + RLENGTH); sub(/[.:]+$/, "", w)
      if (w ~ /^@/) paths = paths (paths != "" ? ", " : "") "`" substr(w, 2) "`"
      else if (w != "#hold") tags = tags (tags != "" ? ", " : "") substr(w, 2) }
    gsub(/(^|[ \t(])[#@][^ \t,;)]+/, "", t)
    sub(/^\*\*\[[0-9-]+\][ \t]*/, "", t); sub(/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ \t]*(·|-|—|:)?[ \t]*/, "", t)
    term = ""; if (k == "term" && match(t, /^\*\*[^*]+\*\*/)) { term = substr(t, 3, RLENGTH - 4); t = substr(t, RLENGTH + 1); sub(/^[ \t]*(—|–|-|:)[ \t]*/, "", t) }
    gsub(/\*\*/, "", t); t = trim(t); sub(/[ \t]*[.;,]$/, "", t)
    if (t == "" || t ~ /^Memory (language|writes):/) return
    if (since != "" && (date == "" || dn(today) - dn(date) > since + 0)) return
    if (at != "") { ok = 0; n = split(paths, P, /, /)
      for (i = 1; i <= n; i++) { p = P[i]; gsub(/`/, "", p); sub(/\/$/, "", p); a2 = at; sub(/\/$/, "", a2)
        if (index(p "/", a2 "/") == 1 || index(a2 "/", p "/") == 1) ok = 1 }
      if (!ok) return }
    topic = paths; if (tags != "") topic = topic (topic != "" ? " · " : "") tags
    about = paths; if (tags != "") about = (about != "" ? about " (" tags ")" : tags)
    why = ""; what = t
    if (body ~ /(^|\037)Why:/) { why = body; sub(/^.*(^|\037)Why:[ \t]*/, "", why) ; if (k == "gotcha") why = body }
    else if (match(t, /(,|;)? (because|since|so that|karena|sebab|agar|supaya) /)) { what = substr(t, 1, RSTART - 1); why = substr(t, RSTART + RLENGTH) }
    kind = k; sc = 1 + rand() * 2
    if (k == "term") { if (term == "" || t == "") return; q = "What does \"" term "\" mean in this project?"; a = t; topic = ""; sc += 1 }
    else if (hold) { kind = "hold"; q = "What must not be changed without asking first" (paths != "" ? " in " paths : "") ", and why?"; a = t (body != "" ? "\037" body : ""); sc += 3 }
    else if (k == "gotcha" && body != "") { q = "Gotcha" (sec != "" ? " (" sec ")" : "") ": " t ".\037Why does it happen, and what do you do instead?"; a = body }
    else if (why != "" && what != "") { q = (k == "rule" ? "Rule" : "Decided") ": " what ".\037Why?"; a = why }
    else if (topic != "") { q = (k == "rule" ? "What is the rule about " : k == "gotcha" ? "What goes wrong with " : "What was decided about ") about "?"; a = t (body != "" ? "\037" body : "") }
    else return
    if (src ~ /^user/) sc += 2; if (k == "gotcha") sc += 1; if (src ~ /unconfirmed/) sc -= 1
    hk = h(t); if (last[hk] == "y") sc -= 4; else if (last[hk] == "n") sc += 2; else if (last[hk] == "u") sc += 1
    gsub(/\t/, " ", q); gsub(/\t/, " ", a); a = toupper(substr(a, 1, 1)) substr(a, 2)
    if (src ~ /unconfirmed/) a = a "\037(The agent wrote this and nobody has confirmed it yet.)"
    fn = ef; sub(/^\.memory\//, "", fn)   # tabs separate the fields; "-" stands for none (read would merge empty ones)
    printf "%.3f\t%s:%d\t%s\t%s\t%s\t%s\t%s\t%s\n", sc, fn, line, kind, (topic != "" ? topic : "-"), q, a, (src != "" ? src : "no source"), hk }
  FNR == 1 { flush(); body = ""; sec = ""; rules = 0; code = 0; inc = 0; base = FILENAME; sub(/.*\//, "", base) }
  /^[ \t]*(```|~~~)/ { code = !code; next } code { next }
  /^[ \t]*<!--/ { inc = !/-->/; next } inc { if (/-->/) inc = 0; next }
  /^>/ { next }
  /^#{1,2} / { flush(); sec = $0; sub(/^#+ /, "", sec); rules = (base == "index.md" && sec ~ /^Rules/); next }
  base == "decisions.md" && /^- / { flush(); k = "decision"; txt = substr($0, 3); body = ""; line = FNR; ef = FILENAME; blk = 0; next }
  base == "decisions.md" && /^### / { flush(); k = "decision"; txt = substr($0, 5); body = ""; line = FNR; ef = FILENAME; blk = 1; next }
  base == "gotchas.md" && /^[0-9]+\. / { flush(); k = "gotcha"; txt = $0; sub(/^[0-9]+\. /, "", txt); body = ""; line = FNR; ef = FILENAME; blk = 0; next }
  base == "glossary.md" && /^- \*\*/ { flush(); k = "term"; txt = substr($0, 3); body = ""; line = FNR; ef = FILENAME; blk = 0; next }
  rules && /^- / { flush(); k = "rule"; txt = substr($0, 3); body = ""; line = FNR; ef = FILENAME; blk = 0; next }
  txt != "" && /[^ \t]/ && (blk || /^[ \t]+/) { body = body (body != "" ? "\037" : "") trim($0); next }
  txt != "" && !blk && /^[ \t]*$/ { flush() }
  END { flush() }' $FILES 2>/dev/null | sort -t"$(printf '\t')" -k1,1nr | head -n "$N")"

if [ -z "$POOL" ]; then
  echo "No entries to ask about${AT:+ under @$AT}${SINCE:+ from the last $SINCE days}: decisions, gotchas and Rules need a reason, a fix or an @path/#tag to make a question."
  exit 0
fi
total="$(printf '%s\n' "$POOL" | grep -c .)"; qs=questions; [ "$total" = 1 ] && qs=question
nl() { printf '%s' "$1" | tr '\037' '\n'; }

if [ -n "$MD" ]; then
  echo "# Project quiz — $(basename "$(pwd -P)")"
  echo
  echo "> $total $qs from \`.memory/\` ($TODAY). Answer first, then open the answer. A question you got"
  echo "> wrong because the entry is unclear means the entry needs rewriting, not you."
  i=0
  printf '%s\n' "$POOL" | while IFS="$(printf '\t')" read -r sc loc kind topic q a src hk; do
    i=$((i + 1)); [ "$topic" = - ] && topic=""
    echo; echo "### $i. $kind${topic:+ · $topic}"; echo
    nl "$q" | sed 's/^/> /'; echo; echo
    echo "<details><summary>Answer</summary>"; echo
    nl "$a"; echo; echo
    echo "Source: \`.memory/$loc\` ($src)"; echo
    echo "</details>"
  done
  exit 0
fi

echo "team-memory quiz — $total $qs from .memory/ (Enter shows the answer)"
i=0; good=0; MISSED=""; UNCLEAR=""
mkdir -p "$HIST_DIR" 2>/dev/null
while IFS="$(printf '\t')" read -r sc loc kind topic q a src hk <&3; do
  i=$((i + 1)); [ "$topic" = - ] && topic=""
  echo; printf '%s/%s  %s%s\n' "$i" "$total" "$kind" "${topic:+ · $topic}"
  nl "$q" | sed 's/^/     /'; echo
  printf '     [Enter] '; read -r _ || break
  nl "$a" | sed '1s/^/     → /; 2,$s/^/       /'; echo
  printf '       source: .memory/%s (%s)\n' "$loc" "$src"
  ans=""
  while :; do
    printf '     Did you know it? [y]es / [n]o / [u]nclear wording: '; read -r ans || break
    case "$ans" in [yYnNuU]*) break ;; esac
  done
  case "$ans" in
    [yY]*) good=$((good + 1)); r=y ;;
    [uU]*) UNCLEAR="$UNCLEAR .memory/$loc"; r=u ;;
    *) MISSED="$MISSED .memory/$loc"; r=n ;;
  esac
  printf '%s\t%s\t%s\n' "$TODAY" "$r" "$hk" >> "$HIST" 2>/dev/null
done 3<<EOF
$POOL
EOF
echo
echo "Score: $good/$i"
[ -n "$MISSED" ] && echo "Read again before working there:$MISSED"
[ -n "$UNCLEAR" ] && echo "Unclear wording:$UNCLEAR → rewrite them (short sentences, the reason in Why:), or ask your agent to"
[ "$good" = "$i" ] && [ "$i" -gt 0 ] && echo "All known. The next quiz picks other entries first."
exit 0
