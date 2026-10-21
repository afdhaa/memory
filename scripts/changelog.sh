#!/usr/bin/env bash
# project-memory: how this project records changes for its users — sourced by mem.sh, scan.sh and the hooks.
#   changelog_info <project-root>  →  "<kind>\t<file, folder or tool>\t<what an agent should do>"
# kind: rule (index.md says), fragments (changesets, towncrier, release-notes folder…), generated (from commits
# or PR titles), file (an existing changelog), none (nothing found: ask the user, never create one unasked)
changelog_info() {
  local r="${1:-.}" f v
  # the user's answer, recorded once in index.md Rules: "- Changelog: CHANGELOG.md" / "- Changelog: none"
  v="$(sed -n 's/^[[:space:]]*[-*][[:space:]]*[Cc]hangelog:[[:space:]]*`\{0,1\}\([^`[:space:]]*\).*/\1/p' "$r/.memory/index.md" 2>/dev/null | head -n1)"
  if [ -n "$v" ]; then
    case "$v" in none|no|-) printf 'rule\tnone\tthis project keeps no changelog (index.md Rules): record nothing\n' ;;
      *) printf 'rule\t%s\tadd one line under an "Unreleased" section at the top of %s (create the file or the section if missing), in the style the file already uses\n' "$v" "$v" ;; esac
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
  for f in CHANGELOG.md CHANGELOG.rst CHANGELOG.txt CHANGELOG changelog.md Changelog.md CHANGES.md CHANGES.rst CHANGES HISTORY.md HISTORY.rst NEWS.md NEWS.rst NEWS; do
    [ -f "$r/$f" ] || continue
    if head -n 15 "$r/$f" | grep -qiE 'auto(matically)?[- ]generated|do not edit|semantic-release|release-please|git-cliff'; then
      printf 'generated\t%s\t%s is generated: write a clear conventional commit message instead; do not edit it by hand\n' "$f" "$f"; return; fi
    printf 'file\t%s\tadd one line under an "Unreleased" section at the top of %s (create the section if it is missing), in the style the file already uses — unless CONTRIBUTING or AGENTS.md says the changelog is written at release time\n' "$f" "$f"; return
  done
  printf 'none\t-\tthis project has no changelog: ask the user once whether to create CHANGELOG.md ("# Changelog", then "## Unreleased"), and record the answer in index.md Rules as "- Changelog: CHANGELOG.md" or "- Changelog: none"\n'
}
