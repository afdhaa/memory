#!/usr/bin/env bash
# team-memory repo scan — run through `mem.sh scan`, which passes the project root and SECRET_RE.
#   bash scan.sh <root> [--print]
# Writes the generated block of .memory/topics/codebase.md (text outside the block is kept; a missing
# "How it fits together" section is added empty for the agent to write), adds it to
# the Map in index.md and fills "Key facts" while that section is still empty. --print only prints the block.
# Reads file names, manifests and git history; never reads .env values. Pure bash + awk + git.
set -u
export LC_ALL=C   # byte semantics: odd encodings in READMEs/manifests never crash awk; stable sort order
ROOT="$1"; MODE="${2:-write}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1
TAB="$(printf '\t')"; BT='`'
TODAY="$(date +%Y-%m-%d)"
IS_GIT=""; git rev-parse --git-dir >/dev/null 2>&1 && IS_GIT=1
HEAD_SHA=""; [ -n "$IS_GIT" ] && HEAD_SHA="$(git rev-parse --short HEAD 2>/dev/null)"

jget() { awk -v keys="$2" -f "$HERE/json.awk" -f "$HERE/json-get.awk" "$1" 2>/dev/null; }
has() { [ -f "$1" ]; }
join() { awk -v sep="$1" 'NF { s = s (n++ ? sep : "") $0 } END { print s }'; }
lower() { tr 'A-Z' 'a-z'; }
# clip <bytes>: shorten long lines at a word boundary (never inside a multi-byte character)
clip() { awk -v n="$1" 'BEGIN { hi = sprintf("[%c-%c]+$", 128, 255) }
  { s = $0; if (length(s) > n) { s = substr(s, 1, n); if (!sub(/ [^ ]*$/, "", s)) sub(hi, "", s); s = s "…" } print s }'; }

# ---- files (relative to ROOT), without memory/agent folders ----
if [ -n "$IS_GIT" ]; then FILES="$(git -c core.quotePath=false ls-files -co --exclude-standard 2>/dev/null)"
  # files deleted in the working tree but not staged yet are still in the index: leave them out
  DEL="$(git -c core.quotePath=false ls-files -d 2>/dev/null)"
  [ -n "$DEL" ] && FILES="$(printf '%s\n' "$FILES" | grep -vxF -f <(printf '%s\n' "$DEL"))"
else FILES="$(find . \( -name .git -o -name node_modules -o -name vendor -o -name dist -o -name build -o -name target \
  -o -name .venv -o -name venv -o -name __pycache__ -o -name .next -o -name .cache \) -prune -o -type f -print 2>/dev/null | sed 's#^\./##')"; fi
FILES="$(printf '%s\n' "$FILES" | grep -vE '(^|/)(\.memory|\.agents|\.claude|\.codex|\.omp|\.git)/' | grep -v '^$' | sort)"
NFILES="$(printf '%s\n' "$FILES" | grep -c .)"
root_has() { printf '%s\n' "$FILES" | grep -qxE "$1"; }

# ---- languages by extension ----
LANGS="$(printf '%s\n' "$FILES" | awk -F/ '
  BEGIN { n = split("ts:TypeScript tsx:TypeScript mts:TypeScript cts:TypeScript js:JavaScript jsx:JavaScript mjs:JavaScript cjs:JavaScript py:Python go:Go rs:Rust java:Java kt:Kotlin kts:Kotlin scala:Scala php:PHP rb:Ruby cs:C# fs:F# swift:Swift m:Objective-C c:C h:C/C++ cc:C++ cpp:C++ hpp:C++ dart:Dart ex:Elixir exs:Elixir erl:Erlang clj:Clojure lua:Lua r:R jl:Julia sh:Shell bash:Shell zsh:Shell ps1:PowerShell vue:Vue svelte:Svelte astro:Astro html:HTML css:CSS scss:SCSS sass:SCSS less:Less sql:SQL graphql:GraphQL gql:GraphQL proto:Protobuf tf:Terraform sol:Solidity zig:Zig nim:Nim hs:Haskell ml:OCaml ipynb:Jupyter", P, " ")
          for (i = 1; i <= n; i++) { split(P[i], kv, ":"); L[kv[1]] = kv[2] } }
  { f = $NF; if (f !~ /\./) next; e = tolower(f); sub(/.*\./, "", e); if (e in L) c[L[e]]++ }
  END { for (l in c) print c[l] "\t" l }' | sort -t"$TAB" -k1,1nr -k2,2 | head -n 8)"
LANG_LINE="$(printf '%s\n' "$LANGS" | awk -F'\t' 'NF { print $2 " (" $1 ")" }' | join ', ')"
LANG_TOP="$(printf '%s\n' "$LANGS" | awk -F'\t' 'NF && n++ < 3 { print $2 }' | join ', ')"

haslock() { [ -f "$1" ] || [ -f "$ROOT/$1" ]; }   # lock files may live at the monorepo root
known() { # known "<file…>" "name:Display …" → "Display, Display"
  local text; text="$(cat $1 2>/dev/null | lower)"
  printf '%s\n' "$2" | tr ' ' '\n' | while IFS=: read -r k v; do
    [ "$k" = "${SELF:-}" ] && continue   # the project itself (Django's own pyproject lists django)
    printf '%s\n' "$text" | grep -qE "(^|[^a-z0-9_.-])$k([^a-z0-9_-]|$)" && printf '%s\n' "${v//_/ }"; done | awk '!s[$0]++' | join ', '
}
# detect_stack: stack and commands of the project in the current directory (root, then each sub-package)
detect_stack() {
# the package's own name, so it is not reported as its own dependency
SELF="$({ sed -n 's/^name[[:space:]]*=[[:space:]]*["'"'"']\([^"'"'"']*\).*/\1/p' pyproject.toml Cargo.toml 2>/dev/null; sed -n 's/^[[:space:]]*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json 2>/dev/null; } | head -n1 | lower)"
# ---- Node / JS ----
PM=""; RUN=""
if has package.json; then
  PKG="$(jget package.json "name dependencies devDependencies peerDependencies scripts engines workspaces packageManager")"
  if haslock pnpm-lock.yaml; then PM=pnpm; RUN="pnpm"; elif haslock yarn.lock; then PM=yarn; RUN="yarn"
  elif haslock bun.lockb || haslock bun.lock; then PM=bun; RUN="bun run"; else PM=npm; RUN="npm run"; fi
  case "$(printf '%s\n' "$PKG" | awk -F'\t' '$1 == "packageManager" { print $3 }')" in pnpm*) PM=pnpm; RUN=pnpm;; yarn*) PM=yarn; RUN=yarn;; esac
  FW="$(printf '%s\n' "$PKG" | awk -F'\t' -v self="$SELF" '
    BEGIN { n = split("next:Next.js nuxt:Nuxt react:React react-native:React_Native expo:Expo vue:Vue svelte:Svelte @sveltejs/kit:SvelteKit @angular/core:Angular solid-js:Solid astro:Astro @remix-run/react:Remix electron:Electron express:Express fastify:Fastify @nestjs/core:NestJS hono:Hono koa:Koa @trpc/server:tRPC graphql:GraphQL socket.io:Socket.IO prisma:Prisma @prisma/client:Prisma drizzle-orm:Drizzle mongoose:Mongoose sequelize:Sequelize typeorm:TypeORM @supabase/supabase-js:Supabase firebase:Firebase tailwindcss:Tailwind @reduxjs/toolkit:Redux zustand:Zustand @tanstack/react-query:TanStack_Query zod:Zod vite:Vite webpack:webpack typescript:TypeScript turbo:Turborepo nx:Nx jest:Jest vitest:Vitest mocha:Mocha @playwright/test:Playwright cypress:Cypress storybook:Storybook eslint:ESLint @biomejs/biome:Biome prettier:Prettier", P, " ")
            for (i = 1; i <= n; i++) { split(P[i], kv, ":"); ORD[i] = kv[1]; NAME[kv[1]] = kv[2] } }
    $1 != "devDependencies" && ($2 in NAME) { RUNTIME[$2] = 1 }
    $1 ~ /ependencies$/ && ($2 in NAME) && !($2 in V) && $2 != self { v = $3; gsub(/^[\^~>=< ]+/, "", v); sub(/[[:space:]|].*/, "", v); V[$2] = v }
    END { for (i = 1; i <= n; i++) if (ORD[i] in V) { nm = NAME[ORD[i]]; gsub(/_/, " ", nm); if (seen[nm]++) continue
            v = V[ORD[i]]; dev = (!(ORD[i] in RUNTIME) && ORD[i] ~ /^(next|nuxt|react|react-native|expo|vue|svelte|@sveltejs\/kit|@angular\/core|solid-js|astro|@remix-run\/react|electron|express|fastify|@nestjs\/core|hono|koa)$/) ? " (dev only)" : ""
            print nm ((v ~ /^[0-9]/) ? " " v : "") dev } }' | join ', ')"
  STACK="${STACK}- Node.js ($PM)${FW:+ — $FW}"$'\n'
  node_ver="$(printf '%s\n' "$PKG" | awk -F'\t' '$1 == "engines" && $2 == "node" { print $3 }')"
  [ -n "$node_ver" ] && STACK="${STACK}- Node version (engines): $node_ver"$'\n'
  ws="$(printf '%s\n' "$PKG" | awk -F'\t' '$1 == "workspaces" && $3 !~ /^[{[]/ { print $3 }' | join ', ')"
  [ -n "$ws" ] && STACK="${STACK}- Workspaces: $ws"$'\n'
  CMDS="${CMDS}$(printf '%s\n' "$PKG" | awk -F'\t' -v run="$RUN" -v insub="${SUBPKG:-}" '
    $1 == "scripts" { N[++n] = $2; V[$2] = $3 }
    END { split("dev start build test lint typecheck format", P, " "); for (i in P) prio[P[i]] = i
      split("prepare install preinstall postinstall prepublish prepublishOnly prepack postpack", L, " "); for (i in L) life[L[i]] = 1
      max = insub ? 3 : 12
      for (i = 1; i <= n; i++) { k = N[i]
        if ((k in life) || (k ~ /^pre/ && (substr(k, 4) in V)) || (k ~ /^post/ && (substr(k, 5) in V))) continue
        if (tolower(V[k]) ~ /(has been|was) (removed|deprecated)|no longer (used|supported)/) continue   # stub that only prints a notice
        if (insub && !(k in prio)) continue
        O[++m] = ((k in prio) ? prio[k] : 100 + i) "\t" k }
      for (i = 1; i <= m; i++) for (j = i + 1; j <= m; j++) { split(O[i], a, "\t"); split(O[j], b, "\t"); if (b[1] + 0 < a[1] + 0) { t = O[i]; O[i] = O[j]; O[j] = t } }
      for (i = 1; i <= m && i <= max; i++) { split(O[i], a, "\t"); print "- `" run " " a[2] "` — " V[a[2]] }
      if (m > max) print "- … " (m - max) " more script(s) in package.json" }' | clip 120)"$'\n'
  FACT_CMDS="$(printf '%s\n' "$PKG" | awk -F'\t' -v run="$RUN" '$1 == "scripts" { S[$2] = 1 }
    END { n = split("dev start build test lint typecheck", W, " "); for (i = 1; i <= n; i++) if (W[i] in S) print "`" run " " W[i] "`" }' | join ' · ')"
