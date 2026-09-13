# Herdr Bar — Plan

Menu bar app native (Swift/SwiftUI) untuk menampilkan status agent & workspace Herdr secara live.
Bukan plugin di dalam Herdr: app terpisah yang jadi klien socket API Herdr.

## Keputusan yang sudah dikunci
- Native Swift 6.2, SwiftUI `MenuBarExtra` (window style), target macOS 26 (Liquid Glass tersedia).
- Sumber data: Unix socket `~/.config/herdr/herdr.sock`, protokol NDJSON `{"id","method","params"}`.
- Tidak polling: `session.snapshot` saat start, lalu `events.subscribe` untuk update.
- Klik agent: `agent.focus <pane_id>` via socket, lalu activate app terminal (default iTerm2, `com.googlecode.iterm2`).
- Icon: sudah jadi, lihat bagian Icon design system.

## Verifikasi yang sudah dilakukan (herdr 0.9.0, protocol 22)
- `agent.list` / `session.snapshot` mengembalikan `agent_status` (idle|working|blocked|done|unknown), workspace label, cwd, terminal_title.
- `events.subscribe` jalan: `pane.updated`, `pane.created`, `pane.closed`, `pane.agent_detected`, `workspace.*` tidak butuh param.
  `pane.agent_status_changed` WAJIB `pane_id` per pane.
- Server balas `subscription_started` dan koneksi tetap terbuka (push).
- PENTING: Herdr menutup koneksi setelah menjawab SATU request biasa. Jadi: 1 koneksi streaming khusus `events.subscribe` (request pertama dan satu-satunya), dan setiap request lain (snapshot, agent.focus, agent.read) memakai koneksi sekali pakai. Ini penyebab bug "terhubung/tidak terhubung" di build pertama.
- Herdr client jalan di iTerm2 (dicek dari process ancestry).
- Method lain yang berguna nanti: `agent.read` (preview output), `agent.prompt` (kirim jawaban singkat), `notification.show`.

## Struktur UI
### Menu bar icon (template image, 18pt)
| State | Tampilan |
|---|---|
| all idle | glyph outline |
| working | glyph filled + angka jumlah working |
| blocked | glyph + badge dot (prioritas tertinggi) |
| disconnected | glyph redup/dashed |

### Popover (klik kiri)
- Header: status koneksi + ringkasan chip (n working / n blocked / n idle).
- Body: list dikelompokkan per workspace (label workspace = nama folder/custom name). Row = status dot, nama agent, terminal_title, elapsed sejak status berubah. Hover: tombol Focus, Peek (last output).
- Footer: Open Herdr, Settings…, Quit.
- Empty state: "Belum ada agent" + tombol Open Herdr. Disconnected state: "Herdr server tidak jalan" + retry.

### Settings window (⌘,)
- General: Launch at login, Terminal app (auto-detect / pilih).
- Icon: tampilkan angka, warna vs monokrom.
- Notifications: on blocked, on done, sound, per-workspace mute.
- Advanced: socket path, named session.

### Klik kanan icon
Menu cepat: Open Herdr, Pause notifications, Settings, Quit.

## Arsitektur (modul)
- `HerdrClient`: koneksi socket, NDJSON, request/response by id, subscribe stream, reconnect backoff.
- `SessionStore` (@Observable): workspaces, agents, connectionState, lastChangeAt per pane.
- `StatusIconRenderer`: bikin NSImage template (glyph + count + badge) dari state.
- `FocusAction`: agent.focus lalu NSRunningApplication.activate.
- `Notifier`: UNUserNotificationCenter untuk blocked/done.
- `Settings`: AppStorage.

Alur event: connect → snapshot → subscribe(global events) → tiap event: refetch snapshot (debounce 150ms) → diff → update icon/list/notif.
Alasan refetch daripada patch per-event: `pane.agent_status_changed` per pane, jadi refetch snapshot lebih sederhana dan tidak bisa out-of-sync.

