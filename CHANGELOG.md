# Changelog

All notable changes. Versions follow [semver](https://semver.org): minor for new features,
patch for fixes and reorganisation.

## 4.1.0
- New `mem.sh doctor` (also `npx team-memory doctor`): checks the install in a project and says
  how to fix each problem: skill copies and their versions, global copies, Claude Code and Codex
  hooks, the AGENTS.md/CLAUDE.md block, the pre-commit secret check, gitignored personal files,
  `merge=union`, and leftovers of the old name `project-memory`. Read-only; exits 1 when something
  is broken.
- CI and the publish workflow use `actions/checkout@v7` and `actions/setup-node@v7` (Node 24), and
  fail early when the package name in `package.json` is not `team-memory`.

## 4.0.0
The skill is renamed from `project-memory` to `team-memory`, the same name as the npm package and
the repository. Nothing in `.memory/` changes.
- New paths: `.agents/skills/team-memory/` (and `.claude/skills/team-memory`), hook messages start
  with `[team-memory]`, backups go to `.git/team-memory-backup/`.
- Upgrading: run `npx team-memory@latest` in the project. The installer removes the old
  `project-memory` skill folders (only when their SKILL.md says `name: project-memory`), replaces the
  old hooks, AGENTS.md/CLAUDE.md block and pre-commit block instead of adding a second copy, and
  updates the paths in `.memory/README.md`. `--global` removes the old global copies.
- skills.sh users: `npx skills remove project-memory`, then `npx skills add afdhaa/team-memory`.
- Unchanged: `PM_*` environment variables and the script names (`pm-hook.sh`, `mem.sh`).

## 3.15.0
From a 20-session test: one project, each session a fresh agent that knew only `.memory/`. Memory
grew from 169 to 227 lines, lint stayed clean, no duplicates, and every knowledge check (14
questions in sessions 7, 14 and 20) was answered correctly from memory. Fixes for what it found:
- `progress.md` stays a state, not a log: the template has a "Done recently" section of at most 5
  lines, the writing guide says to drop items that are done or no longer true, and lint warns above 5.
- Correction capture: "wajib", "mulai sekarang", "from now on", "must always/never" count as standing
  instructions; "jangan lupa", "don't forget" and "never mind" inside a task request no longer do.
- Prompt recall ranks rules, decisions and gotchas above overview prose (`topics/codebase.md`,
  topic paragraphs), and injects at most one prose line per message.
- SKILL.md: thanks or praise for the work ("mantap") is not approval of an entry the agent recorded;
  evidence in `Why:` names how something was checked, not numbers that change every commit.
- Scan: files deleted but not yet staged are left out; "has 1 file" wording.

## 3.14.3
- Descriptions: SKILL.md (shown on skills.sh and read by agents) now opens with what the skill is,
  and stays under the 1,024-character limit; the npm description says what is remembered and where.
- README: installing from skills.sh (`npx skills add afdhaa/team-memory`) and what it leaves out (hooks,
  secret check, AGENTS.md block); official sources include the skills.sh listing and npm provenance.
- CI: jobs stop after 20 minutes, and a new push cancels the previous run.
- The repository is now github.com/afdhaa/team-memory (the old URL redirects), so npm, skills.sh and
  GitHub all use the same name.

## 3.14.2
- Fixes from two audits (lifecycle and portability), each with a regression test:
  - Installer: works again outside git (re-install and `--remove-hooks` stopped half-way); keeps an
    `AGENTS.md` symlink; refreshes the block in CRLF files and keeps their line endings; puts the
    secret check into `.husky/pre-commit` for husky 9 (not the regenerated `.husky/_`); leaves fish
    or other non-sh hooks alone; adds missing template files to an existing `.memory/`; keeps the
    first backup of `settings.json`; recognises `@AGENTS.md` anywhere in `CLAUDE.md`;
    `--remove-hooks` deletes files it left empty; `--version`, usage on unknown options.
  - Hooks: a symlinked `.memory` works (search, recall, `#hold`); control characters in memory no
    longer break the JSON; a capture into an inbox without a final newline is not lost, and a
    read-only `.memory` is reported; planted-text warnings work with spaces in the project path;
    new files with non-ASCII names count for the stop reminder; CRLF memory files keep working;
    non-UTF-8 bytes no longer hide user memory; the state folder must belong to the current user.
  - `mem.sh`: `@path` patterns are checked the same way everywhere (`pm-hit.awk`, `**/` matches zero
    or more folders), so bash 3.2 no longer reports `**` tags as matching nothing; secrets are found
    in a symlinked `.memory`; lint flags a missing `index.md` and handles a `.memory` submodule;
    unknown commands exit 1.
- Fixes found by the first CI run, all invisible on the Linux/mawk machine used so far:
  - macOS (bash 3.2): `scan.sh` and the prompt hook failed to parse (`case` patterns inside `$( )`
    need a leading parenthesis there), so the scan, prompt recall and parts of the installer broke.
  - gawk: `@path` matching used a bracket expression gawk rejects, so `#hold` and path-tagged entries
    did nothing; the scan named an array `RT`, which gawk reserves, and lost the Node frameworks.
- CI: the self-test runs on every push and pull request on Linux (bash 5 with mawk and with gawk)
  and on macOS with the system bash 3.2 and BWK awk.
- Releases: pushing a `v*` tag publishes to npm from GitHub Actions with trusted publishing and
  provenance (no npm token stored); the tag, `package.json` and SKILL.md must carry the same version.
- Installer guards: refuses to install in the home folder; in a subfolder of a git repository it asks
  first (`--here` skips the question, for one package of a monorepo); says when the folder is not a
  git repository. The banner shows the package name and version.

## 3.14.1
- README rewritten as the npm page: what it is and a quick start first, `npx team-memory` everywhere,
  stale parts removed (omp registry placeholder, `.bak` backups, clone paths).

## 3.14.0
- Published on npm as `team-memory`: `npx team-memory` installs into the current project
  (`--global`, `--no-hooks`, `--remove-hooks`, `selftest`, `--version`); README install section rewritten.
- SKILL.md rewritten for the everyday loop: 341 → 145 lines (3,900 → 1,550 words), read at every
  task. Onboarding, re-scans, confirm mode, inbox triage, clean-up, user commands, team use and hook
  details moved to `references/workflows.md`, read only when needed. The Capture table now also
  covers freezes, contracts and stale `topics/` sentences; confirm mode's write/propose split is
  back in SKILL.md, since agents need it on every turn.
- Tested on chalk, cors, cobra, requests, serde_json and laravel/laravel with four agent sessions:
  - Hooks: prompt recall no longer repeats `index.md` lines the session start showed; the edit hook
    keeps its own list, so a rule a prompt already showed still appears before the edit; session
    start warns about planted text in any memory file, also entries without `@path`; a question
    such as "what do you remember…?" is not captured as a correction; long paragraphs are cut in
    recall; in confirm mode the onboarding text is proposed, and a declined section gets
    `Not needed: <reason>`.
  - Changelog: a CI workflow that updates the changelog (laravel's `update-changelog.yml`) counts
    as generated; the unreleased section may be called "dev" or "main"; placeholder lines are kept.
  - SKILL.md: Rule reasons and placement, `user.md` creation and format, the global-vs-project
    tie-break, source markers for approved proposals and user-requested decisions, `*` inside a
    file name, where to park an unanswered changelog question.
  - Lint's advice on planted instructions matches SKILL.md (agents tell the user; people remove it).
  - "complete index.md from the scan" approves the whole onboarding in confirm mode; common filler
    words ("only", "first", "check") no longer drive prompt recall; the scan marks web frameworks
    found only in devDependencies as "(dev only)".

## 3.13.0
Tested on six small repositories (slugify, itsdangerous, cast, itoa, phpdotenv,
the-art-of-command-line), with two full agent sessions (auto and confirm mode).
- Small repos (under 40 files): onboarding asks for 1–2 paragraphs and no "Project layout"; lint
  stops asking for it. A section the user declined holds `Not needed: <reason>`.
- Hooks: rules added to `index.md` during a session are recalled by prompts; session start leaves
  template comments out; the capture nudge sends whole-project rules to `index.md` and freezes to
  `decisions.md` with `#hold`; in confirm mode the changelog line is written with the code, not proposed.
- Changelog: projects released with np or release-it keep notes on GitHub Releases (no file is
  created); the question for projects with nothing also offers "release notes live elsewhere";
  `- Changelog: none; …` is read correctly.
- Scan: the manifest description is used when the README's first line is very short; reference
  links and language-selector lines are cleaned; `README-*` translations are one entry after
  `README.md`; `test.js` counts as a test; "1 file" wording; commits by bots (dependabot,
  renovate, pre-commit-ci) are left out of "Recently active areas"; `vendor-bin/` is not a package.
- SKILL.md: a direct request to write something is its approval in confirm mode; how to mark a
  decision the user asked for but the agent designed; fix `topics/` sentences a change made wrong;
  holds are file- or folder-level; point to `docs/` instead of repeating it.
- Lint flags "several", "numerous", "a variety of".

## 3.12.0
- Team mode removed (`mem.sh team`, the `Team mode:` rule and its hook message). With `progress.md`
  personal and finished work in the project's changelog, it no longer solved a problem. Agent
  entries are confirmed as before (user approval, recurrence or evidence); a `- Team mode:` line
  left in `index.md` is ignored and can be deleted.

## 3.11.0
Tested on six large open-source repositories (next.js, django, home-assistant, ruff, langchain,
supabase), with a security review.
- Installer: when `.claude/skills` and `.agents/skills` are one folder through a symlink (next.js,
  supabase, home-assistant), it no longer deletes the fresh copy and copies the whole skill
  repository, `.git` included, into the project; re-running it repairs such installs. Backups of
  `settings.json`/`hooks.json` go into `.git/`, not the working tree; install messages show
  project-relative paths.
- Secret check: Stripe, Google API, GitLab, npm, PyPI, GitHub fine-grained tokens, Slack webhooks,
  SendGrid, Twilio, `user:password@` in URLs and `KEY=value` pairs in any case (`DB_PASSWORD=…`,
  `aws_secret_access_key = …`); inbox redaction covers the same formats.
- Prompt injection: hooks present memory as information, not orders, and warn when injected
  memory reads like planted instructions; `mem.sh lint` reports such entries as issues and notes
  downloads piped into a shell; SKILL.md tells agents to report them instead of acting on them or
  deleting them silently.
- `progress.md` is personal and gitignored: each person's agent tracks its own work, so branches
  never conflict on it (a copy committed earlier: `git rm --cached .memory/progress.md`; installer
  and lint remind you). Finished, user-visible work goes to the project's changelog the way the
  project keeps it — existing changelog, changesets/towncrier/release-notes folder, or notes
  generated from commits; with none, the agent asks once and records the answer as a Rule.
  `mem.sh changelog` shows which; the stop hook reminds the agent.
- Team mode (`mem.sh team on`): agent entries confirmed only by a teammate's review, rules record
  who gave them.
- Scan: the largest sub-packages instead of the first eight alphabetically, skipping examples,
  benchmarks and templates; "Recently active areas" no longer counts the edge commit of a shallow
  clone; a project is not listed as its own dependency; reStructuredText substitutions removed from
  the title; `.txt`/`.adoc` docs counted; `tests/runtests.py` detected; one version per dependency.
- README: Security and privacy section (no network access, what reaches the model provider,
  CODEOWNERS for memory and hooks) and team mode.

## 3.10.0
Tested on five production repositories (excalidraw, koel, caddy, ripgrep, saleor).
- Installer: never replaces a `CLAUDE.md` symlink (3.9.0 turned it into a copy) and restores one
  that an earlier install converted; a new `CLAUDE.md` imports `@AGENTS.md`, so Claude Code also sees
  the project's own instructions; a broad `.gitignore` rule (`.*`) no longer hides `.memory/` and the
  skill from the team; warns when hook files are ignored.
- `@path` patterns: `*` (one folder level) and `**` (any depth), for search, edits, `#hold` and lint.
- Scan: npm scripts ranked (dev, start, build, test, lint first), lifecycle and "removed" stubs
  skipped, 12 at the root and 3 per sub-package; packages without a framework collapsed to one line;
  conventional Go/Rust commands only at the root; Poe tasks and Django `manage.py`; commands run
  through uv/Poetry/PDM; agent instructions in sub-folders; badges and HTML dropped from the title
  and summary; tool folders and one-file subfolders left out of the layout; long env lists capped.
- `mem.sh`: search ranks entries over long paragraphs and skips bare headings; lint warns when
  `.memory/` is gitignored and notes empty onboarding sections; stats ignores template comments.
- SKILL.md: the project's own AGENTS.md comes first (no copies, conflicts are asked), mixed-source
  entries, where evidence goes, Rule placement, when to read `references/writing.md`.

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