fi

# ---- other ecosystems (manifest text, known names only) ----
PYFILES="$(ls pyproject.toml setup.py setup.cfg Pipfile requirements*.txt 2>/dev/null | tr '\n' ' ')"
if [ -n "$PYFILES" ]; then
  tool=pip; haslock uv.lock && tool=uv; haslock poetry.lock && tool=Poetry; haslock Pipfile.lock && tool=Pipenv; haslock pdm.lock && tool=PDM
  fw="$(known "$PYFILES" "django:Django flask:Flask fastapi:FastAPI starlette:Starlette pydantic:Pydantic sqlalchemy:SQLAlchemy sqlmodel:SQLModel alembic:Alembic graphene:Graphene strawberry-graphql:Strawberry ariadne:Ariadne celery:Celery pytest:pytest numpy:NumPy pandas:pandas scikit-learn:scikit-learn torch:PyTorch tensorflow:TensorFlow transformers:Transformers langchain:LangChain requests:requests httpx:httpx streamlit:Streamlit uvicorn:Uvicorn gunicorn:Gunicorn ruff:Ruff mypy:mypy")"
  STACK="${STACK}- Python ($tool)${fw:+ — $fw}"$'\n'
  has .python-version && STACK="${STACK}- Python version: $(head -n1 .python-version)"$'\n'
  pr=""; case "$tool" in uv) pr="uv run ";; Poetry) pr="poetry run ";; PDM) pr="pdm run ";; Pipenv) pr="pipenv run ";; esac
  has tests/runtests.py && CMDS="${CMDS}- \`${pr}python tests/runtests.py\` — the project's own test runner (\`tests/runtests.py\`)"$'\n' && FACT_CMDS="${FACT_CMDS:+$FACT_CMDS · }\`${pr}python tests/runtests.py\`"
  has manage.py && CMDS="${CMDS}- \`${pr}python manage.py runserver\` · \`${pr}python manage.py migrate\` — (Django)"$'\n'
  # Poe the Poet tasks ([tool.poe.tasks]) are often the real entry points
  if has pyproject.toml && grep -q '^\[tool\.poe\.tasks' pyproject.toml; then
    poe="$(awk '/^\[tool\.poe\.tasks\]/ { on = 1; next } /^\[tool\.poe\.tasks\./ { t = $0; sub(/^\[tool\.poe\.tasks\./, "", t); sub(/\].*/, "", t); print t; on = 0; next }
      /^\[/ { on = 0 } on && /^"?[A-Za-z0-9_-]+"?(\.[A-Za-z_]+)?[[:space:]]*=/ { t = $0; sub(/[[:space:]]*=.*/, "", t); sub(/\..*/, "", t); gsub(/"/, "", t); print t }' pyproject.toml | awk '!s[$0]++' | head -n 12 | sed "s/.*/\`${pr}poe &\`/" | join ' · ')"
    [ -n "$poe" ] && CMDS="${CMDS}- Poe tasks: $poe"$'\n'
    case "$poe" in *"poe test\`"*) FACT_CMDS="${FACT_CMDS:+$FACT_CMDS · }\`${pr}poe test\`";; esac
  fi
  case "$fw" in *pytest*) CMDS="${CMDS}- \`${pr}pytest\` — (conventional)"$'\n'; FACT_CMDS="${FACT_CMDS:+$FACT_CMDS · }\`${pr}pytest\`";; esac
fi
if has go.mod; then
  mod="$(awk '$1 == "module" { print $2; exit }' go.mod)"; gov="$(awk '$1 == "go" { print $2; exit }' go.mod)"
  fw="$(known go.mod "gin-gonic/gin:Gin labstack/echo:Echo gofiber/fiber:Fiber go-chi/chi:chi gorm.io/gorm:GORM spf13/cobra:Cobra google.golang.org/grpc:gRPC")"
  STACK="${STACK}- Go ${gov} — module \`$mod\`${fw:+ — $fw}"$'\n'
  [ -z "${SUBPKG:-}" ] && CMDS="${CMDS}- \`go build ./...\` · \`go test ./...\` — (conventional)"$'\n'; FACT_CMDS="${FACT_CMDS:+$FACT_CMDS · }\`go test ./...\`"
fi
if has Cargo.toml; then
  fw="$(known Cargo.toml "tokio:Tokio axum:axum actix-web:actix-web rocket:Rocket serde:serde clap:clap sqlx:SQLx diesel:Diesel tauri:Tauri")"
  ws=""; grep -q '^\[workspace\]' Cargo.toml && ws=" (workspace)"
  STACK="${STACK}- Rust / Cargo${ws}${fw:+ — $fw}"$'\n'
  [ -z "${SUBPKG:-}" ] && CMDS="${CMDS}- \`cargo build\` · \`cargo test\` — (conventional)"$'\n'; FACT_CMDS="${FACT_CMDS:+$FACT_CMDS · }\`cargo test\`"
fi
if has composer.json; then
  CP="$(jget composer.json "require require-dev scripts")"
  fw="$(printf '%s\n' "$CP" | awk -F'\t' '$1 ~ /^require/ { print $2 }' | awk '{ n = split("laravel/framework:Laravel symfony/framework-bundle:Symfony slim/slim:Slim phpunit/phpunit:PHPUnit pestphp/pest:Pest", P, " "); for (i = 1; i <= n; i++) { split(P[i], kv, ":"); if ($0 == kv[1]) print kv[2] } }' | join ', ')"
  STACK="${STACK}- PHP (Composer)${fw:+ — $fw}"$'\n'
  CMDS="${CMDS}$(printf '%s\n' "$CP" | awk -F'\t' '$1 == "scripts" && $2 !~ /^(pre|post)-/ && n++ < 10 { print "- `composer run " $2 "` — " $3 }' | clip 120)"$'\n'
  has artisan && CMDS="${CMDS}- \`php artisan serve\` · \`php artisan test\` — (Laravel)"$'\n'
fi
if has Gemfile; then fw="$(known Gemfile "rails:Rails sinatra:Sinatra rspec:RSpec sidekiq:Sidekiq")"; STACK="${STACK}- Ruby (Bundler)${fw:+ — $fw}"$'\n'; fi
if has pom.xml; then fw="$(known pom.xml "spring-boot:Spring_Boot quarkus:Quarkus junit:JUnit")"; STACK="${STACK}- Java/Kotlin (Maven)${fw:+ — $fw}"$'\n'; fi
if has build.gradle || has build.gradle.kts; then fw="$(known "build.gradle build.gradle.kts" "spring-boot:Spring_Boot com.android:Android ktor:Ktor junit:JUnit")"; STACK="${STACK}- Java/Kotlin (Gradle)${fw:+ — $fw}"$'\n'; fi
root_has '.*\.(csproj|sln)' && STACK="${STACK}- .NET ($(printf '%s\n' "$FILES" | grep -cE '\.csproj$') project files)"$'\n'
if has pubspec.yaml; then fw="$(known pubspec.yaml "flutter:Flutter")"; STACK="${STACK}- Dart${fw:+ — $fw}"$'\n'; fi
if has mix.exs; then fw="$(known mix.exs "phoenix:Phoenix ecto:Ecto")"; STACK="${STACK}- Elixir (Mix)${fw:+ — $fw}"$'\n'; fi
{ has deno.json || has deno.jsonc; } && STACK="${STACK}- Deno"$'\n'
for f in .nvmrc .node-version; do has "$f" && STACK="${STACK}- Node version ($f): $(head -n1 "$f")"$'\n'; done
has .tool-versions && STACK="${STACK}- .tool-versions: $(grep -v '^#' .tool-versions | join ', ')"$'\n'
return 0
}
STACK=""; CMDS=""; FACT_CMDS=""
detect_stack

# ---- sub-packages (monorepos): manifests one or two folders deep ----
PLAIN=""
SUBDIRS="$(printf '%s\n' "$FILES" | grep -E '^[^/]+(/[^/]+)?/(package\.json|pyproject\.toml|requirements\.txt|go\.mod|Cargo\.toml|composer\.json|Gemfile|pom\.xml|build\.gradle(\.kts)?|pubspec\.yaml|mix\.exs)$' |
  grep -vE '(^|/)(node_modules|vendor|dist|build|examples?|samples?|fixtures?|tests?|__tests__|e2e|docs?|bench(mark)?s?|benchmark-apps|playgrounds?|templates?|vendor-bin|tools?/[^/]+-bin|\.[^/]+)/' | sed 's#/[^/]*$##' | awk '!s[$0]++')"
# the 8 largest packages (by files), not the first 8 alphabetically: in big monorepos those are the ones people work in
SUBDIRS="$(printf '%s\n' "$FILES" | C="$SUBDIRS" awk -F/ 'BEGIN { n = split(ENVIRON["C"], L, "\n"); for (i = 1; i <= n; i++) if (L[i] != "") W[L[i]] = 1 }
  NF > 1 { if ($1 in W) c[$1]++; if (NF > 2 && (($1 "/" $2) in W)) c[$1 "/" $2]++ }
  END { for (d in W) print c[d] + 0 "\t" d }' | sort -t"$TAB" -k1,1nr -k2,2 | head -n 8 | cut -f2)"
while IFS= read -r d; do
  [ -n "$d" ] || continue
  sub="$(cd "$d" && SUBPKG=1 && STACK="" && CMDS="" && FACT_CMDS="" && detect_stack && { printf '%s\n' "$STACK" | grep -vE '^$|^- (Workspaces|Node version|Python version)'; echo "@@"; printf '%s\n' "$CMDS" | grep -v '^$' | head -n 8; })"
  st="$(printf '%s\n' "$sub" | sed '/^@@$/,$d' | sed "s#^- #- $BT$d/$BT — #")"
  cm="$(printf '%s\n' "$sub" | sed '1,/^@@$/d' | sed "s#^- #- (in $BT$d/$BT) #")"
  # no framework found ("- `d/` — Node.js (yarn)"): list it once at the end instead of a line of its own
  if [ -n "$st" ] && [ "$(printf '%s\n' "$st" | grep -c ' — .* — ')" -eq 0 ] && [ "$(printf '%s\n' "$st" | grep -c .)" -eq 1 ]; then
    PLAIN="${PLAIN:+$PLAIN, }$BT$d/$BT"
  elif [ -n "$st" ]; then STACK="${STACK}${st}"$'\n'; fi
  [ -n "$cm" ] && CMDS="${CMDS}${cm}"$'\n'
done <<EOF
$SUBDIRS
EOF
[ -n "${PLAIN:-}" ] && STACK="${STACK}- Other packages (no framework detected): $PLAIN"$'\n'
# shell scripts kept in scripts/ folders are usually the real entry points (test.sh, build.sh…)
SH="$(printf '%s\n' "$FILES" | grep -E '(^|/)scripts/[^/]+\.sh$' | head -n 10 | sed 's/.*/`&`/' | join ', ')"
[ -n "$SH" ] && CMDS="${CMDS}- Shell scripts: $SH"$'\n'

# Makefile / justfile targets
for mf in Makefile makefile GNUmakefile; do
  has "$mf" || continue
  t="$(awk -F: '/^[A-Za-z0-9][A-Za-z0-9_.\/-]*:([^=]|$)/ && $1 !~ /^\./ && !s[$1]++ && n++ < 15 { print "`make " $1 "`" }' "$mf" | join ' · ')"
  [ -n "$t" ] && CMDS="${CMDS}- $t"$'\n'
  [ -z "$FACT_CMDS" ] && FACT_CMDS="$(awk -F: '/^(test|build|run|dev|lint):/ { print "`make " $1 "`" }' "$mf" | join ' · ')"
  break
done
for jf in justfile Justfile .justfile; do
  has "$jf" || continue
  t="$(awk '/^@?[A-Za-z_][A-Za-z0-9_-]*( [^:]*)?:([^=]|$)/ { r = $1; sub(/^@/, "", r); sub(/:.*/, "", r); if (!s[r]++ && n++ < 15) print "`just " r "`" }' "$jf" | join ' · ')"
  [ -n "$t" ] && CMDS="${CMDS}- $t"$'\n'; break
done

# ---- infrastructure, CI, deploy ----
INFRA=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  sv="$(awk '/^services:/ { on = 1; ind = 0; next } on && /^[^ #]/ { on = 0 }
    on && /^ +[A-Za-z0-9_.-]+:/ { match($0, /^ +/); if (!ind) ind = RLENGTH; if (RLENGTH == ind) { s = $1; sub(/:$/, "", s); print s } }' "$f" | join ', ')"
  INFRA="${INFRA}- \`$f\`${sv:+ — services: $sv}"$'\n'
done <<EOF
$(printf '%s\n' "$FILES" | grep -E '^(docker-compose|compose)[^/]*\.ya?ml$')
EOF
df="$(printf '%s\n' "$FILES" | grep -E '(^|/)Dockerfile[^/]*$' | head -n 6 | sed 's/.*/`&`/' | join ', ')"
[ -n "$df" ] && INFRA="${INFRA}- Docker: $df"$'\n'
wf="$(printf '%s\n' "$FILES" | grep -E '^\.github/workflows/[^/]+\.ya?ml$' | sed 's#^\.github/workflows/##' | join ', ')"
[ -n "$wf" ] && INFRA="${INFRA}- GitHub Actions: $wf"$'\n'
for pair in ".gitlab-ci.yml:GitLab CI" "Jenkinsfile:Jenkins" ".circleci/config.yml:CircleCI" "bitbucket-pipelines.yml:Bitbucket Pipelines" \
            "vercel.json:Vercel" "netlify.toml:Netlify" "fly.toml:Fly.io" "Procfile:Procfile (Heroku-style)" "app.yaml:App Engine" \
            "serverless.yml:Serverless Framework" "render.yaml:Render" "railway.json:Railway" "wrangler.toml:Cloudflare Workers" "Chart.yaml:Helm"; do
  has "${pair%%:*}" && INFRA="${INFRA}- ${pair#*:} (\`${pair%%:*}\`)"$'\n'
done
tf="$(printf '%s\n' "$FILES" | grep -cE '\.tf$')"; [ "$tf" -gt 0 ] && INFRA="${INFRA}- Terraform: $tf files"$'\n'

# ---- config & environment (names only) ----
ENV=""; ENV_KEYS=0; ENV_EX=""
for f in .env.example .env.sample .env.template .env.dist .env.local.example example.env; do
  has "$f" || continue
  keys="$(sed -nE 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/p' "$f" | awk '!s[$0]++')"
  n="$(printf '%s\n' "$keys" | grep -c .)"; ENV_KEYS=$((ENV_KEYS + n)); ENV_EX="${ENV_EX:-$f}"
  more=""; [ "$n" -gt 15 ] && more=" … (+$((n - 15)) more)"
  ENV="${ENV}- \`$f\` ($n): $(printf '%s\n' "$keys" | head -n 15 | join ', ')$more"$'\n'
done
for f in .env .env.local .env.development .env.production; do
  [ -f "$f" ] || continue
  if printf '%s\n' "$FILES" | grep -qxF "$f" && [ -n "$IS_GIT" ] && git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    ENV="${ENV}- \`$f\` is committed to git (shared defaults) — values not read; never copy them into memory"$'\n'
  else ENV="${ENV}- \`$f\` exists locally — values not read; never copy them into memory"$'\n'; fi
done

# ---- layout ----
CHILDREN="$(printf '%s\n' "$FILES" | awk -F/ 'NF > 2 { c[$1 "\t" $2]++ } END { for (k in c) if (c[k] > 1) print k "\t" c[k] }' |
  sort -t"$TAB" -k1,1 -k3,3nr -k2,2 | awk -F'\t' 'n[$1]++ < 6')"
DIRS="$(printf '%s\n' "$FILES" | awk -F/ 'NF > 1 && ($1 !~ /^\./ || $1 == ".github") { c[$1]++ } END { for (d in c) print c[d] "\t" d }' | sort -t"$TAB" -k1,1nr -k2,2 | head -n 12)"
# top-level folders, each followed by its largest subfolders as nested bullets
LAYOUT="$(printf '%s\n' "$DIRS" | CH="$CHILDREN" awk -F'\t' '
  BEGIN { n = split(ENVIRON["CH"], L, "\n"); for (i = 1; i <= n; i++) { split(L[i], p, "\t"); if (p[1] != "") S[p[1]] = S[p[1]] "  - `" p[1] "/" p[2] "/` — " p[3] (p[3] == 1 ? " file\n" : " files\n") } }
  NF { printf "- `%s/` — %s file%s\n%s", $2, $1, ($1 == 1 ? "" : "s"), S[$2] }')"
ROOTF="$(printf '%s\n' "$FILES" | awk -F/ 'NF == 1' | head -n 25 | sed 's/.*/`&`/' | join ', ')"
TOP_DIRS="$(printf '%s\n' "$DIRS" | awk -F'\t' 'NF && $2 !~ /^\./ && tolower($2) !~ /^(img|imgs|images?|assets|static|media|screenshots)$/ && n++ < 5 { print "`" $2 "/`" }' | join ', ')"

# ---- tests & docs ----
TESTS="$(printf '%s\n' "$FILES" | grep -E '(^|/)(tests?|__tests__|spec|e2e)/|[._-](test|spec)\.[A-Za-z]+$|_test\.go$|(^|/)test_[^/]*\.py$|(^|/)tests?\.(js|mjs|cjs|ts|py|rb|go|rs|php|sh|java|kt|swift|c|cc|cpp|exs?|lua)$')"
NTESTS="$(printf '%s\n' "$TESTS" | grep -c .)"
TEST_DIRS="$(printf '%s\n' "$TESTS" | awk -F/ 'NF { k = (NF > 1) ? $1 "/" : "(root)"; c[k]++ } END { for (k in c) print c[k] "\t" k }' |
  sort -t"$TAB" -k1,1nr -k2,2 | head -n 5 | awk -F'\t' '{ print "`" $2 "` " $1 }' | join ', ')"
DOCS="$(printf '%s\n' "$FILES" | grep -iE '^(readme(\.(md|rst|txt))?|[^/]+\.(md|mdx|rst))$' | grep -viE '^(license|licence|code_of_conduct|changelog|release-notes|history|cla|dco|security|support|governance|maintainers)[._-]' |
  while IFS= read -r f; do
    case "$f" in (AGENTS.md|CLAUDE.md|GEMINI.md) [ -L "$f" ] && continue ;; esac   # CLAUDE.md -> AGENTS.md: listed once; also skip AGENTS.md / CLAUDE.md that hold nothing but our own bootstrap block
    awk '/<!-- (team|project)-memory:start -->/ { b = 1; next } /<!-- (team|project)-memory:end -->/ { b = 0; next } !b && /[^[:space:]]/ && !/^[[:space:]]*@\.?\/?AGENTS\.md[[:space:]]*$/ { o = 1 } END { exit !o }' "$f" 2>/dev/null && printf '%s\n' "$f"
  done | awk '{ l = tolower($0); k = (l ~ /^readme(\.[a-z]+)?$/) ? 0 : (l ~ /^readme[-_.]/ ? 2 : 1); print k "\t" $0 }' | sort -t"$TAB" -k1,1n -k2,2 |
  awk -F'\t' '$1 == 2 { tr[++t] = $2; next } { print "`" $2 "`" }   # README-de.md, README.zh-CN.md…: one entry
    END { if (t > 2) print "`README-*` (" t " translations)"; else for (i = 1; i <= t; i++) print "`" tr[i] "`" }' | head -n 8 | join ', ')"
nd="$(printf '%s\n' "$FILES" | grep -cE '^docs?/.*\.(md|mdx|rst|txt|adoc)$')"; [ "$nd" -gt 0 ] && DOCS="${DOCS:+$DOCS, }\`docs/\` ($nd pages)"
# agent instructions scoped to a folder (frontend/AGENTS.md…) apply to everything below it
SCOPED="$(printf '%s\n' "$FILES" | grep -E '^[^/].*/(AGENTS|CLAUDE)\.md$' | grep -vE '(^|/)(node_modules|vendor)/' | head -n 8 | sed 's/.*/`&`/' | join ', ')"
[ -n "$SCOPED" ] && DOCS="${DOCS:+$DOCS; }agent instructions for sub-folders: $SCOPED"

# ---- README summary ----
README_F=""; for f in README.md readme.md Readme.md README.rst README.txt README; do has "$f" && { README_F="$f"; break; }; done
README_SUM=""; TITLE=""
if [ -n "$README_F" ]; then
  # title = first "# " or setext "===" heading; summary = first prose or blockquote paragraph that is not a
  # list, a GitHub alert or an intro ending in ":" — looked for only before the second "##" section
  R="$(awk '
    function words(s,  t) { t = s; gsub(/<[^>]*>|&[a-z]+;|\]\([^)]*\)/, " ", t); return gsub(/[A-Za-z][A-Za-z]+/, "&", t) }
    function seps(x,  y) { y = x; return gsub(/∙| \| | · /, "", y) }
    function emit() { if (p != "" && seps(p) < 3 && p !~ /:[[:space:]]*$/ && p !~ /^([-*+]|[0-9]+[.)])[[:space:]]/ && words(p) >= 4) found = p; p = ""; pl = 0 }
    /^[[:space:]]*(```|~~~)/ { emit(); if (found != "") exit; code = !code; next } code { next }
    cm { if (/-->/) cm = 0; next }
    /^[[:space:]]*<!--/ { if (!/-->/) cm = 1; next }
    /^=+[[:space:]]*$/ && p != "" && pl == 1 { if (title == "") title = p; p = ""; pl = 0; next }
    /^-+[[:space:]]*$/ && p != "" && pl == 1 { p = ""; pl = 0; if (++h2 >= 2) exit; next }
    /^#/ { emit(); if (found != "") exit
           if (title == "" && /^# /) { t = $0; sub(/^# +/, "", t)
             # badges and logos in the heading: keep the text; an image-only heading gives its alt text
             a = t; gsub(/\[!\[[^]]*\]\([^)]*\)\]\([^)]*\)|!\[[^]]*\]\([^)]*\)|<[^>]*>/, "", a); gsub(/^[[:space:]]+|[[:space:]]+$/, "", a)
             if (a == "" && match(t, /!\[[^]]*\]/)) a = substr(t, RSTART + 2, RLENGTH - 3)
             title = a } else if (/^## / && ++h2 >= 2) exit
           next }
    /^[[:space:]]*$/ { emit(); if (found != "") exit; next }
    /^>/ { s = $0; sub(/^>[[:space:]]*/, "", s); if (s ~ /^\[!/) { alert = 1; next }
           if (alert || s == "") { emit(); if (found != "") exit; next }
           sub(/^#+[[:space:]]*/, "", s); p = p (p != "" ? " " : "") s; pl++; next }
    { alert = 0 }
    /^[[:space:]]*(<|!\[|\[!\[|\|)/ { emit(); if (found != "") exit; next }
    { p = p (p != "" ? " " : "") $0; pl++ }
    END { if (found == "") emit(); gsub(/[[:space:]]+/, " ", found); print title; print found }' "$README_F" |
    sed -E 's/\[!\[[^]]*\]\([^)]*\)\]\([^)]*\)//g; s/!\[([^]]*)\]\([^)]*\)/\1/g; s/\[([^]]*)\]\([^)]*\)/\1/g; s/\[([^]]+)\]\[[^]]*\]/\1/g; s/\[([^]]+)\]([^(]|$)/\1\2/g; s/\*\*([^*]+)\*\*/\1/g; s/__([^_]+)__/\1/g
      s/\|[A-Za-z][^|]{0,40}\|_{0,2}//g; s/<[^>]*>/ /g; s/&nbsp;|&[a-z]+;/ /g; s/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//')"
  TITLE="$(printf '%s\n' "$R" | sed -n 1p | clip 80)"; README_SUM="$(printf '%s\n' "$R" | sed -n 2p | clip 320)"
  [ "$(printf '%s' "$README_SUM" | tr -cs 'A-Za-z' ' ' | wc -w)" -ge 4 ] || README_SUM=""   # "&nbsp;", a lone link…
fi
# the manifest description: used when the README gives no paragraph, or only a very short one ("... so better sign this")
MDESC=""
has package.json && MDESC="$(jget package.json description | awk -F'\t' '$1 == "description" { print $NF; exit }')"
[ -z "$MDESC" ] && has pyproject.toml && MDESC="$(awk '/^\[(project|tool\.poetry)\]/ { p = 1; next } /^\[/ { p = 0 } p && /^description[[:space:]]*=/ { sub(/^[^"]*"/, ""); sub(/".*$/, ""); print; exit }' pyproject.toml)"
[ -z "$MDESC" ] && has composer.json && MDESC="$(jget composer.json description | awk -F'\t' '$1 == "description" { print $NF; exit }')"
[ -z "$MDESC" ] && has Cargo.toml && MDESC="$(awk '/^\[package\]/ { p = 1; next } /^\[/ { p = 0 } p && /^description[[:space:]]*=/ { sub(/^[^"]*"/, ""); sub(/".*$/, ""); print; exit }' Cargo.toml)"
if [ -n "$MDESC" ] && { [ -z "$README_SUM" ] || [ "$(printf '%s' "$README_SUM" | wc -w)" -lt 8 ]; }; then README_SUM="$(printf '%s' "$MDESC" | clip 320)"; fi

