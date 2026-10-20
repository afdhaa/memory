# project-memory v3.4

Memori berbentuk Markdown untuk coding agent: per project di `.memory/`, plus memori pribadi
lintas project di `~/.agents/memory/user.md`. Satu skill untuk Claude Code, Codex, OpenCode,
Antigravity, dan Pi/omp. Tanpa server, database, atau container; hook & helper bash + awk murni.

## 1. Instal

Butuh: `bash`, `awk`, `git`. Jalan di macOS dan Linux.

### A. Per project (disarankan)

Clone sekali, lalu jalankan installer dari root setiap project yang ingin punya memori:

    git clone https://github.com/afdhaa/memory.git ~/tools/project-memory
    cd ~/kode/project-saya
    bash ~/tools/project-memory/scripts/install.sh

Hasilnya:

| Lokasi | Isi |
|---|---|
| `.agents/skills/project-memory/` | salinan skill (dibaca Codex, OpenCode, Antigravity, omp) |
| `.claude/skills/project-memory` | symlink ke salinan di atas (Claude Code) |
| `.memory/` | memori project dari template, langsung di-*scan* (lihat §2) |
| `AGENTS.md`, `CLAUDE.md` | blok instruksi singkat di antara `<!-- project-memory:start/end -->` |
| `.claude/settings.json`, `.codex/hooks.json` | hooks otomatis (lihat §3) |
| `.gitignore`, `.gitattributes`, pre-commit | file pribadi tidak di-commit, merge tanpa konflik, cegah token bocor |
| `~/.agents/memory/user.md` | memori pribadi lintas project (dibuat bila belum ada) |

| Opsi | Fungsi |
|---|---|
| *(tanpa opsi)* | semua yang di tabel atas |
| `--no-hooks` | sama, tanpa hooks agent |
| `--remove-hooks` | hapus hooks agent + blok pre-commit milik project-memory (yang lain tidak disentuh) |
| `--global` | skill untuk semua project + user memory (tanpa `.memory/` dan hooks) |

Aman dijalankan ulang. `.memory/` dan `user.md` tidak pernah ditimpa; hook lain dan pre-commit
yang sudah ada dipertahankan (backup `.bak` untuk file JSON).

### B. Global (semua project, tanpa hooks)

    bash ~/tools/project-memory/scripts/install.sh --global

Menyalin skill ke `~/.agents/skills`, `~/.claude/skills`, `~/.config/opencode/skills`, dan
`~/.gemini/antigravity/skills`. Saat dipakai di project tanpa `.memory/`, agent membuatnya
sendiri dari template.

### C. Lewat registry omp (skills.omp.sh)

Bila sudah dipublikasikan (lihat §5):

    omp skill install -g @<scope>/project-memory     # semua project
    omp skill install @<scope>/project-memory        # project ini saja

omp meminta konfirmasi karena skill ini membawa script.

### Cek instalasi

    bash .agents/skills/project-memory/scripts/selftest.sh

76 tes otomatis di repo sementara (tidak menyentuh project/memori Anda). Lulus di bash 5 +
mawk/gawk dan bash 3.2 + BWK awk (macOS). Installer tidak butuh python/node/jq: hooks digabung
ke `settings.json`/`hooks.json` yang sudah ada dengan awk, hook lain tetap utuh (backup `.bak`).

## 2. Mulai pakai

### Scan project baru

Saat `.memory/` dibuat, installer langsung memindai repo. Tanpa installer (mis. skill global di
omp), jalankan sendiri dari root project — `.memory/` dibuat otomatis bila belum ada:

    bash ~/tools/project-memory/scripts/mem.sh scan            # atau .agents/skills/project-memory/scripts/mem.sh
    bash ~/tools/project-memory/scripts/mem.sh scan --print    # lihat hasilnya saja, tidak menulis apa pun

Yang dicatat ke `.memory/topics/codebase.md`:

| Bagian | Isi |
|---|---|
| Overview | nama, ringkasan README, jumlah file per bahasa, branch/commit/remote, dokumen |
| Stack | Node (npm/pnpm/yarn/bun + framework & versi), Python, Go, Rust, PHP, Ruby, Java/Kotlin, .NET, Dart, Elixir, Deno, versi runtime |
| Commands | script `package.json`/`composer.json`, target `Makefile`/`justfile`, perintah standar (`go test ./...`, `cargo test`, `pytest`) |
| Layout | folder utama + subfolder dengan jumlah file, file di root |
| Infrastructure & CI | Docker, service docker-compose, GitHub Actions/GitLab CI/…, Vercel/Netlify/Fly/…, Terraform |
| Config & environment | **nama** variabel dari `.env.example`; isi `.env` tidak pernah dibaca |
| Tests | jumlah file tes dan lokasinya |
| Recently active areas | folder yang paling sering berubah di 300 commit terakhir |

Scan juga menambahkan `topics/codebase.md` ke Map di `index.md` dan mengisi **Key facts** selama
bagian itu masih kosong. Scan ulang hanya mengganti blok di antara `scan:start`/`scan:end`;
catatan Anda di bawahnya dan Key facts yang sudah diedit tidak disentuh. `mem.sh lint` mengingatkan
bila scan sudah tertinggal lebih dari 150 commit (`PM_SCAN_STALE`).

### Sesudah scan

1. Buka agent di root project, lalu minta: **"lengkapi .memory/index.md dari hasil scan"**. Agent
   menulis Project summary (di Claude Code & Codex, hook mengingatkannya otomatis selama ringkasan
   masih kosong).
2. Kerja seperti biasa. Agent membaca memori di awal tugas dan mencatat keputusan, koreksi
   Anda, jebakan, dan progres sebelum selesai. Setiap kali menulis, agent menutup jawabannya
   dengan satu baris seperti `📝 memory: +1 gotcha (#test), progress`.
3. Commit `.memory/` agar rekan tim dan agent lain ikut memakai memori yang sama.

### Gaya penulisan memori

Isi `.memory/` ditulis untuk dibaca manusia (rekan tim, reviewer PR, Anda sendiri), bukan hanya
agent. SKILL.md mewajibkan agent menulis setiap catatan agar bisa dipahami orang yang tidak ikut
sesi tersebut:

- Judul berupa kalimat utuh yang langsung menyebut intinya, bukan singkatan atau potongan kata.
- Selalu ada **apa**, **kenapa** (`Why:`), dan **harus bagaimana** (`Do instead:`).
- Konkret: sebut perintah, file, angka, atau pesan error — bukan "kadang gagal".
- Istilah domain dijelaskan saat pertama muncul; satu ide per catatan; tag di akhir baris.
- `topics/` ditulis seperti halaman wiki singkat, `procedures/` seperti resep langkah demi langkah,
  `progress.md` cukup jelas untuk dilanjutkan orang lain besok.

Contoh:

    ✗ 1. **[2026-10-14] API 429** #api (agent, seen: 1)
         Do instead: sleep.

    ✓ 1. **[2026-10-14] API supplier menolak request beruntun dengan HTTP 429** #api @src/sync/ (agent, seen: 1)
         Why: batasnya sekitar 60 request per menit per key; upload produk massal melewatinya.
         Do instead: beri jeda 1 detik di setiap loop create/publish (lihat syncProducts()).

Label `Why:` / `Do instead:` / `Rejected:` / `Revisit if:` tetap berbahasa Inggris karena dikenali
hook; isinya memakai bahasa project. Minta **"rapikan memori"** untuk menulis ulang catatan lama
yang masih kriptik.

### Perintah ke agent

| Anda bilang | Hasil |
|---|---|
| "ingat ini …" / "catat …" | dicatat untuk project ini |
| "ingat untuk semua project …" | dicatat di `~/.agents/memory/user.md` |
| "lupakan …" | dihapus (keputusan dicoret, tidak dihapus) |
| "apa yang kamu tahu soal X" | ringkasan dari memori + rujukan file |
| "jangan sentuh folder X" | area dibekukan (`#hold`); agent wajib minta izin sebelum mengedit |
| "update memory" | catat semua yang penting dari sesi ini |
| "rapikan memori" | gabung duplikat, buang yang basi, cek ulang dengan lint |
| "scan ulang" / "index ulang project" | `mem.sh scan`, lalu Project summary/Key facts diperbarui bila perlu |
| "jangan dicatat" | tidak disimpan |

