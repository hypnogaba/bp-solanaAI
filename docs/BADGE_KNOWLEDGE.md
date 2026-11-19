# Solana BP26 badge - knowledge base

Compiled 2026-11-19 from solana.com/breakpoint/badge, the Lua API reference and the
solana-os repo. For an agent that has to work on badge apps without re-reading the docs.

## Hardware

- ESP32-C5-WROOM, RISC-V single core 240 MHz, 16 MB flash, 8 MB PSRAM (used from Solana OS 2.0.0)
- Display ILI9341 320x240 landscape, SPI2 shared with microSD; LVGL 9
- Input: D-pad UP/DOWN/LEFT/RIGHT + SELECT + CANCEL (front, via TCA9534 I2C expander), BOOT = Home (back), RST
- 8x WS2812B RGB LEDs on GPIO 27: 6 across the top, 2 on the right edge; brightness capped at ~24/255
- microSD (name-brand only; no-name cards that ignore CS are rejected), FAT
- Radios: Wi-Fi 6 2.4 + 5 GHz, BLE 5, 802.15.4 (unused). One radio: Wi-Fi and ESP-NOW mesh share it
- USB-C, CH340C serial 115200 baud; console commands help, info, sd, ls, cat, rgb, lua *, ble *, bridge *
- 3.7 V 1000 mAh LiPo, charges at ~100 mA over USB-C (~10 h), ADC battery sense on GPIO 1
- Free GPIO for hacks: 2, 5, 26. Board 68.58 x 104.97 x 1.6 mm, no mounting holes, STL/SCAD case on the site

## Solana OS

- Open source MIT: github.com/solana-foundation/solana-os (ESP-IDF, C, LVGL 9, Lua 5.5)
- Launcher with built-in apps: Wi-Fi, My Badge, Guide, X Dex, Trade, Quests, App Store, Apps, ESP-NOW, HW Debug, Settings, About
- One app at a time; app frees memory on exit; HOME (BOOT) always returns to the launcher
- Browser emulator with the real firmware: /breakpoint/badge/emulator (two tabs: /emulator and /emulator?badge=2 talk mesh + BLE to each other)
- Flash stock firmware from the browser over USB-C: /breakpoint/badge/stock (Web Serial, Chrome/Edge). Current: 2.4.0
- Game layer: Hitchhiker's Guide to Solana (Guide pages, !LAMPs, X Dex card swaps, quests at beacons, Gossip MMO on the mesh)

## Developer workflow (no toolchain needed)

1. Sign in at /breakpoint/badge/profile and link X (required for http/ws/rpc even in test runs, and for publishing)
2. Write the app at /breakpoint/badge/apps/submit (editor, or drop a folder/zip with main.lua + app.json + files)
3. Try in emulator: runs in the page, print() and errors shown below
4. Run on badge: copies only changed files over USB (Web Serial), starts the app, shows the badge console. Badge needs microSD + Solana OS >= 0.5.0, Wi-Fi joined for http
5. Test runs last 12 h on that badge with the draft's permissions and hosts
6. Publish: store compiles every .lua with the badge's Lua, automatic code check (~1 min), then live. Up to 25 apps per account, 20 versions a day
7. On the badge, installed apps live in /sdcard/hh/apps/<id>/

Building from source needs ESP-IDF v6.x: idf.py build && idf.py -p <port> -b 460800 flash

## App package

