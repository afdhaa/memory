# pm_hit(path, tag): does an @path tag apply to a repo-relative path?
# A tag matches the path itself and everything below it. Patterns: * = any characters within one path
# segment, ** = any depth ("src/**/*.ts" also matches "src/x.ts"). The regex is built one character at a
# time because bracket tricks such as /[][…]/ are read differently by gawk, mawk and BWK awk.
function pm_hit(p, t,   re, i, c) {
  if (p == t || index(p, t "/") == 1) return 1
  if (t !~ /\*/) return 0
  re = ""
  for (i = 1; i <= length(t); i++) {
    c = substr(t, i, 1)
    if (c == "*") {
      if (substr(t, i + 1, 2) == "*/") { re = re "(.*/)?"; i += 2 }
      else if (substr(t, i + 1, 1) == "*") { re = re ".*"; i++ }
      else re = re "[^/]*"
    }
    else if (c == "^") re = re "\\^"
    else if (c == "\\") re = re "\\\\"
    else if (index(".+?$(){}|[]", c)) re = re "[" c "]"
    else re = re c
  }
  return (p ~ ("^" re "(/|$)"))
}
