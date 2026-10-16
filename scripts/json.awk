# json.awk — minimal JSON parser/serializer library, pure awk (BWK/macOS, gawk, mawk).
# Load before a main program:  awk -f json.awk -f <main>.awk …
# Nodes: T[id] = o|a|s|n; objects/arrays: N[id] members, K[id,i] raw key (with quotes), C[id,i] child;
# strings/literals: V[id] raw JSON text. parse() sets ERR on invalid input.

function fail(msg) { print msg > "/dev/stderr"; exit 2 }
function node(t) { NODES++; T[NODES] = t; N[NODES] = 0; return NODES }
function oput(id, k, v) { N[id]++; K[id, N[id]] = k; C[id, N[id]] = v }
function okey(id, k,   i) { for (i = 1; i <= N[id]; i++) if (K[id, i] == k) return C[id, i]; return 0 }
function odel(id, k,   i, m) {
  m = 0
  for (i = 1; i <= N[id]; i++) if (K[id, i] != k) { m++; K[id, m] = K[id, i]; C[id, m] = C[id, i] }
  N[id] = m
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

# raw JSON string → plain text (\uXXXX kept as written; newlines/tabs become spaces)
function jtext(raw,   s) {
  s = substr(raw, 2, length(raw) - 2)
  gsub(/\\[nrt]/, " ", s); gsub(/\\"/, "\"", s); gsub(/\\\//, "/", s); gsub(/\\\\/, "\\", s)
  return s
}
