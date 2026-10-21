# project-memory v3.10

Markdown memory for coding agents: one memory per project in `.memory/`, plus a personal memory
shared across projects in `~/.agents/memory/user.md`. One skill for Claude Code, Codex, OpenCode,
Antigravity and Pi/omp. No server, database or container; the hooks and helpers are plain bash + awk.

## 1. Install

Requires `bash`, `awk` and `git`. Runs on macOS and Linux.

### A. Per project (recommended)

Clone once, then run the installer from the root of every project that should have memory:

    git clone https://github.com/afdhaa/memory.git ~/tools/project-memory
    cd ~/code/my-project
    bash ~/tools/project-memory/scripts/install.sh

What it creates:

| Location | Contents |
|---|---|
| `.agents/skills/project-memory/` | copy of the skill (read by Codex, OpenCode, Antigravity, omp) |
| `.claude/skills/project-memory` | symlink to the copy above (Claude Code) |
| `.memory/` | project memory from the templates, scanned right away (see §2); `.memory/README.md` explains each file to teammates |
| `AGENTS.md`, `CLAUDE.md` | a short instruction block between `<!-- project-memory:start/end -->` in `AGENTS.md`; a new `CLAUDE.md` just imports it (`@AGENTS.md`), so Claude Code also sees your project's own AGENTS.md. An existing `CLAUDE.md` gets the block too; a symlink is left alone. |
| `.claude/settings.json`, `.codex/hooks.json` | automatic hooks (see §3) |
| `.gitignore`, `.gitattributes`, pre-commit | keeps personal files out of git, merges without conflicts, blocks leaked tokens |
| `~/.agents/memory/user.md` | personal memory for all projects (created if missing) |

| Option | Effect |
|---|---|
| *(none)* | everything in the table above |
| `--no-hooks` | the same, without agent hooks |
| `--remove-hooks` | removes the agent hooks and the project-memory pre-commit block (nothing else is touched) |
| `--global` | skill for all projects + user memory (no `.memory/`, no hooks) |

Safe to re-run. `.memory/` and `user.md` are never overwritten; other hooks and an existing
pre-commit hook are kept (JSON files get a `.bak` backup).

### B. Global (all projects, no hooks)

    bash ~/tools/project-memory/scripts/install.sh --global

Copies the skill to `~/.agents/skills`, `~/.claude/skills`, `~/.config/opencode/skills` and
`~/.gemini/antigravity/skills`. In a project without `.memory/`, the agent creates it from the
templates.

### C. From the omp registry (skills.omp.sh)

Once published (see §5):

    omp skill install -g @<scope>/project-memory     # all projects
    omp skill install @<scope>/project-memory        # this project only

omp asks for confirmation because the skill ships scripts.

### Check the installation

    bash .agents/skills/project-memory/scripts/selftest.sh

Runs 110 automated tests in a temporary repo; your projects and memory are not touched. Passes on
bash 5 with mawk/gawk and on bash 3.2 with BWK awk (macOS). The installer needs no python, node or
jq: hooks are merged into existing `settings.json`/`hooks.json` with awk, and other hooks stay
intact (`.bak` backup).

## 2. Getting started

### Memory structure

The installer (or the first `mem.sh scan`) adds this to your project. Everything in `.memory/` is
plain Markdown that you can read, edit and review in pull requests.

```
your-project/
├── .memory/                    # project memory — committed, shared by the team and every agent
│   ├── README.md               # explains these files to teammates (documentation, not memory)
│   ├── index.md                # read at the start of every task: summary, rules, key facts, map
│   ├── progress.md             # what is in progress, next, blocked — rewritten after each task
│   ├── decisions.md            # why things are the way they are, with rejected alternatives
│   ├── gotchas.md              # surprises and corrections, each with "Do instead"
│   ├── topics/
│   │   ├── codebase.md         # how the code fits together, project layout, generated scan facts
│   │   └── <area>.md           # deeper notes per area (auth, billing, deploy…), added over time
│   ├── procedures/
│   │   └── <name>.md           # step-by-step workflows that repeat (release, migration…)
│   ├── local.md                # personal notes for this project      — gitignored
│   ├── inbox.md                # remarks captured from chat, unanswered proposals — gitignored
│   └── .stats.tsv              # which entries the hooks surfaced      — gitignored
├── .agents/skills/project-memory/   # the skill itself (SKILL.md, references/, scripts/, hooks/)
├── .claude/skills/project-memory    # symlink to the skill, for Claude Code
├── .claude/settings.json       # Claude Code hooks
├── .codex/hooks.json           # Codex hooks
├── AGENTS.md, CLAUDE.md        # instruction block for agents (CLAUDE.md imports AGENTS.md)
└── .gitattributes, .gitignore  # merge=union for decisions/gotchas, personal files kept out of git

~/.agents/memory/user.md        # your personal preferences for every project (not in the repo)
```

