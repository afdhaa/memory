#!/usr/bin/env bash
# team-memory gaps — run through `mem.sh gaps`, which passes the project root.
#   bash gaps.sh <root> [--days 90] [-n 10]
# The folders changed most in the last N days (git log), next to how many memory entries point at
# them (@path tags and `path` mentions). A busy folder with no entries is knowledge that lives only
# in people's heads: ask the team about it, or have the agent read it and propose entries.
set -u
export LC_ALL=C
ROOT="$1"; shift
cd "$ROOT" || exit 1
DAYS=90; N=10
while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS="${2:-90}"; shift ;;
    --days=*) DAYS="${1#--days=}" ;;
    -n) N="${2:-10}"; shift ;;
    -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "mem.sh gaps: unknown option $1 (see mem.sh gaps --help)" >&2; exit 2 ;;
  esac; shift
done
DAYS="${DAYS%d}"; case "$DAYS" in ''|*[!0-9]*) DAYS=90 ;; esac
case "$N" in ''|*[!0-9]*) N=10 ;; esac
git rev-parse --git-dir >/dev/null 2>&1 || { echo "mem.sh gaps needs a git repository (it reads git log)."; exit 1; }

# folder <TAB> commits <TAB> authors, busiest first. A folder is two levels deep (src/billing,
# docs/guide); in a monorepo, two levels inside the package (packages/vite/src/node).
# lockfiles, generated memory and translations say nothing about where knowledge is missing
CHURN="$(git log --since="$DAYS days ago" --no-merges --name-only --format='@%ae' -- . 2>/dev/null | awk '
  /^@/ { who = substr($0, 2); c++; bot = (who ~ /\[bot\]|renovate|dependabot|github-actions|greenkeeper/); next }   # dependency bumps are not where knowledge is
  bot { next }
  NF == 0 { next }
  /^\.memory\// || /(^|\/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|poetry\.lock|uv\.lock|Gemfile\.lock|composer\.lock|go\.sum|CHANGELOG\.md)$/ || /(^|\/)(locales?|i18n|translations)\// { next }
  { n = split($0, P, "/"); if (n < 2) next
    b = 0; if (n >= 4 && P[1] ~ /^(packages|apps|libs|services|crates|modules|plugins|projects)$/) b = 2
    d = P[1]; for (i = 2; i <= b + 2 && i < n; i++) d = d "/" P[i]
    if (!((c, d) in seen)) { seen[c, d] = 1; commits[d]++ }
    if (!((d, who) in au)) { au[d, who] = 1; authors[d]++ } }
  END { for (d in commits) print d "\t" commits[d] "\t" authors[d] }' | sort -t"$(printf '\t')" -k2,2nr -k1,1 | head -n 60)"
total="$(git log --no-merges --since="$DAYS days ago" --format=%ae 2>/dev/null | grep -cvE '\[bot\]|renovate|dependabot|github-actions|greenkeeper')"
if [ -z "$CHURN" ] || [ "$total" -lt 5 ]; then
  echo "Only $total commit(s) in the last $DAYS days${CHURN:+ (a shallow clone?)}: too little history to see where work happens. Try --days 365."
  exit 0
fi

# paths memory points at: @tags and `backticked/paths`, from every memory file except the generated scan
# (topics/codebase.md is left out: as the overview of the whole repo it names every folder)
MF="$(find -H .memory -type f -name '*.md' ! -name README.md ! -name inbox.md ! -name progress.md ! -path '*/topics/codebase.md' 2>/dev/null | sort | tr '\n' ' ')"
REFS="$(awk '
  FNR == 1 { gen = 0; inc = 0 }
  /^<!-- scan:start/ { gen = 1; next } gen { if (/^<!-- scan:end/) gen = 0; next }
  /^[ \t]*<!--/ { inc = !/-->/; next } inc { if (/-->/) inc = 0; next }
  /^>/ { next }
  { line = $0
    while (match(line, /(^|[ \t(])@[A-Za-z0-9_.][^ \t,;)]*|`[A-Za-z0-9_.][^` ]*\/[^` ]*`/)) {
      p = substr(line, RSTART, RLENGTH); line = substr(line, RSTART + RLENGTH)
      gsub(/^[ \t(]*@|`/, "", p); sub(/[.,;:]+$/, "", p); sub(/\*.*/, "", p); sub(/\/+$/, "", p)
      if (p != "" && p !~ /^(https?:|www\.)/) print FILENAME "\t" p } }' $MF /dev/null 2>/dev/null)"

printf '%s\n' "$CHURN" | REFS="$REFS" awk -F'\t' -v days="$DAYS" -v total="$total" -v max="$N" '
  BEGIN { n = split(ENVIRON["REFS"], R, "\n"); for (i = 1; i <= n; i++) { split(R[i], F, "\t"); rf[i] = F[1]; rp[i] = F[2] } }
  { d = $1; e = 0; k = ""
    for (i = 1; i <= n; i++) if (rp[i] != "" && index(rp[i] "/", d "/") == 1) {   # the folder or something in it; a broad @packages/ says nothing specific
      e++; f = rf[i]; sub(/^\.memory\//, "", f); if (index(", " k ", ", ", " f ", ") == 0) k = k (k != "" ? ", " : "") f }
    row = sprintf("%4d commit%s · %2d %s · ", $2, ($2 == 1 ? " " : "s"), $3, ($3 == 1 ? "person" : "people"))
    if (e == 0) { if (ng < max) { gap[++ng] = row "no memory"; gd[ng] = d "/"; w = (length(d) + 1 > w ? length(d) + 1 : w) } }
    else if ($2 >= 5 && (e <= 2 || $2 > 30 * e)) { if (nt < max) { thin[++nt] = row e " mention" (e == 1 ? "" : "s") " (" k ")"; td[nt] = d "/"; w = (length(d) + 1 > w ? length(d) + 1 : w) } }
    else if (nc < 5) { ok[++nc] = row e " mentions (" k ")"; cd[nc] = d "/"; w = (length(d) + 1 > w ? length(d) + 1 : w) } }
  END {
    printf "Where work happened in the last %d days (%d commits; bots left out), and what memory says about it:\n", days, total
    if (w > 44) w = 44
    if (ng) { print "\nBusy, with no memory yet (ask the team, or have the agent read the code and propose entries):"; for (i = 1; i <= ng; i++) printf "  %-" w "s %s\n", gd[i], gap[i] }
    if (nt) { print "\nBusy, with little memory:"; for (i = 1; i <= nt; i++) printf "  %-" w "s %s\n", td[i], thin[i] }
    if (nc) { print "\nCovered:"; for (i = 1; i <= nc; i++) printf "  %-" w "s %s\n", cd[i], ok[i] }
    if (!ng && !nt) print "\nEvery busy folder has memory entries."
  }'
