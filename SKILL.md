---
name: project-memory
description: Persistent project memory in plain Markdown — `.memory/` at the repo root plus personal `~/.agents/memory/user.md` — shared by every coding agent. Use at the START of every task (recall rules, decisions, gotchas, progress; triage `.memory/inbox.md`), on each NEW REQUEST (search related memory), BEFORE EDITING an area (check entries tagged for that path), and BEFORE FINISHING (record decisions, user corrections, gotchas, procedures, progress). In a new project without `.memory/`, index the repo first (`mem.sh scan`). Also use when the user says "remember this", "ingat ini", "catat", "jangan lupa", "untuk semua project", "forget that", "lupakan", "what do you know about X", "apa yang sudah kita putuskan", "update memory", "review memory", "cek memori", "rapikan memori", "scan project", "scan ulang", "freeze/hold this area", corrects how you did something, or a message starts with "[project-memory]". Trigger even if memory is not mentioned whenever the repo has a `.memory/` folder.
metadata:
  version: 3.7.0
---

# Project Memory (v3.7)

Every coding agent working in this repo shares one long-term memory, kept as Markdown.
No server, no database: the files are the memory, `scripts/mem.sh` and `grep` are the
search engine, git is the history.

**Purpose:** the next session must not re-learn what an earlier session already learned.
Write an entry only if it will save a future agent time or prevent a future mistake.

## Layout

```
.memory/                      # committed — shared with the team
├── README.md       # For people: what each memory file is for. Documentation, not memory.
├── index.md        # ALWAYS read. Summary, rules (max ~15), key facts, map. ≤ ~150 lines.
├── progress.md     # Current state: in progress / next / blocked. Rewritten, never appended.
├── decisions.md    # Why things are the way they are. Newest first. Reversed ones kept, struck through.
├── gotchas.md      # Curated runbook by category, priority-sorted, max 10 per category, each with "Do instead".
├── topics/         # Deeper knowledge per area (auth.md, deploy.md …) — the project wiki.
│   └── codebase.md # "How it fits together" + "Project layout" (written by you) + generated repo facts from `mem.sh scan`.
├── procedures/     # Step-by-step workflows that worked and will be repeated.
├── local.md        # gitignored: personal notes for this project.
├── inbox.md        # gitignored: user remarks auto-captured by hooks, waiting for triage.
└── .stats.tsv      # gitignored: which entries hooks surfaced, and when (used to find stale memory).

~/.agents/memory/user.md      # personal, all projects: communication & coding preferences (≤ ~40 lines)
```

Layers: `user.md` = persona, `index.md` = project core, `topics/` = scenarios,
`decisions.md` + `gotchas.md` = atomic facts, `procedures/` = reusable skills.
Raw conversations are never stored.

Helper (path relative to this SKILL.md; works from anywhere inside the repo):
- `bash scripts/mem.sh search <words…>` — ranked search (project memory + user memory)
- `bash scripts/mem.sh path <file>` — entries tagged for a file or folder
- `bash scripts/mem.sh lint` — sizes, caps, secrets, map gaps, missing @paths, stale and duplicate entries, filler words
- `bash scripts/mem.sh review` — unconfirmed agent entries waiting for the user, oldest first
- `bash scripts/mem.sh stats` — counts per file and hook usage
- `bash scripts/mem.sh scan` — index the repo: writes the generated facts block of `topics/codebase.md`,
  adds it to the Map and fills `index.md` Key facts while empty. Never reads `.env` values.
- `bash scripts/mem.sh approve <path> [minutes]` — lift a `#hold` temporarily, only after the user approves
- `bash scripts/selftest.sh` — verify the installation works on this machine

**New project** (no `.memory/` anywhere up the tree): from the project root run
`bash scripts/mem.sh scan` — it creates `.memory/` from the templates and indexes the repo. Then:
1. Read `topics/codebase.md`, the README and the main entry points.
2. Write the Project summary in `index.md`: 3–5 plain sentences a newcomer understands (what the
   project is, who uses it, what stage it is in). Correct Key facts if needed.
3. Write the **"How it fits together"** section at the top of `topics/codebase.md`. The scan only
   lists facts (stack, commands, folders); this section explains them, in 3–6 short paragraphs of
   full sentences: what the code does and its main parts; how a typical request or job flows through
   it (entry point → … → storage/output), naming real files and folders; where to start reading;
   conventions or design choices that are not obvious from the file names. Write from what you read
   in the code — never guess — and say so when something is unclear.