What an entry looks like:

```
1. **[2026-10-21] The supplier API answers bulk product uploads with "429 Too Many Requests"** #supplier #produk @src/services/supplier.js (agent, seen: 1, unconfirmed)
   Why: publishAll() sent one POST right after another; the supplier's exact rate limit is not documented.
   Do instead: keep the pause between requests in publishAll() and retry a 429 after its Retry-After delay.
```

- **Title**: the point in one sentence, dated.
- **`#tags`**: help search; **`@path`**: shows the entry before an agent edits that code
  (patterns work too: `@app/*/migrations/` for one folder level, `@**/schema.graphql` for any depth).
- **`(user|agent, seen: N)`**: who it came from and how often it came up; `unconfirmed` marks an
  agent's conclusion that nobody has checked yet.
- **`Why:` / `Do instead:`**: the cause and the concrete fix.

### Scan a new project

When `.memory/` is created, the installer scans the repo. Without the installer (for example with
the global skill in omp), run the scan from the project root; it creates `.memory/` if needed:

    bash ~/tools/project-memory/scripts/mem.sh scan            # or .agents/skills/project-memory/scripts/mem.sh
    bash ~/tools/project-memory/scripts/mem.sh scan --print    # print the result only, write nothing

`.memory/topics/codebase.md` has three parts:

1. **How it fits together**: an overview the agent writes after the scan. It covers the main
   parts of the code, how a request or job flows from the entry point to storage, which files to
   read first, and conventions that the file names do not reveal. The scan never changes it.
2. **Project layout**: one line per folder, written by the agent: what lives there and where new
   code of that kind goes. The scan never changes it.
3. **Repository facts (generated)**: the scan output. Each section opens with one sentence that
   says what its list contains:

| Section | Contents |
|---|---|
| Overview | name, README summary, file count per language, branch/commits/remote, docs |
| Stack | Node (npm/pnpm/yarn/bun + frameworks and versions), Python, Go, Rust, PHP, Ruby, Java/Kotlin, .NET, Dart, Elixir, Deno, runtime versions |
| Commands | `package.json`/`composer.json` scripts, `Makefile`/`justfile` targets, standard commands (`go test ./...`, `cargo test`, `pytest`) |
| Layout | main folders with their largest subfolders and file counts, files at the root |
| Infrastructure & CI | Docker, docker-compose services, GitHub Actions/GitLab CI/…, Vercel/Netlify/Fly/…, Terraform |
| Config & environment | variable **names** from `.env.example`; `.env` contents are never read |
| Tests | number of test files and where they are |
| Recently active areas | folders changed most often in the last 300 commits |

The scan also adds `topics/codebase.md` to the Map in `index.md` and fills **Key facts** while
that section is empty. A re-scan replaces only the block between `scan:start`/`scan:end`; text
outside the block and Key facts you have edited stay as they are. An older `codebase.md` without
"How it fits together" or "Project layout" gets those sections, empty, for the agent to write. `mem.sh lint` warns when
the scan is more than 150 commits old (`PM_SCAN_STALE`).

### After the scan

1. Open your agent at the project root and ask it to **"complete .memory/index.md from the scan"**.
   The agent writes the Project summary and the "How it fits together" and "Project layout"
   sections of `codebase.md`. In Claude Code and Codex, a hook reminds it while any is still empty.
2. Work as usual. The agent reads memory at the start of a task and, before finishing, records
   decisions, your corrections, gotchas and progress. Whenever it writes to memory, it ends its
   reply with one line such as `📝 memory: +1 gotcha (#test), progress`.
3. Commit `.memory/` so teammates and other agents share the same memory.

### How memory is written

`.memory/` is written for people (teammates, PR reviewers, you) as much as for agents.

**Language: English by default**, whatever language the conversation is in, so every person and
every agent can read it. UI text, error messages and business terms are kept verbatim, quoted and
then explained. So that automatic recall still finds an entry when you ask in another language,
the agent adds your terms as tags (for example `#harga` next to `#pricing`). To use another
language, add this line to the Rules in `index.md` (or to `user.md` for all projects):

    - Memory language: Indonesian

**Writing rules** (short version in SKILL.md, full guide with examples in `references/writing.md`):