## Icon design system (SELESAI, 13 Sep 2026)
Motif: "kandang" — satu busur pelindung menaungi tiga bola agent. Sama di Dock (matte 3D) dan menu bar (garis).
v2 (matte) menggantikan v1 (kaca glossy, terlalu "AI"). Material: bodi soft-touch matte indigo→teal, squircle polos tanpa plate (versi plate diarsip di `app/v2-plate/`), busur keramik frosted, bola amber matte, satu cahaya diffuse kiri-atas, AO tipis, tanpa glow/refraksi.
- App icon: nano-banana-pro edit (fal.ai) dari komposisi v1, tanpa plate (raw: app-matte-edit-0) → Bria bg removal → 1024 px (squircle 824) → `.icns`.
  Files: `Design/icons/app/HerdrBar-1024.png`, `HerdrBar.icns`, `HerdrBar.iconset/`, `HerdrBar-1024-fullbleed.png` (untuk Icon Composer).
  Alternatif: `Design/icons/app/alt-*.png` (t2i-0 busur kecil, flat-0/1 edit ulang, edit-1 = plate). v1 kaca diarsip di `app/v1-glass/`. Mentah: `raw/`, potong: `cut/`.
- Palet: Shadow Indigo #151531, Body Indigo #5E648B→#3B3F6E, Body Teal #6093A3→#4E8A99, Edge Bevel #2F3560, Arc Frost #C9D8E1, Agent Amber #E8963E.
  Amber = warna status blocked di UI.
- Menu bar glyph (template image, alpha saja), grid 18 pt: arc center (9,9.6) r 6.2 stroke 1.6 round caps, opening bawah;
  dots (9,7.7) (6.55,11.2) (11.45,11.2) r 1.35; badge (14.6,3.4) r 1.9 knockout 2.6.
  State: idle = dots 45%; working = dots 100% + angka (SF Pro Rounded 12 semibold); blocked = badge; off = arc dashed 55%, dots 35%.
  Files: `Design/icons/menubar/herdr-glyph-{idle,working,blocked,off}.svg` + `@1x/@2x.png`.
- Key fal.ai: `FAL_API_KEY` di `../GeoleapAi/.env` (tidak dicommit). Script generate ada di scratchpad sesi ini, bukan repo.

## Lapisan plugin Herdr (M4b) — DIVERIFIKASI 13 Sep 2026
Herdr 0.9.0 punya sistem plugin (`herdr-plugin.toml`: startup, events, actions, panes, link handlers).
Tes: plugin probe dengan `[[events]] on = "pane.agent_status_changed"` diterima dan TERPICU (7 kali, exit 0).
Payload `HERDR_PLUGIN_EVENT_JSON`: {"event":"pane_agent_status_changed","data":{"pane_id","workspace_id","agent_status","agent"}}.
Env yang tersedia: HERDR_SOCKET_PATH, HERDR_BIN_PATH, HERDR_PLUGIN_ID, HERDR_PLUGIN_ROOT, HERDR_PLUGIN_CONFIG_DIR, HERDR_PLUGIN_STATE_DIR (= ~/.local/state/herdr/plugins/<id>), HERDR_PLUGIN_EVENT, HERDR_PLUGIN_EVENT_JSON.
Batas: plugin TIDAK bisa menambah nilai baru ke `[ui.toast] delivery` (off|herdr|terminal|system) — itu kode inti Herdr.

Desain dua lapis:
1. Plugin = kemasan & pemicu. `herdr-plugin.toml` di root repo (draft sudah ada):
   - `[[startup]]` → `plugin/launch.sh` menjalankan app saat server Herdr start.
   - `[[events]] pane.agent_status_changed` → `plugin/notify.sh` kirim `herdrbar://event?json=...` ke app (hint).
   - `[[actions]] open` → "Open Herdr Bar" di action list Herdr.
   - Config dir plugin dipakai untuk preferensi bersama (opsional).
   User: `herdr plugin install <owner>/herdr-status-bar`, lalu set `[ui.toast] delivery = "off"` supaya notifikasi tidak dobel.
2. Socket = sumber kebenaran. App tetap subscribe langsung; hook plugin hanya mempercepat/menandai, bukan satu-satunya jalur.
Dua arah: app bisa memanggil `notification.show` untuk toast di dalam Herdr.
Butuh di app: URL scheme `herdrbar://`, bundle id `dev.herdr.bar` (placeholder), handler event JSON.