4. Write the **"Project layout"** section of `topics/codebase.md`: one line per folder (or root
   file) a newcomer needs, saying what lives there and where new code of that kind goes, e.g.
   ``- `src/services/` — business logic (pricing, catalogue, supplier sync); new features start here.``
   Take the folder list from the generated Layout; skip folders nobody edits (build output, vendored code).
5. Tell the user in one line.

Do the same when `index.md` has no Project summary or `codebase.md` has an empty "How it fits
together" or "Project layout" yet. Re-run the scan when lint says it is out of date or after big structural changes;
it only rewrites its own block (between `scan:start`/`scan:end`), so everything you write outside
it stays. After a re-scan that shows structural changes, update "How it fits together" and "Project layout" too.

## Hooks (if installed)

In Claude Code and Codex, hooks do part of this automatically. Messages starting with
`[project-memory]` come from them — treat them as instructions from this skill:
- **Session start / after compaction:** `index.md`, `progress.md` and `user.md` are injected,
  plus a note if `inbox.md` has items to triage or the Project summary is still empty.
  Don't re-read what was injected.
- **Every user prompt:** the most relevant memory entries for that prompt are injected
  (ranked keyword match). If the prompt looks like a correction or standing instruction, it
  is also captured in `inbox.md` and you are asked to record it.
- **Before an edit:** entries tagged with that file's `@path` are injected; `#hold` areas
  require the user's approval. Claude Code shows an approval prompt. Codex blocks the edit
  instead: ask the user, and only after they clearly approve in chat run
  `bash scripts/mem.sh approve <path>` (valid 60 min), then retry. Never approve on your own.
- **Before stopping:** if files changed but memory didn't, you get one reminder. Record what
  is worth keeping, or end with `memory: nothing new` without editing anything.

Without hooks (OpenCode, Antigravity, or `PM_HOOKS=off`), do all of the below yourself.

## 1. Recall

1. Start of a task: read `.memory/index.md`, `.memory/progress.md` and `~/.agents/memory/user.md`
   if it exists (skip what was injected). If `inbox.md` has items, triage them first (§2).
2. New request: `mem.sh search <2–4 keywords from the request>` (skip if a hook injected matches).
   Open `topics/` or `procedures/` files from the map when relevant.
3. **Before editing in an area**, `mem.sh path <file-or-dir>` (skip if injected). A recorded
   decision beats your assumption; if you think it is outdated, ask — don't silently override it.
4. If an entry for the area is tagged `#hold`, ask the user before changing anything there
   (without hooks, too). If they approve, `mem.sh approve <path>` records it for 60 minutes.
5. An entry marked `unconfirmed` is a lead, not a fact: check it against the code before you rely
   on it. If it holds, confirm it; if it is wrong, correct or remove it (see *Confidence*).

## 2. Capture

Write **immediately** — not only at the end — when:

| Event | Where |
|---|---|
| User corrects you or states a preference **for this project** | `gotchas.md` → "User directives" (or `index.md` Rules if project-wide) |
| User states a preference **for every project** ("selalu", "di semua project", "always") | `~/.agents/memory/user.md` |
| A decision is made (library, design, "don't touch X") | `decisions.md`, with the reason |
| Something non-obvious bit you (setup step, flaky test, misleading name) | `gotchas.md` |
| A multi-step workflow succeeded and will recur | `procedures/<name>.md` |
| Substantial knowledge about one area | `topics/<area>.md` (+ add it to the map) |
| End of every task | rewrite `progress.md` |

When unsure whether a preference is project-only or global, keep it in the project and
ask once. Never copy project secrets, names of private systems or client data into `user.md`.

### Inbox triage

`inbox.md` holds raw user remarks captured by the prompt hook (secrets redacted). For each
item: if durable, record it in the right place (table above), rewritten as a clear,
self-contained entry (see *Writing style*) — never paste the raw remark. If it is already
recorded, a one-off, or not a correction, drop it. Then delete the triaged items (empty the file). Report in one line, e.g. `📝 inbox: 2 recorded, 3 dropped`.

### The filter

