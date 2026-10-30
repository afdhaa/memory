#!/usr/bin/env bash
# team-memory: how this project records changes for its users — sourced by mem.sh, scan.sh and the hooks.
#   changelog_info <project-root>  →  "<kind>\t<file, folder or tool>\t<what an agent should do>"
# kind: rule (index.md says), fragments (changesets, towncrier, release-notes folder…), generated (from commits
# or PR titles), file (an existing changelog), none (nothing found: ask the user, never create one unasked)
# a changelog written by a tool: a marker line, or version headings that link to a compare URL
# ("## [8.3.5](https://github.com/o/r/compare/v8.3.4...v8.3.5)", as conventional-changelog writes them)
cl_generated() {
  head -n 15 "$1" | grep -qiE 'auto(matically)?[- ]generated|do not edit|semantic-release|release-please|git-cliff|^#+ .*\]\(https?://[^)]*/compare/'
}
changelog_info() {
  local r="${1:-.}" f v
  # the user's answer, recorded once in index.md Rules: "- Changelog: CHANGELOG.md" / "- Changelog: none"
  v="$(sed -n 's/^[[:space:]]*[-*][[:space:]]*[Cc]hangelog:[[:space:]]*`\{0,1\}\([^`[:space:]]*\).*/\1/p' "$r/.memory/index.md" 2>/dev/null | head -n1)"
  v="${v%[;,.:]}"   # "- Changelog: none; …", "CHANGES.md."
  case "$(printf '%s' "$v" | tr 'A-Z' 'a-z')" in
    none|no|-) printf 'rule\tnone\tthis project keeps no changelog (index.md Rules): record nothing\n'; return ;; esac
  # a file name ("CHANGES.md", "docs/changelog.rst", "NEWS"); a sentence ("every change needs a fragment") is not one
  if [ -n "$v" ] && { case "$v" in */*|*.*) true ;; *) printf '%s' "$v" | grep -qE '^[A-Z][A-Z_-]+$' ;; esac; }; then
    printf 'rule\t%s\tadd one line to the section for unreleased changes at the top of %s (it may be called "Unreleased", "dev", "main" or carry the next version; create the file, or "Unreleased", only if there is none), in the style the file already uses\n' "$v" "$v"
    return; fi
  if [ -d "$r/.changeset" ]; then
    printf 'fragments\t.changeset/\tadd a changeset: a new .changeset/<name>.md with the package bump and one user-facing sentence (npx changeset)\n'; return; fi
  if [ -f "$r/towncrier.toml" ] || grep -qs '^\[tool\.towncrier' "$r/pyproject.toml"; then
    printf 'fragments\ttowncrier\tadd a news fragment where the towncrier config says (one user-facing sentence); never edit the generated changelog\n'; return; fi
  for f in changelog.d newsfragments .changes changelogs/fragments releasenotes/notes docs/releases docs/release-notes docs/release_notes; do
    [ -d "$r/$f" ] && { printf 'fragments\t%s/\tadd the change to the release notes in %s/ the way the existing files do it (the upcoming version'"'"'s file, or a new fragment)\n' "$f" "$f"; return; }
  done
  for f in release-please-config.json .release-please-manifest.json .releaserc .releaserc.json .releaserc.yml .releaserc.yaml release.config.js release.config.cjs cliff.toml .github/release-drafter.yml .github/release.yml; do
    [ -f "$r/$f" ] && { printf 'generated\t%s\trelease notes are generated from commit messages or PR titles: write a clear conventional commit message / PR title (feat:, fix:…); do not edit a changelog by hand\n' "$f"; return; }
  done
  # a CI workflow that rewrites the changelog (laravel/laravel: update-changelog.yml)
  for f in "$r"/.github/workflows/*changelog*.y*ml "$r"/.github/workflows/*release-notes*.y*ml; do
    [ -f "$f" ] && { printf 'generated\t%s\tthe changelog is updated by the %s workflow at release time: write a clear commit message and PR title; do not edit it by hand\n' "${f#"$r"/}" "${f##*/}"; return; }
  done
  # np and release-it publish release notes on GitHub Releases, written at release time
  if grep -qsE '"(np|release-it)"[[:space:]]*:' "$r/package.json" || [ -f "$r/.release-it.json" ]; then
    printf 'generated\t%s\trelease notes are written on GitHub Releases at release time: write a clear commit message and PR title; do not create a changelog file\n' "$(grep -qs '"np"' "$r/package.json" && echo np || echo release-it)"; return; fi
  for f in CHANGELOG.md CHANGELOG.rst CHANGELOG.txt CHANGELOG changelog.md Changelog.md CHANGES.md CHANGES.rst CHANGES HISTORY.md HISTORY.rst NEWS.md NEWS.rst NEWS; do
    [ -f "$r/$f" ] || continue
    if cl_generated "$r/$f"; then
      printf 'generated\t%s\t%s is generated: write a clear conventional commit message instead; do not edit it by hand\n' "$f" "$f"; return; fi
    printf 'file\t%s\tadd one line to the section for unreleased changes at the top of %s (it may be called "Unreleased", "dev", "main" or carry the next version; create "Unreleased" only if there is none), in the style the file already uses, keeping any placeholder line it carries — unless CONTRIBUTING or AGENTS.md says the changelog is written at release time\n' "$f" "$f"; return
  done
  # monorepo: one changelog per package (vite: packages/vite/CHANGELOG.md, packages/create-vite/…)
  f="$(cd "$r" && ls -d packages/*/CHANGELOG.md apps/*/CHANGELOG.md libs/*/CHANGELOG.md crates/*/CHANGELOG.md modules/*/CHANGELOG.md 2>/dev/null | head -n 1)"
  if [ -n "$f" ]; then
    if cl_generated "$r/$f"; then
      printf 'generated\t%s\teach package has its own changelog (%s, …), generated at release time from commit messages: write a clear conventional commit message whose scope names the package or area; do not edit the changelogs by hand\n' "${f%%/*}/*/CHANGELOG.md" "$f"
    else
      printf 'file\t%s\teach package has its own changelog (%s, …): add one line to the unreleased section of the changelog of the package you changed, in the style it already uses\n' "${f%%/*}/*/CHANGELOG.md" "$f"
    fi; return; fi
  printf 'none\t-\tthis project has no changelog: ask the user once whether to create CHANGELOG.md ("# Changelog", then "## Unreleased") or whether release notes live elsewhere (GitHub Releases, a website), and record the answer in index.md Rules as "- Changelog: CHANGELOG.md" or "- Changelog: none (<where release notes live>)"\n'
}