# ---- git ----
GIT=""; ACTIVE=""
if [ -n "$IS_GIT" ] && [ -n "$HEAD_SHA" ]; then
  remote="$(git remote get-url origin 2>/dev/null | sed -E 's#://[^@/]+@#://#')"
  GIT="It is versioned with git: branch \`$(git rev-parse --abbrev-ref HEAD)\`, $(git rev-list --count HEAD) commits, last commit on $(git log -1 --format=%cs)${remote:+, remote \`$remote\`}."
  # leave out the oldest commit in view when it has no parent here (root commit, or the edge of a shallow CI clone):
  # it lists every file of the repo as changed
  NACT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"; [ "$NACT" -gt 300 ] && NACT=300 || NACT=$((NACT - 1))
  [ "$NACT" -gt 0 ] && ACTIVE="$(git -c core.quotePath=false log -n "$NACT" --name-only --format='@@%an' --relative 2>/dev/null |
    # dependency and CI bumps by bots (dependabot, renovate, pre-commit-ci) say nothing about where people work
    awk '/^@@/ { bot = (tolower($0) ~ /\[bot\]|dependabot|renovate|pre-commit-ci|github-actions|greenkeeper/); next } !bot && NF' | grep -vE '(^|/)(\.memory|\.agents|\.claude|\.codex|\.omp)/' |
    awk -F/ '{ k = (NF > 2) ? $1 "/" $2 "/" : ((NF == 2) ? $1 "/" : $1); c[k]++ } END { for (k in c) print c[k] "\t" k }' |
    sort -t"$TAB" -k1,1nr -k2,2 | while IFS="$TAB" read -r c k; do [ -e "$k" ] && printf '%s\t%s\n' "$c" "$k"; done |
    head -n 8 | awk -F'\t' '{ print "`" $2 "` " $1 }' | join ', ')"
