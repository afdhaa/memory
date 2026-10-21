# Writing memory — full guide

Read this once per session before you write or rewrite memory. SKILL.md has the short version.

Memory is read by people (teammates reviewing `.memory/` in a PR, the user checking what you
know) as much as by agents. An entry that only its author can decode is worthless next month.
Every entry must make sense to someone who was **not** in this session and does not know the code yet.

## Writing rules

1. **Lead with the point, in plain words.** The bold title is a complete statement a reader can act
   on: "Integration tests hang unless the database container is running", not "int tests hang (db)".
2. **Say what, why, and what to do.** What happens or was decided, then why (cause, constraint, who
   asked), then what to do instead. The reason lets a future reader judge whether the entry still holds.
3. **Full sentences, no private shorthand.** No telegraphic fragments ("db flaky, retry"), no
   abbreviations you invented, no arrows or symbols in place of verbs. Explain a domain term or a
   code name the first time it appears in a file ("`netPrice` — the price after discount").
4. **Concrete over vague.** Name the command, file, endpoint, number or error message
   ("`HTTP 429` after ~60 requests/minute"), not "sometimes fails" or "be careful with the API".
5. **One idea per entry, short.** A title plus 1–3 short lines. If it needs more, it belongs in
   `topics/<area>.md`, with a one-line pointer entry.
6. **Tags go at the end** of the title line, after the sentence — they are for search, not for
   reading. When the user talks in another language than the memory language, always add the words
   they used as tags too (user said "upload produk" → `#upload #produk`), or prompt recall will miss
   the entry.
7. **No session narration.** Not "I tried X, then Y, then found…" — write the conclusion that
   remains true after the session.
8. **One paragraph per line** in topic files and in `topics/codebase.md`. Prompt recall reads memory
   line by line; a paragraph broken over several lines is recalled as fragments.

## Language

Write all memory files in **English**, whatever language the conversation is in, so every
teammate and every agent can read them. Exceptions:

- **Override:** if `index.md` Rules (this project) or `user.md` (all projects) contains a line
  `Memory language: <language>`, write memory in that language instead. Add or change that line
  only when the user asks. The field labels `Why:`, `Do instead:`, `Rejected:`, `Revisit if:` stay
  in English in every language — the hooks recognise them.
- **Keep verbatim** what must match reality: UI text, error messages, domain terms the business
  uses, identifiers. Quote them and explain them in English: `the "Simpan Draf" (Save draft) button`.
- **Recall across languages:** the hooks match memory against the user's words, so tag entries with
  the user's own terms: `**[2026-10-14] Net price excludes the platform fee** #pricing #harga @src/pricing/`.
- Translate inbox remarks and user corrections into English when you record them; keep the
  original wording only when the exact phrase matters.

## Anti-slop

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
- **Unverified claims:** never record a guess as a fact. Mark your own conclusions `unconfirmed`
  (see *Confidence* in SKILL.md), say what was verified and how, and say plainly what was not tested.

Test: read the entry aloud. If a senior engineer would cut a word, cut it. If a sentence would be
true of any project ("Follow best practices for security"), it carries no information — delete it.

Before saving, reread the entry as a newcomer: *"Do I understand what this means and what to do,
without opening the code or the chat?"* If not, rewrite it.

## Good and bad examples

✗ Hard to read — only the author knows what it means:
```
1. **[2026-10-14] API 429** #api (agent, seen: 1)
   Do instead: sleep.
- 2026-10-14 · legacy auth stays (mob v2) #auth
```

✗ Readable sentences, but padded and vague:
```
1. **[2026-10-14] Implemented a robust, seamless retry strategy for the API** #api
   Why: it is important to note that various errors can occur.
```

✓ A newcomer knows what happens, why, and what to do:
```
1. **[2026-10-14] The supplier API rejects bursts of requests with HTTP 429** #api #produk @src/sync/ (agent, seen: 1, unconfirmed)
   Why: bulk product uploads sent requests back to back; the supplier's exact limit is not documented.
   Do instead: wait 1 second between requests in every create/publish loop (see syncProducts()).
- 2026-10-14 · Keep the legacy auth module for now, because the mobile app v2 still logs in through /v1/login. #auth @src/auth/legacy/ #hold (user)
```

## Templates

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
work tomorrow knows where things stand. Per item: one sentence on what it is and why it matters,
then the next concrete step, or what it is waiting on and who:
```
## In progress
- Supplier upload fix for HTTP 429: `publishAll()` now waits between requests and retries; tests in `tests/supplier.test.js` were not run yet (no node_modules). Next: `npm install && npm run test`, then a real bulk publish. Not committed.

## Next
- Find out the supplier's real rate limit and tune the delay; 1 second is a safe guess, slow for large batches.

## Blocked / waiting on
- Adding `"type": "module"` to package.json — waiting for the user's decision.
```

**`topics/codebase.md`** — two sections you write after a scan (the scan never changes them):

- *How it fits together*: 3–6 short paragraphs, one per line. What the code does and its main
  parts; how a typical request or job flows through it, naming real files and functions; where to
  start reading; conventions that the file names do not reveal. Write only what you read in the code.
- *Project layout*: one line per folder (or root file) a newcomer needs, saying what lives there and
  where new code of that kind goes:
  ```
  - `src/routes/` — Express routers, one file per URL prefix; keep them thin and call a service.
  - `src/services/` — business logic (pricing, catalogue, supplier sync); new features start here.
  ```
