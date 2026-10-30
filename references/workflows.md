# Workflows — read the section you need

SKILL.md has the everyday loop. This file holds the less frequent workflows. Paths to scripts are
relative to the skill folder (`.agents/skills/team-memory/`).

## New project, or a re-scan

No `.memory/` anywhere up the tree: from the project root run `bash scripts/mem.sh scan`. It creates
`.memory/` from the templates and indexes the repo into `topics/codebase.md`. Then:

1. Read `topics/codebase.md`, the README and the main entry points.
2. Write the Project summary in `index.md`: 3–5 plain sentences a newcomer understands (what the
   project is, who uses it, what stage it is in). Correct Key facts if needed.
3. In `topics/codebase.md` write **"How it fits together"** (3–6 paragraphs: main parts, how a request
   or job flows through the code, where to start reading) and **"Project layout"** (one line per
   folder: what lives there, where new code goes). Templates: `references/writing.md`. Write only
   what you read in the code, and say when something is unclear.
   **Before saving, check your own text:** every sentence with "all", "each", "every", "only" or
   "one X per Y" against a file listing or `grep` (name the exceptions, or rewrite it as what you
   saw); every sentence you took from the docs against the code (they agree: point to the doc
   instead; they differ: write what the code does, plus an `(agent, unconfirmed)` note on the
   mismatch). Key facts stay one line each and do not repeat what `codebase.md` or a Rule says.
   Then run `mem.sh lint` and act on every `checked every case?` note: confirm the sentence with a
   listing or `grep`, or rewrite it.
   **Small repo** (under ~40 files): 1–2 paragraphs; leave "Project layout" out when the generated
   Layout already says it all.
4. When the repo already documents its layout, commands, endpoints or design (AGENTS.md, CLAUDE.md,
   `docs/`), point to it ("How signing works: see docs/signer.rst") and write only what it lacks.
5. If the user does not want a section, write `Not needed: <reason>` in it so nobody asks again.
6. Tell the user in one line.

Do the same when `index.md` has no Project summary or a `codebase.md` section is still empty.
Re-run the scan when lint says it is out of date or after big structural changes: it only rewrites
its own block (between `scan:start` and `scan:end`). If it shows structural changes, update "How it
fits together" and "Project layout" too.

## Inbox triage

`inbox.md` holds user remarks captured by the prompt hook (secrets redacted) and, in confirm mode,
proposals the user has not answered (`proposed →` lines; ask before writing those). For each item:
if durable, record it where the Capture table in SKILL.md says, rewritten as a clear entry — never
the raw remark. If it is recorded already, a one-off, or not a correction, drop it. Then empty the
file and report: `📝 inbox: 2 recorded, 3 dropped`.

When unsure whether a preference is for this project or every project, keep it in the project and
ask once. Never copy project secrets, private system names or client data into `user.md`.

## Confirm mode

Set by `- Memory writes: confirm` in `index.md` Rules (this project, wins) or `user.md` (every
project). Switch only when the user asks: "mode konfirmasi" / "ask before saving memory" →
`mem.sh mode confirm`; "mode otomatis" → `mem.sh mode auto`; `--global` for every project.

- **Write directly** — the user's own words are the approval: "remember / ingat / catat / forget",
  corrections and standing instructions ("jangan…", "selalu…"), recorded as `(user, …)`. A direct
  request to write something approves exactly that; "complete index.md from the scan" approves the
  whole onboarding (summary, Key facts and the `codebase.md` sections).
- **Also write directly** — not memory: `progress.md` (personal) and the changelog line (part of the
  code change). Mention them.
- **Propose** your own conclusions: gotchas, decisions, topics, procedures, `codebase.md` sections.
  When the user declines a section, writing `Not needed: <reason>` in it is their answer, not a proposal.
  Do the task first; at its end, one numbered list with the target file and the exact entry for
  each, then ask: *"Save? Reply 'all', '1,3', '2: <change>' or 'none'."*
- Write only what is approved, exactly as approved, without `unconfirmed`.
- No answer: save each item as one line in `inbox.md`
  (`- YYYY-MM-DD · proposed → gotchas.md: **Title…** Why: … Do instead: …`) and ask again at the
  next session start. Never write them without a yes.
- Reporting line: `📝 memory: 3 proposed (waiting for your answer)`.

## Clean-up

When lint reports issues, `index.md` passes ~150 lines, a file passes ~300 lines, or the user says
"rapikan memori":
1. Merge duplicates (they also appear after a `merge=union` merge of two branches).
2. **Missing @path**: the code moved or was deleted — update the path or retire the entry.
3. **Stale?** (old, seen once, not surfaced by hooks lately): check against the code; update,
   confirm or remove. Ask the user if unsure.
4. Fold related entries into `topics/<area>.md`; promote recurring lessons; demote outdated rules;
   rewrite cryptic or padded entries per `references/writing.md`; translate to the memory language.
5. Go through `mem.sh review`: confirm what holds, remove what does not.
6. Refresh the map in `index.md`, empty `inbox.md`, re-run lint until clean, report the changes.

## User commands

| User says | Do |
|---|---|
| "remember / ingat / catat …" | Record now (project scope), confirm in one line. |
| "… untuk semua project / everywhere" | Record in `~/.agents/memory/user.md`, confirm. |
| "forget / lupakan …" | Remove it (strike through a decision), confirm. |
| "undo / batalkan catatan terakhir" | Show the entries you wrote last (`git diff -- .memory`, or this session's writes), remove what the user points to, confirm in one line. |
| "what do you know about X" | `mem.sh search X`, summarise with file references. |
| "freeze / hold / jangan sentuh <area>" | Decision with `@path #hold`. A hold covers whole files or folders; to protect one class or function, write a Rule naming it and say so. "unfreeze" removes `#hold`. |
| "<output/API/format> must not change" | `index.md` Rule with `@path`, no `#hold`: the code may change while the contract holds. |
| "update memory" | Capture for the whole session, plus inbox triage. |
| "mode konfirmasi" / "mode otomatis" | `mem.sh mode confirm` / `auto`, confirm in one line. |
| "review memory / cek memori" | `mem.sh review`; show each unconfirmed entry in one line; keep, fix or drop as answered. |
| "rapikan memori / clean up memory" | Clean-up, then report. |
| "scan ulang / rescan" | `mem.sh scan`, then update the summary, Key facts and `codebase.md` sections if needed. |
| "jangan dicatat / don't save this" | Don't write it; remove it from the inbox. |

## Team use

Commit `.memory/` following the project's own commit and PR conventions; review it in PRs like code.
The installer sets `merge=union` for `decisions.md` and `gotchas.md` (run lint after a merge for
duplicates), gitignores the personal files and adds a pre-commit secret check.

## Hooks in detail

- **Session start / after compaction:** `index.md`, `progress.md`, `user.md`, plus notes about an
  inbox to triage or onboarding sections still empty.
- **Each prompt:** the best-matching entries (keyword ranking, each shown once per session); a prompt
  that looks like a correction is captured into `inbox.md` with a reminder to record it. Cursor and
  Copilot capture only: their prompt hooks cannot add context.
- **Before an edit:** entries tagged for that file (Gemini CLI and Cursor: right after the edit; Copilot:
  none). A `#hold` area needs the user's approval: Claude Code shows a prompt; Codex, Gemini CLI,
  Cursor and Copilot block the edit — ask, and only after a clear yes run `mem.sh approve <path>`
  (60 minutes), then retry.
- **Before stopping:** files changed but memory didn't → one reminder (memory, progress, changelog).
  If nothing is worth keeping, end with `memory: nothing new`.