### Helper (bisa dijalankan manual)

    bash .agents/skills/project-memory/scripts/mem.sh search harga produk
    bash .agents/skills/project-memory/scripts/mem.sh path src/api/
    bash .agents/skills/project-memory/scripts/mem.sh lint      # + @path hilang, entri basi, duplikat
    bash .agents/skills/project-memory/scripts/mem.sh stats
    bash .agents/skills/project-memory/scripts/mem.sh scan      # index ulang repo
    bash .agents/skills/project-memory/scripts/mem.sh approve src/api/ 30   # buka #hold 30 menit

## 3. Dukungan per agent

| Agent | Skill | Hooks otomatis |
|---|---|---|
| Claude Code | `.claude/skills/` | ya (`.claude/settings.json`) |
| Codex | `.agents/skills/` | ya (`.codex/hooks.json`) |
| omp / Pi | `.agents/skills/`, `~/.agents/skills/` | tidak — agent mengikuti SKILL.md secara manual |
| OpenCode, Antigravity | `.agents/skills/` | tidak — lewat instruksi di AGENTS.md |

Yang dilakukan hooks di Claude Code & Codex:

| Kapan | Apa |
|---|---|
| Awal sesi / setelah compaction | `index.md`, `progress.md`, `user.md` disuntikkan; pengingat triase inbox |
| Setiap prompt | maks. 5 catatan paling relevan disuntikkan (peringkat kata kunci, tanpa duplikat per sesi); kalimat koreksi ("jangan…", "salah…", "always…") ditangkap ke `inbox.md` dengan token disensor |
| Sebelum edit file | catatan `@path` untuk file itu muncul; area `#hold` selalu minta izin (Claude Code: dialog izin; Codex: edit ditahan, agent bertanya ke Anda lalu menjalankan `mem.sh approve` setelah Anda setuju) |
| Sebelum berhenti | pengingat mencatat bila kode berubah tapi memori tidak (maks. 3x/sesi) |

Matikan hooks: `export PM_HOOKS=off`. Atur: `PM_RECALL_MAX` (5), `PM_MAX_NUDGES` (3),
`PM_STALE_DAYS` (120), `PM_USER_MEMORY`.

### Catatan omp

- Instal dengan cara A, B, atau C. omp membaca `.agents/skills/` (project) dan
  `~/.agents/skills/` (global) tanpa konfigurasi tambahan, juga blok instruksi di `AGENTS.md`.
- Hooks Claude Code tidak dijalankan omp (hooks omp berupa modul TS/JS), jadi recall dan
  pencatatan dilakukan agent mengikuti SKILL.md. Untuk memastikan skill dipakai, ketik
  `/skill:project-memory` di awal sesi.
- Cek: tanya omp "skill apa saja yang berhubungan dengan memory?" — `project-memory` harus muncul.
- Project baru dengan skill global: ketik `/skill:project-memory scan project ini`; agent
  menjalankan `mem.sh scan` dari folder skill lalu menulis Project summary.

## 4. Update & hapus

    git -C ~/tools/project-memory pull
    cd ~/kode/project-saya && bash ~/tools/project-memory/scripts/install.sh   # salinan skill diperbarui

Lewat registry: `omp skill update project-memory`.
Hapus hooks: `install.sh --remove-hooks`; lalu hapus `.agents/skills/project-memory`,
`.claude/skills/project-memory`, dan blok `project-memory` di `AGENTS.md`/`CLAUDE.md`.
`.memory/` tetap milik Anda.

## 5. Publikasi (untuk pemelihara)

GitHub (`git@github.com:afdhaa/memory.git`):

    bash scripts/selftest.sh         # harus 0 gagal
    git add -A && git commit -m "…" && git push

skills.omp.sh (versi diambil dari `metadata.version` di SKILL.md):

    omp skill publish . --dry-run    # cek isi paket & pemindaian secret
    omp skill version patch          # naikkan versi untuk rilis berikutnya
    omp skill publish .

## Tim

- `.gitattributes` `merge=union` untuk `decisions.md` & `gotchas.md`: tambahan dari dua branch digabung tanpa konflik (lint menandai duplikat).
- pre-commit menolak commit yang memasukkan token/password ke `.memory/`.
- `inbox.md`, `local.md`, `.stats.tsv` tidak ikut di-commit.
