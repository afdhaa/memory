# Changelog

All notable changes. Versions follow [semver](https://semver.org): minor for new features,
patch for fixes and reorganisation.

## 3.9.0
Tested on three real repositories (Node/Express + Prisma, Go/Gin, FastAPI + React monorepo).
- Scan: sub-packages of monorepos (`backend/`, `frontend/`…) with their frameworks and commands;
  lock files at the repo root are honoured; shell scripts in `scripts/` folders are listed.
- Scan: the README title is taken from image headings (alt text); the summary comes from the first
  real paragraph or tagline blockquote, skipping lists and "…:" intros, with a manifest fallback;
  markdown links are stripped.
- Scan: docs list covers any README spelling and root-level guides (development.md…), and skips
  AGENTS.md/CLAUDE.md that only hold the skill's block; recently active areas omit deleted paths;
  a `.env` committed to git is reported as such; image folders are left out of Key facts.
- `mem.sh review` only matches the source marker of an entry (no false positives from prose);
  `search` skips the generated scan block and returns 12 shortened lines; lint says when user
  memory is missing.
- SKILL.md: where user rules go (project Rules, area directives, user memory), a Rule format with
  tags and `@path`, contract vs `#hold`, what reading code can verify, when to rewrite progress,
  newest-first decisions with the marker on the title line, and pointing to existing docs instead
  of copying them.

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
