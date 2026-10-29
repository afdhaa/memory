# hooks-json.awk — add/remove team-memory hook entries in a Claude Code or Codex hooks JSON file.
# Pure awk (BWK/macOS, gawk, mawk); no python, node or jq.
#   awk -v action=add|remove -v mark=<text in our hook commands> -f json.awk -f hooks-json.awk <target.json|/dev/null> <snippet.json>
# Prints the updated JSON (2-space indent) on stdout. Exits 2 without output if a file is not valid JSON.
# Only hook commands containing `mark` are touched; every other key, entry and hook is kept as written.

{ if (FILENAME == ARGV[1]) tgt = tgt $0 "\n"; else snp = snp $0 "\n" }

END {
  root = parse(tgt, 1); if (ERR) fail("not valid JSON: " ERR)
  if (T[root] != "o") fail("top level is not a JSON object")
  hooks = okey(root, "\"hooks\"")
  if (hooks && T[hooks] != "o") fail("\"hooks\" is not a JSON object")
  if (hooks) strip(hooks)
  if (action == "add") {
    snip = parse(snp, 0); if (ERR) fail("snippet is not valid JSON: " ERR)
    sh = okey(snip, "\"hooks\"")
    if (!hooks) { hooks = node("o"); oput(root, "\"hooks\"", hooks) }
    for (i = 1; i <= N[sh]; i++) {
      arr = okey(hooks, K[sh, i])
      if (!arr) { arr = node("a"); oput(hooks, K[sh, i], arr) }
      if (T[arr] != "a") fail("hooks." K[sh, i] " is not a JSON array")
      src = C[sh, i]
      for (j = 1; j <= N[src]; j++) C[arr, ++N[arr]] = C[src, j]
    }
  }
  if (hooks && N[hooks] == 0) odel(root, "\"hooks\"")
  printf "%s\n", out(root, "")
}

# a hook object whose "command" string contains the mark (JSON may escape "/" as "\/")
function ours(h,   c, s) {
  if (T[h] != "o") return 0
  c = okey(h, "\"command\""); if (!c || T[c] != "s") return 0
  s = V[c]; gsub(/\\\//, "/", s)
  return index(s, mark) > 0
}

# remove our hooks; drop entries and events that become empty because of it
function strip(hooks,   i, m, ev, arr, j, mm, e, hk, k, kk, gone, emptied) {
  m = 0
  for (i = 1; i <= N[hooks]; i++) {
    arr = C[hooks, i]; emptied = 0
    if (T[arr] == "a") {
      mm = 0
      for (j = 1; j <= N[arr]; j++) {
        e = C[arr, j]; gone = 0
        if (T[e] == "o" && (hk = okey(e, "\"hooks\"")) && T[hk] == "a") {
          kk = 0
          for (k = 1; k <= N[hk]; k++) if (!ours(C[hk, k])) C[hk, ++kk] = C[hk, k]
          if (kk == 0 && N[hk] > 0) gone = 1
          N[hk] = kk
        }
        if (!gone) C[arr, ++mm] = e
      }
      if (mm == 0 && N[arr] > 0) emptied = 1
      N[arr] = mm
    }
    if (!emptied) { m++; K[hooks, m] = K[hooks, i]; C[hooks, m] = C[hooks, i] }
  }
  N[hooks] = m
}