Ask: *"Would a fresh agent next week waste time or make a mistake without this?"*
Do NOT store: what is obvious from code/README/`git log`; session narration; one-off
events with no lesson; speculation. **Never store secrets** (keys, tokens, passwords,
connection strings, personal data) — write *where* they live (`.env` → `KP_BEARER`),
never the value. If you find one in memory, delete it and tell the user to rotate it.
A git pre-commit check blocks commits that put secrets into `.memory/`.

### Writing style — write for a teammate, not for a parser

Memory is read by people (teammates reviewing `.memory/` in a PR, the user checking what you
know) as much as by agents. An entry that only its author can decode is worthless next month.
Every entry must make sense to someone who was **not** in this session and does not know the code yet.

1. **Lead with the point, in plain words.** The bold title is a complete statement a reader can act
   on: "Integration tests hang unless the database container is running", not "int tests hang (db)".
2. **Say what, why, and what to do.** What happens or was decided → why (cause, constraint, who asked)
   → what to do instead. The reason is what lets a future reader judge whether the entry still holds.
3. **Full sentences, no private shorthand.** No telegraphic fragments ("db flaky, retry"), no
   abbreviations you invented, no arrows or symbols in place of verbs. Explain a domain term or a
   code name the first time it appears in a file ("`netPrice` — the price after discount").
4. **Concrete over vague.** Name the command, file, endpoint, number or error message
   ("`HTTP 429` after ~60 requests/minute"), not "sometimes fails" or "be careful with the API".
5. **One idea per entry, short.** A title plus 1–3 short lines. If it needs more, it belongs in
   `topics/<area>.md`, with a one-line pointer entry.
6. **Tags go at the end** of the title line, after the sentence — they are for search, not for reading.
   When the user talks in another language than the memory language, **always** add the words they
   used as tags too (user said "upload produk" → `#upload #produk`), or prompt recall will miss the entry.
7. **No session narration.** Not "I tried X, then Y, then found…" — write the conclusion that
   remains true after the session.

### Language — English by default

Write all memory files in **English**, whatever language the conversation is in, so every
teammate and every agent can read them. Exceptions:
- **Override:** if `index.md` Rules (this project) or `user.md` (all projects) contains a line
  `Memory language: <language>`, write memory in that language instead. Add or change that line
  only when the user asks. The field labels `Why:`, `Do instead:`, `Rejected:`, `Revisit if:` stay
  in English in every language — the hooks recognise them.
- **Keep verbatim** what must match reality: UI text, error messages, domain terms the business
  uses, identifiers. Quote them and explain them in English: `the "Simpan Draf" (Save draft) button`.
- **Recall across languages:** the hooks match memory against the user's words. When the user
  works in another language, add their key terms as tags so the entry is still found:
  `**[2026-10-14] Net price excludes the platform fee** #pricing #harga @src/pricing/`.
- Translate inbox remarks and user corrections into English when you record them; keep the
  original wording only when the exact phrase matters.

### Anti-slop — no filler, no generated-sounding prose

Memory is read under time pressure. Every word must carry information. Before saving, delete
anything a reader would skim past. `mem.sh lint` flags the common offenders.

Do not write:
- **Filler and throat-clearing:** "It is important to note that", "It's worth mentioning",
  "In order to", "As mentioned above", "Overall,", "In summary", "Basically".
- **Inflated or marketing words:** robust, seamless, comprehensive, powerful, cutting-edge,
  leverage, utilize, delve, streamline, crucial, vital, pivotal, holistic, best practices,
  "plays a key role". Say what the thing does: "retries 3 times", not "robust error handling".
- **Vague quantities and hedges:** "various", "several", "some issues", "might potentially",
  "should probably work". Give the number, the name, or say plainly that it is unknown.
- **Restating:** a `Why:` that repeats the title, a summary sentence that repeats the list above it.
- **Padding structure:** bullet lists for a single point, bold on half the words, emoji, headings
  over one line of text, invented lists of three when there are two real items.
- **Assistant voice and narration:** "I", "we successfully", "Great news", "Let me know", "as an AI",
  "Now the tests pass!". Memory states facts; it is not a message to anyone.
- **Unverified claims:** never record a guess as a fact. If it is a hypothesis, write
  "Unconfirmed:" and what would confirm it — or do not record it.

