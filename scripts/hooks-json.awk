# hooks-json.awk — add/remove project-memory hook entries in a Claude Code or Codex hooks JSON file.
# Pure awk (BWK/macOS, gawk, mawk); no python, node or jq.
#   awk -v action=add|remove -v mark=<text in our hook commands> -f hooks-json.awk <target.json|/dev/null> <snippet.json>
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

function fail(msg) { print msg > "/dev/stderr"; exit 2 }
function node(t) { NODES++; T[NODES] = t; N[NODES] = 0; return NODES }
function oput(id, k, v) { N[id]++; K[id, N[id]] = k; C[id, N[id]] = v }
function okey(id, k,   i) { for (i = 1; i <= N[id]; i++) if (K[id, i] == k) return C[id, i]; return 0 }
function odel(id, k,   i, m) {
  m = 0
  for (i = 1; i <= N[id]; i++) if (K[id, i] != k) { m++; K[id, m] = K[id, i]; C[id, m] = C[id, i] }
  N[id] = m
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

# ---- parser: input split into single characters (CH), POS = cursor ----
function parse(s, allow_empty,   v) {
  LEN = split(s, CH, ""); POS = 1; ERR = ""
  ws()
  if (POS > LEN) { if (allow_empty) return node("o"); ERR = "empty file"; return 0 }
  v = value(); if (ERR) return 0
  ws(); if (POS <= LEN) { ERR = "unexpected data after the top-level value (char " POS ")"; return 0 }
  return v
}
function ws() { while (POS <= LEN && (CH[POS] == " " || CH[POS] == "\t" || CH[POS] == "\n" || CH[POS] == "\r")) POS++ }
function value(   c, id) {
  ws(); c = CH[POS]
  if (c == "{") return pobj()
  if (c == "[") return parr()
  if (c == "\"") { id = node("s"); V[id] = str(); return id }
  return lit()
}
function str(   j, r) {
  if (CH[POS] != "\"") { ERR = "expected a string (char " POS ")"; return "" }
  r = "\""; j = POS + 1
  while (1) {
    if (j > LEN) { ERR = "unterminated string"; return "" }
    if (CH[j] == "\\") { r = r CH[j] CH[j + 1]; j += 2; continue }
    r = r CH[j]
    if (CH[j] == "\"") break
    j++
  }
  POS = j + 1
  return r
}
function lit(   t, id) {
  t = ""
  while (POS <= LEN && index("0123456789+-.eEtrufalsn", CH[POS])) t = t CH[POS++]
  if (t ~ /^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$/ || t == "true" || t == "false" || t == "null") {
    id = node("n"); V[id] = t; return id
  }
  ERR = "unexpected '" (t != "" ? t : CH[POS]) "' (char " POS ")"; return 0
}
function pobj(   id, k, v) {
  id = node("o"); POS++; ws()
  if (CH[POS] == "}") { POS++; return id }
  while (1) {
    ws(); k = str(); if (ERR) return 0
    ws(); if (CH[POS] != ":") { ERR = "expected ':' (char " POS ")"; return 0 }
    POS++; v = value(); if (ERR) return 0
    oput(id, k, v); ws()
    if (CH[POS] == ",") { POS++; continue }
    if (CH[POS] == "}") { POS++; return id }
    ERR = "expected ',' or '}' (char " POS ")"; return 0
  }
}
function parr(   id, v) {
  id = node("a"); POS++; ws()
  if (CH[POS] == "]") { POS++; return id }
  while (1) {
    v = value(); if (ERR) return 0
    C[id, ++N[id]] = v; ws()
    if (CH[POS] == ",") { POS++; continue }
    if (CH[POS] == "]") { POS++; return id }
    ERR = "expected ',' or ']' (char " POS ")"; return 0
  }
}

# ---- serializer: same layout as JSON.stringify(x, null, 2) / json.dump(indent=2) ----
function out(id, ind,   s, i, ni) {
  if (T[id] == "s" || T[id] == "n") return V[id]
  if (N[id] == 0) return (T[id] == "o") ? "{}" : "[]"
  ni = ind "  "
  s = (T[id] == "o") ? "{\n" : "[\n"
  for (i = 1; i <= N[id]; i++)
    s = s ni (T[id] == "o" ? K[id, i] ": " : "") out(C[id, i], ni) (i < N[id] ? ",\n" : "\n")
  return s ind ((T[id] == "o") ? "}" : "]")
}