fi

# ---- assemble the generated block ----
# sec <title> <intro sentence> <lines>: a section that opens with one sentence saying what the list is
sec() { [ -n "$(printf '%s' "$3" | tr -d '[:space:]')" ] && printf '\n### %s\n%s\n%s\n' "$1" "$2" "$(printf '%s\n' "$3" | grep -v '^$')"; }
BODY="$(
  printf '### Overview\n'
  [ "$(printf '%s' "$TITLE" | tr 'A-Z' 'a-z')" = "$(basename "$ROOT" | tr 'A-Z' 'a-z')" ] && TITLE=""
  printf '**%s**%s has %s file%s%s.\n' "$(basename "$ROOT")" "${TITLE:+ ("$TITLE")}" "$NFILES" "$([ "$NFILES" = 1 ] || echo s)" "${LANG_LINE:+ — by language: $LANG_LINE}"
  [ -n "$README_SUM" ] && printf 'It describes itself as: "%s"\n' "$README_SUM"
  [ -n "$GIT" ] && printf '%s\n' "$GIT"
  [ -n "$DOCS" ] && printf 'Documentation to read first: %s.\n' "$DOCS"
  if [ -f "$HERE/changelog.sh" ]; then . "$HERE/changelog.sh"
    case "$(changelog_info "$ROOT" | cut -f1,2)" in
      (fragments*) printf 'Changes for users are recorded as fragments or release notes in %s, not in a single changelog file.\n' "$BT$(changelog_info "$ROOT" | cut -f2)$BT" ;;
      (generated*) printf 'The changelog is generated from commit messages (%s); it is not edited by hand.\n' "$BT$(changelog_info "$ROOT" | cut -f2)$BT" ;;
      (file*) printf 'Changes for users are recorded in %s.\n' "$BT$(changelog_info "$ROOT" | cut -f2)$BT" ;;
    esac
  fi
  sec "Stack" "Languages, frameworks and tools detected from the manifest files (versions are the declared ranges):" "$STACK"
  sec "Commands" "How to run, build and test. Each line gives the command, then what it executes; \"(conventional)\" means the ecosystem default, not a script found in the repo:" "$CMDS"
  sec "Layout" "The largest top-level folders, with their file counts and biggest subfolders:" "$LAYOUT${ROOTF:+