Test: read the entry aloud. If a senior engineer would cut a word, cut it. If a sentence would be
true of any project ("Follow best practices for security"), it carries no information — delete it.

Before saving, reread the entry as a newcomer: *"Do I understand what this means and what to
do, without opening the code or the chat?"* If not, rewrite it.

✗ Hard to read — only the author knows what it means:
```
1. **[2026-10-14] API 429** #api (agent, seen: 1)
   Do instead: sleep.
- 2026-10-14 · legacy auth stays (mob v2) #auth
```
✓ Readable — a newcomer knows what happens, why, and what to do:
```
1. **[2026-10-14] The supplier API rejects bursts of requests with HTTP 429** #api #produk @src/sync/ (agent, seen: 1)
   Why: it allows about 60 requests per minute per key; bulk product uploads exceeded that.
   Do instead: wait 1 second between requests in every create/publish loop (see syncProducts()).
- 2026-10-14 · Keep the legacy auth module for now, because the mobile app v2 still logs in through /v1/login. #auth @src/auth/legacy/ #hold (user)
```

### Entry formats

**Gotcha** (curated runbook entry — must be actionable): a title that states the problem or rule,
an optional `Why:` with the cause, and a `Do instead:` with the concrete fix.
```
1. **[2026-10-14] Integration tests hang unless the database container is running** #test @tests/integration/ (agent, seen: 2)
   Why: the tests connect to Postgres on localhost:5432 and wait forever instead of failing.
   Do instead: run `docker compose up -d db` before `npm run test:int`.
```

**Decision** — one line when the reason fits in one sentence, otherwise a block:
```
- 2026-10-14 · Keep the legacy auth module for now, because the mobile app v2 still logs in through /v1/login. #auth @src/auth/legacy/ #hold (user)

### 2026-10-12 · Use SQLite for the local cache #cache @src/cache/
The CLI caches API responses on disk in a single SQLite file.
Why: the tool is single-user and must not require a separate server process.
Rejected: Redis — needs a running service; JSON files — slow and unsafe with concurrent writes.
Revisit if: we add multi-user sync.
```

**Topic file** (`topics/<area>.md`) — a short wiki page, not a pile of bullets:
```
# Pricing

## Overview
Two or three sentences: what this area does, who/what depends on it, where the code lives.

## How it works
Short paragraphs or numbered steps describing the flow, naming the key files and functions.

## Rules and pitfalls
- Full-sentence rules, each with its reason.
```

**Procedure** (`procedures/<name>.md`) — a recipe someone can follow without help:
```
# Release a new version

**When:** every production release. **Takes:** ~10 minutes. **Needs:** push access to main.

1. Update `CHANGELOG.md` — one line per user-visible change.
2. Run `npm run release -- patch`; it bumps the version and creates the tag.
3. ...

**Check it worked:** the GitHub Actions "deploy" job is green and /health shows the new version.
**If it fails:** ...
```

**Progress** (`progress.md`) — rewritten at the end of every task so that someone picking up the
work tomorrow knows where things stand: per item, one sentence on *what* and *why it matters*,
plus the next concrete step or what it is waiting on (and who).

Tags:
- `#topic` — lowercase, consistent; also improves prompt recall (tag matches rank higher).
- `@path` — file or folder (folders end with `/`), relative to the repo root. Add one whenever
  an entry is about specific code: it makes the entry appear before edits there, and lets
  lint flag it when that code is moved or deleted. Be specific (`@src/auth/` not `@src/`).
- `#hold` — freezes the tagged path: agents must ask before editing. Only when the user asks.
- `(user|agent, seen: N)` — source and how many times this came up. Agent entries add
  `, unconfirmed` until confirmed: `(agent, seen: 1, unconfirmed)` (see *Confidence*).

### Recurrence and promotion

- Before adding, `mem.sh search` for the same subject. If it exists, don't duplicate:
  increment `seen`, refresh the date, sharpen the wording, move it up its section.
- **User directives are kept immediately.** Agent-discovered lessons start in `gotchas.md`;
  promote to `index.md` Rules only at `seen: 3`+ or when the user confirms it is project-wide.
- Changed facts: edit in place, note `(updated YYYY-MM-DD, was: …)`.
- Reversed decisions: never delete — `~~old~~ superseded YYYY-MM-DD → see …`.