- The title is a complete sentence that states the point, not an abbreviation or a fragment.
- Every entry says **what** happens, **why** (`Why:`) and **what to do** (`Do instead:`).
- Concrete: name the command, file, number or error message.
- **Anti-slop:** no filler ("It is important to note…", "In order to"), no marketing words
  (robust, seamless, comprehensive, leverage…), no vague quantities ("various", "several"), no
  assistant voice ("I", "Great news", "Let me know"), no emoji, and no guesses recorded as facts.
- `mem.sh lint` flags those filler words (text inside `code` is ignored).

Examples:

    ✗ 1. **[2026-10-14] API 429** #api (agent, seen: 1)
         Do instead: sleep.
    ✗ 1. **[2026-10-14] Implemented a robust, seamless retry strategy for the API** #api
         Why: it is important to note that various errors can occur.

    ✓ 1. **[2026-10-14] The supplier API rejects bursts of requests with HTTP 429** #api @src/sync/ (agent, seen: 1)
         Why: it allows about 60 requests per minute per key; bulk product uploads exceeded that.
         Do instead: wait 1 second between requests in every create/publish loop (see syncProducts()).

**Unconfirmed entries.** What you tell the agent is recorded as `(user, …)` and trusted. What the
agent concludes on its own is recorded as `(agent, seen: 1, unconfirmed)`: agents still see it, but
must check it against the code before relying on it. It becomes confirmed when you approve it (in
chat or by deleting `, unconfirmed` in a PR review), when it comes up again in a later session, or
when the agent verifies it with a test or command. Unconfirmed entries never become project Rules.
Ask **"review memory"** (or "cek memori") to go through them; `mem.sh lint` flags those older than
30 days.

    1. **[2026-10-21] The supplier API rejects bursts of product uploads with HTTP 429** #supplier #produk @src/services/supplier.js (agent, seen: 1, unconfirmed)

The labels `Why:` / `Do instead:` / `Rejected:` / `Revisit if:` are always in English because the
hooks recognise them. Ask the agent to **"clean up memory"** to rewrite (and translate) older entries.

### Auto or confirm mode

| Mode | What the agent does |
|---|---|
| `auto` (default) | Writes memory as it works and reports each write in one line (`📝 memory: +1 gotcha …`) so you can veto it. |
| `confirm` | Writes what **you** tell it (instructions, corrections, "remember…") right away. What it **concludes itself** (gotchas, decisions, progress, codebase notes) it only proposes: at the end of the task it lists the exact entries, numbered, and writes only what you approve. |

**Switch modes** in one of three ways:

1. **Ask the agent:** "ask before saving memory" / "mode konfirmasi" switches to confirm; "save memory
   automatically" / "mode otomatis" switches back. Add "for all projects" / "untuk semua project" to
   make it global.
2. **Run the helper:**

       bash .agents/skills/project-memory/scripts/mem.sh mode                    # show the current mode
       bash .agents/skills/project-memory/scripts/mem.sh mode confirm            # this project
       bash .agents/skills/project-memory/scripts/mem.sh mode auto               # back to automatic
       bash .agents/skills/project-memory/scripts/mem.sh mode confirm --global   # all your projects

3. **Edit the line yourself:** `- Memory writes: confirm` (or `auto`) under Rules in
   `.memory/index.md` for this project, or under Workflow in `~/.agents/memory/user.md` for all
   projects. If both exist, the project setting wins. No line means `auto`.

The new mode applies from the next message; hooks pick it up at once.

**Answering a proposal** in confirm mode: reply `all`, `1,3`, `2: <change>` or `none`. Your own
instructions ("don't use axios", "always…", "remember…", "catat…") are written right away, since
they come from you. Proposals you leave unanswered wait in `.memory/inbox.md` (not committed) and come back at
the next session; nothing is written without your yes.

### Talking to the agent

The skill understands both English and Indonesian phrasing.

| You say | Result |
|---|---|
| "remember …" / "ingat ini …" / "catat …" | recorded for this project |
| "remember for all projects …" / "untuk semua project …" | recorded in `~/.agents/memory/user.md` |
| "forget …" / "lupakan …" | removed (decisions are struck through, not deleted) |
| "what do you know about X" | summary from memory with file references |
| "freeze / don't touch folder X" / "jangan sentuh …" | area frozen (`#hold`); the agent must ask before editing it |
| "update memory" | records everything worth keeping from this session |
| "ask before saving memory" / "mode konfirmasi" | confirm mode: the agent proposes entries and writes only what you approve ("mode otomatis" switches back) |
| "review memory" / "cek memori" | walks you through unconfirmed agent entries: keep, fix or drop |
| "clean up memory" / "rapikan memori" | merges duplicates, removes stale entries, rewrites cryptic or padded entries, re-checks with lint |
| "rescan the project" / "scan ulang" | `mem.sh scan`, then updates Project summary, Key facts and "How it fits together" if needed |
| "don't save this" / "jangan dicatat" | nothing is stored |