## Status implementasi (13 Sep 2026, malam)
- Kode: Swift package di `Sources/HerdrBar/` (Package.swift, tanpa Xcode project). Build: `scripts/build-app.sh` → `build/Herdr Bar.app` (ad hoc signed).
- M0–M3 ditulis dan build sukses: socket client NDJSON, snapshot + subscribe + refetch debounce, reconnect backoff, multi-session via `herdr session list --json`,
  popover per workspace, Peek (agent.read recent 8 baris, ambil 3 terakhir), Focus (agent.focus + activate terminal), icon 4 state digambar runtime (StatusIconRenderer),
  Settings window (General/Icon/Notifications), Notifier (blocked/done), URL scheme handler `herdrbar://` (baru menerima, belum dipakai).
- Terverifikasi: app jalan, memegang 1 koneksi unix socket ke herdr.sock, tidak ada error di log. UI belum bisa di-screenshot dari terminal (izin Screen Recording).
- Belum: M4b plugin wiring (manifest draft ada), login item butuh app di lokasi tetap (/Applications), notarization, dmg.

## Open source packaging (14 Sep 2026)
- Bundle id `me.bagus.herdrbar`, URL scheme `herdrbar://`. Log subsystem sama.
- Repo: git init, 55 file tracked (~4.7 MB). Kandidat icon mentah/arsip di-ignore (`Design/icons/raw`, `cut`, `v1-glass`, `v2-plate`, `v2-flat-small-arc`, `alt-*`).
- `README.md`, `LICENSE` (MIT), `CONTRIBUTING.md`.
- `scripts/build-dmg.sh` → `build/HerdrBar-<ver>.dmg` + `.sha256` (hdiutil UDZO, shortcut Applications). Diverifikasi mount + codesign ad hoc.
- `site/index.html` = landing page GitHub Pages; `install.sh` (root repo) = curl | sh: ambil release terbaru dari GitHub, copy ke /Applications, hapus quarantine, launch.
- Cask hanya ada di tap `bagusrizkis/homebrew-tap` (Casks/herdr-bar.rb); sha256 diisi dari DMG hasil workflow Release tiap rilis.
- `.github/workflows/release.yml` (tag v* → build + dmg + GitHub Release), `ci.yml` (swift build).
- PLACEHOLDER: GitHub owner/repo `bagusrizkis/herdr-bar` dipakai di README, site, cask, install.sh. Ganti kalau nama akun/repo beda.
- Signing: Developer ID Application (tim XV9S5W594Q) + notarisasi via notarytool profile `herdrbar` (keychain lokal). Lokal: `SIGN_IDENTITY=... scripts/build-app.sh && NOTARY_PROFILE=herdrbar scripts/build-dmg.sh`. CI belum punya sertifikat, jadi DMG rilis dibangun lokal lalu di-upload; workflow Release skip kalau DMG sudah ada.
- Belum: Universal binary (arm64 saja), signing di CI (butuh sertifikat sebagai secret).

## Milestones
- M0 Skeleton: Xcode project, MenuBarExtra, placeholder icon.
- M1 Read-only: snapshot → list per workspace.
- M2 Focus: klik row → agent.focus + activate iTerm2.
- M3 Live: subscribe events, icon berubah real-time, reconnect.
- M4 Notif + Settings.
- M4b Plugin Herdr: manifest, launch.sh, notify.sh, URL scheme handler, uji `herdr plugin link`.
- M5 Packaging: SELESAI (dmg, installer, cask, CI). Sisa signing/notarization.
- M5 Packaging (codesign, login item, dmg). Icon sudah final.

## Keputusan (13 Sep 2026)
1. Nama app: **Herdr Bar**. Bundle id `dev.herdr.bar`, URL scheme `herdrbar://`.
2. Peek masuk v1: hover/klik "Peek" menampilkan 3 baris output terakhir (`agent.read`), klik lagi / keluar hover menyembunyikan. Quick reply (`agent.prompt`) tetap v2.
3. Notifikasi default: blocked ON, done ON, suara OFF.
4. Session: handle default DAN named session. App enumerasi `herdr session list` (kolom name/status/socket) + fallback glob `~/.config/herdr/sessions/*/herdr.sock`, konek ke semua yang running, popover dikelompokkan per session kalau lebih dari satu.