- Folder: main.lua (UTF-8, <= 64 KB) + app.json + up to 64 bundled files (<= 256 KB each, <= 1 MB total), read-only via fs / require
- app.json: id (3-24 chars a-z0-9-), name (<= 20), version, author, summary, icon (play star heart bell gift home image list wifi shuffle eye edit charge gps settings audio bulb), accent (hex, no #), category (games tools social quests demos), permissions, hosts (<= 8 names, for http/ws only)
- Permissions: led wifi mesh ble lamps items profile quest http rpc mail background files inventory gossip
- C apps also possible from 2.3.0 (store compiles to wasm + native)

## Lua lifecycle

- Top-level chunk runs once (build UI there). Globals the host calls: on_key(key, rep) ("up" "down" "left" "right" "select" "back"; return false on "back" to exit), on_tick(ms) (every 30 ms, configurable 16..1000 via sys.tick), on_mesh(from, msg), on_meet(from, data), on_exit(), on_service(msg), on_mail(m), on_gossip(ev)
- sys.keys() for keys held now (several at once). No key release event.
- Screen below the status bar: 320 x 218 (ui.W, ui.H), origin top-left
- Everything that talks to the server is async with cb(ok, result); result errors: "offline" "not linked" "denied" "busy" "socket open" "host not allowed" "too fast" "timeout" "unreachable"

## Limits (Solana OS 2.x)

- Lua heap 6 MB (PSRAM); 200 000 VM instructions per callback; 128 UI objects; 200 bytes per label, 12 KB label text on screen; 8 timers (>= 20 ms); storage 16 KB per app
- 32-bit integers (wrap at +-2^31) and 32-bit floats: big numbers from rpc arrive as strings
- Mesh: 4 msg/s, <= 200 bytes JSON, unsigned, lossy; meets are signed by both badges (300/app/day)
- HTTP: 60 req/min per badge, <= 2 KB body, <= ~3.5 KB answer (truncated flag), 6 s timeout, https only, hosts whitelisted in app.json, requests go through the badge server which adds signed X-Badge-* headers (Ed25519, key at https://badge-api.solana.com/api/http/key)
- WebSocket: one at a time, <= 4 KB per message, badge server calls fail with "socket open" while open
- RPC: 30 calls/min (6 sendTransaction), whitelisted read methods + sendTransaction/simulateTransaction, mainnet/devnet, sponsored by Triton One
- BLE: one connection, <= 244 bytes per value, <= 4 characteristics served, ~30 KB SRAM while on, no pairing/encryption
- Background service (service.lua): 1 MB heap, tick 1 s, 3 per badge, cannot spend or use ui/led/ble/ws

## Modules (short)

ui (label rect bar gradient list qr image load canvas anim hint toast confirm input clear), led (set hex fill off, count = 8), timer (after every cancel), sys (millis time battery keys memory tick exit), badge (id owner online), json (encode decode), storage (get set remove), fs (exists size list read lines json load) + require, files (owner's own files on the card, permission files), wifi, mesh (nearby send bridge meet meets pause resume info channel scan), ble (on off advertise scan connect serve set notify drop), lamps (balance spend transfer deposit award), items, profile (me get items pages), quest, http (get post request), ws (open), rpc (call), crypto (sha256 on_curve verify), solana (encode decode pda), service, mail, gossip

Colours: theme names "text" "dim" "bg" "panel" "border" "purple" "green" "pink" "lpurple" "blue" "aqua" "lime" "yellow" "orange", or 0xRRGGBB. Label sizes 12 (mono) 14 20 32.

Images: bundled PNG/GIF (not interlaced, palette preferred), pixel-art rows (characters . # k w p g m v b a l y o), ui.canvas, ui.anim. Integer scale 1..16. 2 bytes per pixel of heap.

## Security rules

- A badge is not a wallet: never put a keypair, API key or password on it. main.lua and the SD card are readable by anyone
- Everything from mesh/BLE is untrusted; the server decides anything of value
- Solana Pay flow: badge builds the message, server hands it to a phone wallet via solana: QR, wallet signs

## Reading the badge from a computer

- Serial console: 115200 baud, tools/badge.py in the repo drives it and saves screenshots (shot)
- lua list / lua run <id> / lua rm <id> / lua mem / lua install <id> / lua put / lua recv / lua sums
- Opening the serial port resets the board; only one process can hold it (close monitors before flashing)

## Links

- Badge site: https://solana.com/breakpoint/badge/
- Lua API: https://solana.com/breakpoint/badge/apps/docs (repo: docs/LUA_API.md)
- C API: https://solana.com/breakpoint/badge/apps/docs/c
- Connectivity guide: https://solana.com/breakpoint/badge/apps/docs/connectivity
- Examples: https://github.com/solana-foundation/solana-os/tree/main/docs/examples
- Support Telegram: https://t.me/+FbTI1ucYgAQxYmQx