### Helpers (can be run by hand)

    bash .agents/skills/project-memory/scripts/mem.sh search pricing product
    bash .agents/skills/project-memory/scripts/mem.sh path src/api/
    bash .agents/skills/project-memory/scripts/mem.sh lint      # also: missing @paths, stale entries, duplicates, filler words
    bash .agents/skills/project-memory/scripts/mem.sh review    # unconfirmed agent entries, oldest first
    bash .agents/skills/project-memory/scripts/mem.sh mode confirm   # ask before writing memory (auto = default)
    bash .agents/skills/project-memory/scripts/mem.sh stats
    bash .agents/skills/project-memory/scripts/mem.sh scan      # re-index the repo
    bash .agents/skills/project-memory/scripts/mem.sh approve src/api/ 30   # lift #hold for 30 minutes

## 3. Agent support

| Agent | Skill | Automatic hooks |
|---|---|---|
| Claude Code | `.claude/skills/` | yes (`.claude/settings.json`) |
| Codex | `.agents/skills/` | yes (`.codex/hooks.json`) |
| omp / Pi | `.agents/skills/`, `~/.agents/skills/` | no — the agent follows SKILL.md by itself |
| OpenCode, Antigravity | `.agents/skills/` | no — through the instructions in AGENTS.md |

What the hooks do in Claude Code and Codex:

| When | What |
|---|---|
| Session start / after compaction | injects `index.md`, `progress.md`, `user.md`; reminds the agent to triage the inbox |
| Every prompt | injects up to 5 of the most relevant entries (keyword ranking, no repeats within a session); corrections ("don't…", "wrong…", "jangan…", "always…") are captured in `inbox.md` with tokens redacted |
| Before a file edit | shows the `@path` entries for that file; `#hold` areas always need approval (Claude Code: permission prompt; Codex: the edit is blocked, the agent asks you and runs `mem.sh approve` once you agree) |
| Before stopping | reminds the agent to record memory if code changed but memory did not (at most 3 times per session) |

Turn hooks off: `export PM_HOOKS=off`. Settings: `PM_RECALL_MAX` (5), `PM_MAX_NUDGES` (3),
`PM_STALE_DAYS` (120), `PM_UNCONFIRMED_DAYS` (30), `PM_USER_MEMORY`.

### Notes for omp

- Install with method A, B or C. omp reads `.agents/skills/` (project) and `~/.agents/skills/`
  (global) without extra configuration, and also the instruction block in `AGENTS.md`.
- omp does not run Claude Code hooks (omp hooks are TS/JS modules), so the agent does recall and
  recording itself by following SKILL.md. To make sure the skill is used, type
  `/skill:project-memory` at the start of a session.
- Check: ask omp "which skills are related to memory?" — `project-memory` should be listed.
- New project with the global skill: type `/skill:project-memory scan this project`; the agent runs
  `mem.sh scan` from the skill folder and then writes the Project summary.

## 4. Update and uninstall

    git -C ~/tools/project-memory pull
    cd ~/code/my-project && bash ~/tools/project-memory/scripts/install.sh   # refreshes the skill copy

From the registry: `omp skill update project-memory`.
To uninstall: `install.sh --remove-hooks`, then delete `.agents/skills/project-memory`,
`.claude/skills/project-memory` and the `project-memory` block in `AGENTS.md`/`CLAUDE.md`.
`.memory/` stays yours.

## 5. Publishing (for maintainers)

GitHub (`git@github.com:afdhaa/memory.git`):

    bash scripts/selftest.sh         # must report 0 failed
    git add -A && git commit -m "…" && git push

skills.omp.sh (the version comes from `metadata.version` in SKILL.md):

    omp skill publish . --dry-run    # check package contents and the secret scan
    omp skill version patch          # bump the version for the next release
    omp skill publish .

## Teams

- `.gitattributes` sets `merge=union` for `decisions.md` and `gotchas.md`: additions from two branches merge without conflicts (lint flags duplicates).
- The pre-commit hook rejects commits that put tokens or passwords into `.memory/`.
- `inbox.md`, `local.md` and `.stats.tsv` are not committed.

## License

MIT — see [LICENSE](LICENSE). Release history: [CHANGELOG.md](CHANGELOG.md).
