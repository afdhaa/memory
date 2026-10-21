# Changelog

All notable changes. Versions follow [semver](https://semver.org): minor for new features,
patch for fixes and reorganisation.

## 3.8.1
- MIT license and this changelog.
- The installer's closing message is in English.
- Selftest checks that `package.json` (when present) and SKILL.md carry the same version.

## 3.8.0
- Write mode: `auto` (default) or `confirm`, set with `mem.sh mode` or the line
  `- Memory writes: …` in `index.md` (project) or `user.md` (global). In confirm mode the user's
  own instructions are written at once; the agent's own conclusions are proposed as a numbered list
  and written only when approved. Unanswered proposals wait in `inbox.md`.
- Lint treats pending proposals as info, not an issue.

## 3.7.1
- SKILL.md shortened (353 → 272 lines); the full writing guide, examples and templates moved to
  `references/writing.md`, read once per session before writing.
- "One paragraph per line" rule so prompt recall never returns fragments.
- README: memory structure tree and an annotated entry.

## 3.7.0
- Agent-written entries start as `(agent, seen: 1, unconfirmed)` until the user confirms them,
  they recur, or they are verified; decisions the agent made itself need the user's approval.
- `mem.sh review` lists unconfirmed entries; lint flags those older than 30 days.

## 3.6.0
- `topics/codebase.md` gains an agent-written "Project layout" section; the scan lists subfolders.
- `.memory/README.md` explains each memory file to teammates.
- Entries are tagged with the user's own words when they write in another language.

## 3.5.0
- Memory is written in English by default (`Memory language:` overrides it).
- Anti-slop rules; lint flags filler and marketing words.
- `topics/codebase.md` gains an agent-written "How it fits together" section; the scan output is
  written as sentences.

## 3.4.0
- Writing-style guide: full-sentence titles, `Why:` / `Do instead:`, concrete details.
- Clearer formats for gotchas, decisions, topics, procedures and progress.

## 3.3.x
- `mem.sh scan` indexes a repo into `topics/codebase.md`; fixes from review.

## 3.2.1
- First public version: shared Markdown memory, hooks for Claude Code and Codex, lint, secret check.