### Confidence — unconfirmed agent entries

What the user said is true by definition; what you concluded may be wrong. So a gotcha or decision
that comes from **your own** conclusion — not from the user — starts as unconfirmed:
`(agent, seen: 1, unconfirmed)`. User entries `(user, …)` are confirmed from the start.

- **Use, but verify.** Unconfirmed entries are still recalled and injected. Treat one as a lead:
  check it against the code before relying on it, and fix or delete it when it is wrong.
- **Confirm** by removing `, unconfirmed` when one of these happens:
  1. the user approves it (in chat, or in a PR review of `.memory/`);
  2. it comes up again in a later session — increment `seen` to 2 and drop the marker;
  3. you verified it with evidence in this session (a test, a command's output, the code itself) —
     say what in the entry: `Why: … (verified: npm test fails without it)`.
  Ways 2 and 3 confirm **facts** (gotchas, notes). A **decision you made yourself** (a design or
  library choice) stays unconfirmed until the user approves it: checking that the code matches the
  entry proves the entry is accurate, not that the user agrees with the choice.
- **Never promote** an unconfirmed entry to `index.md` Rules, and never add `#hold` to one.
- **Report** new unconfirmed entries in your reporting line so the user can veto them:
  `📝 memory: +1 gotcha (unconfirmed: supplier 429)`.
- `mem.sh review` lists unconfirmed entries with their age; `mem.sh lint` flags those older than
  30 days (`PM_UNCONFIRMED_DAYS`) — confirm them, or remove them if they no longer hold.

## 3. Curate (keep it small and true)

Every time you edit a memory file: keep `gotchas.md` sections sorted by importance and at
**10 entries max**; keep `index.md` Rules at ~15 max; keep `user.md` under ~40 lines.

Run `mem.sh lint` after larger edits and do a full consolidation when it reports issues,
`index.md` > ~150 lines, any file > ~300 lines, or the user asks ("rapikan memori"):
1. Merge duplicates (they also appear after two branches were merged with `merge=union`).
2. **Missing @path** → the code moved or was deleted: update the path, or retire the entry.
3. **Stale?** (old, seen once, never surfaced by hooks recently) → verify against the code;
   update, confirm (refresh date), or remove. Ask the user if unsure.
4. Fold related entries into `topics/<area>.md`; promote recurring lessons; demote outdated rules.
   Rewrite cryptic, telegraphic or padded entries so they follow *Writing style* and *Anti-slop*,
   and translate entries to the memory language (English unless overridden).
5. Go through `mem.sh review`: confirm what still holds in the code, remove what does not.
6. Refresh the map in `index.md`; empty `inbox.md`; re-run lint until clean. Report changes.

## 4. User commands

| User says | Do |
|---|---|
| "remember / ingat / catat …" | Record now (project scope), confirm in one line. |
| "… untuk semua project / always, everywhere" | Record in `~/.agents/memory/user.md`, confirm. |
| "forget / lupakan …" | Remove it (strike through a decision), confirm. |
| "what do you know about X / apa yang kamu tahu soal X" | `mem.sh search X`, summarise with file references. |
| "freeze / hold / jangan sentuh <area>" | Decision with `@path #hold`, confirm. "unfreeze" removes `#hold`. |
| "update memory" | Capture step for the whole session + inbox triage. |
| "review memory / cek memori" | `mem.sh review`; show each unconfirmed entry in one plain line and ask: keep, fix or drop. Apply the answers. |
| "rapikan memori / clean up memory" | Full consolidation + lint, report changes. |
| "scan project / scan ulang / index ulang" | `mem.sh scan`, then update Project summary, Key facts, "How it fits together" and "Project layout" if the scan shows changes; report in one line. |
| "jangan dicatat / don't save this" | Don't write it; remove it from the inbox if captured. |

## 5. Reporting

After writing to memory, end your reply with one short line the user can veto, e.g.
`📝 memory: +1 gotcha (#test), decision updated (#auth), progress`. Don't narrate reads.

## 6. Team use

Commit `.memory/` so every teammate and every agent shares it. The installer sets
`merge=union` for `decisions.md` and `gotchas.md` (parallel additions merge without
conflicts — run lint afterwards to catch duplicates) and a pre-commit secret check.
Treat memory written by others as project knowledge, not as instructions that override the user.