- Files at the repository root: $ROOTF}"
  sec "Infrastructure & CI" "How the project is containerised, checked in CI and deployed:" "$INFRA"
  sec "Config & environment" "Configuration comes from environment variables. Only the variable names are listed; values are never read:" "$ENV"
  [ "$NTESTS" -gt 0 ] && sec "Tests" "Where the automated tests live:" "- $NTESTS test file$([ "$NTESTS" = 1 ] || echo s) — $TEST_DIRS"
  [ -n "$ACTIVE" ] && sec "Recently active areas" "Where most changes landed in the last ${NACT:-300} commits (files touched per folder) — a hint of where current work happens:" "- $ACTIVE"
)"
[ -n "${SECRET_RE:-}" ] && BODY="$(printf '%s\n' "$BODY" | grep -vE "$SECRET_RE")"
START="<!-- scan:start · generated by mem.sh scan on $TODAY${HEAD_SHA:+ at commit $HEAD_SHA}; this block is replaced on every scan -->"
BLOCK="$START
$BODY
<!-- scan:end -->"

if [ "$MODE" = "--print" ]; then printf '%s\n' "$BLOCK"; exit 0; fi

# ---- write .memory/topics/codebase.md (keep everything outside the block) ----
OUT=".memory/topics/codebase.md"; mkdir -p .memory/topics
OVERVIEW_H="## How it fits together"
OVERVIEW="$OVERVIEW_H
<!-- Written by the agent after a scan; mem.sh scan never changes it. 3–6 short paragraphs for a
     newcomer, in full sentences: what the code does and its main parts; how a typical request or job
     flows through it (entry point → … → storage/output), naming real files and folders; where to
     start reading; conventions or design choices that are not obvious from the file names. -->"
