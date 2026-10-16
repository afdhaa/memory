# json-get.awk — print the members of selected top-level keys of a JSON object, one per line:
#   key<TAB>member<TAB>value      (objects: member = key name; arrays: member = index; scalars: member empty)
#   awk -v keys="name scripts dependencies" -f json.awk -f json-get.awk package.json
# Exits 1 without output if the file is not a valid JSON object.

{ src = src $0 "\n" }

END {
  root = parse(src, 0); if (ERR || T[root] != "o") exit 1
  nk = split(keys, W, " ")
  for (w = 1; w <= nk; w++) {
    v = okey(root, "\"" W[w] "\""); if (!v) continue
    if (T[v] == "o") for (i = 1; i <= N[v]; i++) print W[w] "\t" jtext(K[v, i]) "\t" show(C[v, i])
    else if (T[v] == "a") for (i = 1; i <= N[v]; i++) print W[w] "\t" i "\t" show(C[v, i])
    else print W[w] "\t\t" show(v)
  }
}

function show(id) {
  if (T[id] == "s") return jtext(V[id])
  if (T[id] == "n") return V[id]
  return (T[id] == "o") ? "{…}" : "[…]"
}