LAYOUT_H="## Project layout"
LAYOUT_S="$(cat <<'MD'
## Project layout
<!-- Written by the agent after a scan; mem.sh scan never changes it. One line per folder (or root
     file) a newcomer needs: what lives there and where new code of that kind goes. Take the list from
     the generated Layout below; skip folders nobody edits (build output, vendored code). Example:
- `src/routes/` — Express routers, one file per URL prefix; keep them thin and call a service.
- `src/services/` — business logic (pricing, catalogue, supplier sync); new features start here.
-->
MD
)"
FACTS_H="## Repository facts (generated)
> Produced by \`mem.sh scan\` from file names, manifests and git history. Do not edit: this block is
> replaced on every scan. Write explanations in the sections above instead."
if [ -f "$OUT" ] && grep -q '^<!-- scan:start' "$OUT"; then
  BLK="$BLOCK" awk '/^<!-- scan:start/ { print ENVIRON["BLK"]; skip = 1; next } skip && /^<!-- scan:end -->/ { skip = 0; next } !skip { print }' "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
  echo "~ $OUT (scan refreshed)"
elif [ -f "$OUT" ]; then
  { cat "$OUT"; printf '\n%s\n%s\n' "$FACTS_H" "$BLOCK"; } > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"; echo "+ $OUT (scan block added at the end)"
else
  printf '# Codebase\n\n%s\n\n%s\n\n## Notes\n<!-- Other facts about the codebase worth keeping, in full sentences. -->\n\n%s\n%s\n' "$OVERVIEW" "$LAYOUT_S" "$FACTS_H" "$BLOCK" > "$OUT"
  echo "+ $OUT"
fi
# older codebase.md without the narrative section: add it once, right after the title
if ! grep -qxF "$OVERVIEW_H" "$OUT"; then
  OV="$OVERVIEW" awk 'NR == 1 && /^# / { print; print ""; print ENVIRON["OV"]; print ""; done = 1; next }
    NR == 1 { print ENVIRON["OV"]; print ""; done = 1 } { print }' "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
  echo "~ $OUT (added \"How it fits together\" for the agent to write)"
fi
# …and without "Project layout": add it once, before Notes / the generated facts (or at the end)
if ! grep -qxF "$LAYOUT_H" "$OUT"; then
  LS="$LAYOUT_S" awk '!done && (/^## Notes$/ || /^## Repository facts/ || /^<!-- scan:start/) { print ENVIRON["LS"]; print ""; done = 1 }
    { print } END { if (!done) { print ""; print ENVIRON["LS"] } }' "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
  echo "~ $OUT (added \"Project layout\" for the agent to write)"
fi

# ---- index.md: Map entry + Key facts while empty ----
IDX=".memory/index.md"
[ -f "$IDX" ] || exit 0
# section_fill <file> <heading> <lines> <only-if-empty: 1|0> — append lines at the end of a "## heading" section
# files edited on Windows (CRLF): edit them as LF, then restore their line endings
CR="$(printf '\r')"
lf_begin() { WAS_CRLF=""; grep -q "$CR\$" "$1" 2>/dev/null || return 0; WAS_CRLF=1; tr -d '\r' < "$1" > "$1.lf" && cat "$1.lf" > "$1" && rm -f "$1.lf"; }
lf_end() { [ -n "${WAS_CRLF:-}" ] || return 0; sed "s/\$/$CR/" "$1" > "$1.cr" && cat "$1.cr" > "$1" && rm -f "$1.cr"; }
section_fill() {
  lf_begin "$1"
  LINES="$3" awk -v h="## $2" -v only="$4" '
    { L[++n] = $0 }
    END {
      for (i = 1; i <= n; i++) if (L[i] == h) s = i
      if (!s) { for (i = 1; i <= n; i++) print L[i]; print ""; print h; print ENVIRON["LINES"]; exit }
      e = n + 1; for (i = s + 1; i <= n; i++) if (L[i] ~ /^## /) { e = i; break }
      inc = 0; full = 0
      for (i = s + 1; i < e; i++) { l = L[i]
        if (inc) { if (l ~ /-->/) inc = 0; continue }
        if (l ~ /^[[:space:]]*<!--/) { if (l !~ /-->/) inc = 1; continue }
        if (l ~ /[^[:space:]]/) full = 1 }
      last = s; for (i = s + 1; i < e; i++) if (L[i] ~ /[^[:space:]]/) last = i
      for (i = 1; i <= last; i++) print L[i]
      if (!(only == 1 && full)) print ENVIRON["LINES"]
      for (i = last + 1; i <= n; i++) print L[i]
    }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
  lf_end "$1"
}
if ! grep -q 'topics/codebase\.md' "$IDX"; then
  section_fill "$IDX" "Map" "- topics/codebase.md — how the code fits together, what each folder is for, plus generated repo facts: stack, commands, layout, config, CI (refresh: mem.sh scan)" 0
  echo "~ $IDX (Map: topics/codebase.md)"
fi
FACTS=""
[ -n "$LANG_TOP$STACK" ] && FACTS="- Stack: $(printf '%s\n' "$LANG_TOP" "$(printf '%s\n' "$STACK" | grep -E '^- (`[^`]*` — )?(Node\.js|Python|Go |Rust|PHP|Ruby|Java|\.NET|Dart|Elixir|Deno)' |
  awk '{ print (index($0, " — ") ? 0 : 1) "\t" NR "\t" $0 }' | sort -t"$TAB" -k1,1n -k2,2n | cut -f3 | head -n 3 | sed 's/^- //')" | grep -v '^$' | join ' · ')"
[ -n "$FACT_CMDS" ] && FACTS="${FACTS:+$FACTS
}- Commands: $FACT_CMDS"
[ -n "$TOP_DIRS" ] && FACTS="${FACTS:+$FACTS
}- Main folders: $TOP_DIRS"
[ -n "$ENV_EX" ] && FACTS="${FACTS:+$FACTS
}- Config: environment variables listed in \`$ENV_EX\` ($ENV_KEYS); real values only in local \`.env\` files"
FACTS="${FACTS:+$FACTS
}- More: topics/codebase.md (how the code fits together, project layout, generated facts)"
before="$(cksum < "$IDX")"
section_fill "$IDX" "Key facts" "$FACTS" 1
[ "$before" != "$(cksum < "$IDX")" ] && echo "~ $IDX (Key facts filled from scan)"
exit 0
