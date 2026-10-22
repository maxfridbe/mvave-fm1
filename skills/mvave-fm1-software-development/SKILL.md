---
name: mvave-fm1-software-development
description: Write, build, test and ship software (custom firmware) for the M-VAVE FM-1 (JieLi AC791N / pi32v2). Use when asked to create or modify FM-1 firmware, add a synth engine or UI, port something to the device, choose a base firmware, or understand the hardware API (keys, LEDs, LCD, audio ISR, USB-MIDI, flash). Companion to the mvave-fm1-firmware skill, which covers backup / flashing / recovery.
---

# Writing software for the M-VAVE FM-1

Researched from: `aroum/fm1-custom-fw` (catalog of ~130 community firmwares), `hugelton/Felucca` (the HAL almost everything forks), `zvenson/dinghy` (minimal template), `m-vave/fm1_open` (official source + binary SDK), `Keitark/fm1-nes` (bare-metal), `Quixotic7/RemoteFM1` and `TransitFM1`, `rcell233/OpenIFW-fm1`, `dspaudio/orbit`, `FM-1-RE`.

> Scope honesty: the catalog below comes from the hub README. I deep-read the platform bases (Felucca HAL, Dinghy, fm1_open, fm1-nes, RemoteFM1, TransitFM1, ORBIT) but did **not** read each of the ~130 firmware repos. Treat per-firmware notes as pointers, not audits. **The build recipe in section 6 was not run on this machine**: `pkgman.jieliapp.com` (JieLi's toolchain host) was unreachable from here.

Always read the `mvave-fm1-firmware` skill first: take a verified full-flash backup before flashing anything you wrote.

---

## 1. Pick a development path

| Path | Base | Language / toolchain | Use when |
|---|---|---|---|
| **A. Felucca-family platform (recommended)** | Dinghy (smallest) or Felucca / SLOOP / ORBIT | C, JieLi clang 4.0.1 `pi32v2`, Linux x86-64 native (Docker elsewhere) | New instruments, UIs, engines. Gets OTA updates, USB rescue, MIDI, USB audio, LCD, LEDs, settings for free |
| **B. Official open firmware** | `m-vave/fm1_open` (V14: 8 tracks, DX7 library, 8 samples) | C app + **binary** engine SDK (`libfm1_engine.a`), RTOS-task model, **JieLi Windows toolchain 2.5.3** | You want to extend M-VAVE's own instrument and stay close to stock behaviour. Windows/PowerShell build. GPLv3 + SDK linking exception |
| **C. Bare metal / emulator-style** | `Keitark/fm1-nes` (`firmware/usb-diag`) | C, your own startup, app-only `.fm1app` + `jl-uboot-tool` writes | Games, emulators, non-audio. Apache-2.0. You own recovery: no OTA path unless you build it. Experimental |
| **D. Binary patch of stock V15** | `czietz/fm1-firmware-patcher`, `smememe/fm1-macropad-patch` | Python patch scripts on `FM-1.fwsc` | Tiny tweaks (detune fix, aftertouch off, macropad). Flash with M-UPGRADE |
| **E. Modular builders** | `w0ts/optimist` (pick engines/FX in browser/CLI), `Modular-1`, `fm1-rocket-os` | Felucca-derived | Assemble existing engines rather than write DSP |

Default recommendation: **Path A starting from Dinghy**. It is ~200 lines of app on top of a finished platform.

Before writing from scratch, check whether an existing firmware already does it. The catalog (section 8) is large.

---

## 2. Hardware you are programming

- **SoC**: JieLi AC7911B (AC791N / WL82), dual-core pi32v2 RISC, no FPU. 1 MiB SPI NOR inside the package (Puya, JEDEC `0x856014`), executes in place (XIP) through a cache.
- **Display**: 240x240 RGB565 TFT (ST7789-class) on SPI1: `PC10` MOSI, `PC9` CLK, `PC8` D/C, `PC7` CS, backlight `PA2` (active low). Full-screen update is ~115 KB, so draw only what changed.
- **Panel**: 27 keys (F3..G5), 14 buttons, 7 encoders, 1 MASTER pot, LEDs per key/button. One **11 column x 6 row** diode matrix behind 2x 74HC595 (`PA4` SER, `PA3` SRCLK, `PA1` RCLK). Rows `PA0, PA5..PA8, PB7` with pull-ups (low = closed). LED row lines `PH6, PH9, PA9, PA10`. Scanned by a 10 kHz timer (TIMER5). 5 spare 595 outputs are uncommitted.
- **Audio out**: ALNK0 I2S, 24-bit left-justified stereo double-buffered DMA into an external codec. Codec control lines `PC0/1/2/6`.
- **Analog**: SAR ADC ch4 = MASTER pot (`PB6`), ch3 = battery divider (`PB1`). Never hold `PB1` low for 8 s (resets the chip).
- **MIDI**: USB device (full speed, class-compliant MIDI + optional UAC audio + optional CDC serial) and TRS MIDI **IN only** on `PH8` (UART1 RX, 31250 baud). No hardware MIDI OUT on the jack.
- **Wireless**: Wi-Fi/BLE die exists (M-VAVE's open firmware V14 accepts BLE MIDI in and sends BLE out). No community firmware uses much of it yet.
- **No debug header, no JTAG/SWD, no recovery button.** Debugging = crash screen + disassembly + optional CDC console + host-mode builds.

### Button / encoder / key ids (Dinghy / Felucca names)

Buttons: `BTN_OCT_DOWN=0, OCT_UP=1, FX=2, SEL=3, ENV=4, LFO=5, EDIT=6, GLO=7, HOME=8, SAVE=9, ARP=10, SEQ=11, PLAY=12, REC=13`.
Encoders: `ENC_SELECT=0, ALGORITHM=1, KNOB1..KNOB4=2..5, PRESETS=6`.
Keys: bit 0 = F3 (MIDI 53) ... bit 26 = G5. `KEY_LED(k) = 14 + k` for LED ids.

---

## 3. Memory map and runtime model

CPU addresses (Felucca `firmware/app.ld`):

| Region | Address | Size | Notes |
|---|---|---|---|
| XIP code + rodata | `0x02000120` | 0x8DFBC (~568 KB) | `app.bin` byte 0 maps here. `const` tables cost no RAM |
| RAMTEXT | `0x01C00000` | 0x6000 | `.ram_text`: code that must run while flash is busy (the flash driver) |
| RAM (.data/.bss) | `0x01C08000` | 72-96 KB | What ISRs touch, small variables |
| POOL | `0x01C1A000` | 360 KB | Big zeroed buffers, `__attribute__((section(".pool")))` |
| Stacks | `0x01C74000..0x01C7C000` | 24 KB | 256-byte guard bands. Keep big arrays `static` |
| NOINIT | `0x01C7C000` | 0x3D50 | Survives reset and UBOOT entry |
| Reserved | `0x01C7FD50+` | | boot_info, boot-state mailbox (`0x01C7FD80`), UPDATA_PARM (`0x01C7FD88`), vector table |

Flash (1 MiB), physical offsets:

| Range | Use | Rule |
|---|---|---|
| `0x00000-0x03FFF` | Boot head / SPL | Never touch |
| `0x04000-0x92FFF` | Your app | Written by installer |
| `0x93000-0xE8FFF` | Stock settings store; Felucca-family keep songs/sounds `0x97000-0xDFFFF` | Use only your own range |
| `0xE0000-0xE4FFF` | Update-loader staging (platform) | Don't use |
| `0xE5000-0xE6FFF` | Felucca autosave A/B | |
| `0xE7000` | Felucca FM6 voice bank | |
| `0xFC000-0xFEFFF` | Settings / globals (`SETTINGS_AT=0xFC000` in Dinghy) | |
| `0xFF000+` | Reserved | |

Three address spaces are not interchangeable: **physical flash offset**, **decoded app-file offset** (`app.bin` byte 0 = flash `0x4120` in the stock layout), and **CPU runtime address** (`0x02000120` for XIP). Never copy an address from another firmware revision into a write.

### Timing and concurrency model (Felucca platform)

- TIMER5 at 10 kHz: key/encoder scan (`fm1_input_tick`), millisecond counter, USB poll (2 kHz), UART MIDI poll. It has higher priority than the audio IRQ so scanning keeps pace during a render.
- ALNK0 audio IRQ: calls your `app_audio(int32_t *out, uint32_t n)` every 256 frames at 44.1 kHz (5.8 ms). Buffer is `L R L R...`, pre-zeroed, Q15 full scale +-32767; add into it.
- Main loop: your `app_main()`. Must call `platform_poll()` at least every few ms (USB) and never less than once per 8 s (watchdog resets the chip).
- Share data ISR <-> main with `volatile`, one writer each. 32-bit stores are atomic, structs are not.
- Flash erase/program runs from RAM with interrupts off for tens of ms: **audio drops out**. Save only when silent, never in a loop (~100k erase cycles per sector).
- Second core: Felucca can run DSP on core 1 (`FELUCCA_CPU2`), but any reset path must halt it first (see `fm1_cpu1_halt`).

---

## 4. Hardware API (Dinghy `platform.c`, summarised)

```c
#include "platform.c"                       // first line of your app, one compilation unit
static void app_audio(int32_t *out, uint32_t n);   // audio ISR
static void app_main(void);                         // main loop, never returns
```

| Area | Calls |
|---|---|
| Time | `fm1_ms`, `fm1_ticks()` (24 MHz, wraps ~179 s: subtract), `fm1_micros()`, `fm1_delay_ms/us()` |
| Keys | `fm1_in.notes` (27-bit held), `fm1_input_note_edges()` |
| Buttons | `fm1_in.buttons`, `fm1_input_edges(&released)` |
| Encoders | `fm1_enc_take(ENC_x)` detents since last call, + = clockwise |
| Pots | `fm1_adc_read(FM1_ADC_MASTER / FM1_ADC_BATT)` 0..1023 (-1 not ready); platform already applies MASTER as volume |
| LEDs | `fm1_led_key(id, on)`, raw `fm1_led[col]`, `fm1_led_dim[col]`, breathe/mid layers in `hal/fm1_input.h` |
| Screen | `lcd_fill`, `draw_text_box(x,y,w,&FONT_S/L,"txt",colour,align)`, canvas: `cv_begin/cv_rect/cv_line/cv_pset/cv_text/cv_blit` (`CV_MAX` 240x64 by default), `RGB(r,g,b)` |
| MIDI | `midi_get(&st,&d1,&d2)`, `midi_send(st,d1,d2)` (main loop only). SysEx belongs to the platform updater |
| Settings | `settings_load/save(p, n<=256)` with CRC32 in one 4 KiB sector |
| Flash (own data) | widen `FL_RANGE_OK` to your range; `fl_erase4k`, `fl_write`, `fl_verify_xip` in `hal/fm1_flash.h` |
| System | `fm1_wdt_feed`, `fm1_reboot`, `fm1_enter_uboot` (writes `"usb_update_mode"` to the mailbox and resets: ROM USB boot) |

Build options (before `#include "usb.c"` in platform.c): `FELUCCA_UAC` (USB audio, default 1), `FELUCCA_CDC` (serial console, default 0 in Dinghy; some hosts then hide audio), `FELUCCA_OTA` (**leave on**), `FELUCCA_FLASH`, `FELUCCA_UART`, `FELUCCA_CPU2`.

Hardware register access is allowed **only inside `hal/`**. Put a helper there; the build fails on raw addresses elsewhere.

---

## 5. The chip's rules (enforced by Dinghy's build)

- **Integers only.** No `float`/`double` (no FPU, no libgcc: link fails). Use Q15 levels, Q12 gains, 32-bit phase accumulators (`inc = f * 2^32 / 44100`). Precompute constants on the host.
- **No 64-bit division or modulo** (`__udivdi3` missing). 64-bit multiply is fine.
- **Division by zero does not trap**; it yields a wrong value. Guard divisors.
- **No calls or constants in the chip ROM window** `0xFFC00000..0xFFCFFFFF`. A constant like `-32767 << 7` = `0xFFC00080` triggers the check; restructure the arithmetic.
- **No hardware register access outside `hal/`**, no inline asm outside it.
- **Code in `.ram_text` (flash driver) must not call anything** and touches only SFRs, stack and RAM buffers.
- Image, RAM and pool limits are checked; `build/*.dis` is the disassembly to look up crash PCs.
- Audio ISR: no flash, no screen, no `platform_poll`, no waiting. Compute envelopes/filter coefficients once per 16-32 frames. Target under half the 5.8 ms budget; time it with `fm1_ticks()`.

---

## 6. Build, package, install (Path A)

Prerequisites (Linux x86-64; macOS/Windows need Docker or WSL):

```sh
pip3 install Pillow mido python-rtmidi
tools/get_toolchain.sh                         # JieLi clang 4.0.1 pi32v2 -> ~/.jieli/toolchain   (UNVERIFIED here: host unreachable)
git clone --depth 1 --branch AC79NN_SDK_V1.2.1_2023-12-13 \
    https://gitee.com/Jieli-Tech/fw-AC79_AIoT_SDK.git ~/fw-AC79_AIoT_SDK
# only 3 SDK files are used: cpu/wl82/tools/uboot.boot, cfg_tool.bin, cfg/eq_cfg_hw.bin
```

Env overrides: `JIELI_TOOLCHAIN`, `AC79_SDK`. Build checks the SHA-256 of SDK files (`uboot.boot` `4e3b4c22...`, `cfg_tool.bin` `27657995...` in Dinghy).

```sh
tests/run_host.sh        # Dinghy: run the app on the PC -> build/host/*.wav + screen PNGs (no hardware)
./build.sh               # -> build/<name>.fwsc, fails on bricking mistakes
./build.sh --release 0.2 # identity FM-1_992, version string 0.2
python3 tools/fm1_install.py build/<name>.fwsc   # USB-MIDI install (--info to read identity)
```

Compiler flags (Dinghy): `-target pi32v2 -Os -ffunction-sections -fno-builtin`, linked with `firmware/app.ld`, entry via `crt0.S`. `app.bin` is wrapped by `fm1pkg_make.py` into a `.fwsc`:
- `flash.bin`: head `[0,0x4000)` (SDK header, JLFS entries, SPL `uboot.boot`, isd_config blob that decodes to chip key **0x980F**) plus the app area (app_area_head, `app.bin`, `cfg_tool.bin`, `eq_cfg_hw.bin`, region descriptors), SFC-encrypted with the chip key. All integrity checks are CRC16 (poly 0x1021, init 0).
- `ota.bin`: your update loader (loader linked at `0x01C0A800`, max ~0x14000 bytes).
- UFW container, chip tag `AC791N`, identity string embedded one marker byte per 0x30-byte block.

### Package identity (`FM-1_9NN`)

Installers and the hub tell firmwares apart by it. Taken: `900` SLOOP / ORBIT, `91N` Felucca, `93N` sloopDX, `97N` zp12, `98N` Doom, `99N` Dinghy; `000` ORBIT rescue; `015` stock V15 (also what RemoteFM1/TransitFM1 impersonate so any installer will overwrite them). Keep the `FM-1_9NN` form so web installers can resume a cut-off install (they only resume loaders they know). Pick yours in `tools/build.py` (`PRODUCT`).

### Host (emulator) development loop

- Dinghy: `tests/host.c` runs the same app source on the PC (screen as PPM->PNG, audio as WAV).
- Felucca/ORBIT: `web/emu/build.sh` compiles the firmware C to WebAssembly (Emscripten) against a simulated FM-1; ORBIT also has `tools/orbit_preview.py` and a C sequencer/DSP render test (`tests/regress.c` golden hashes + CPU cost budget).
- OpenIFW-fm1 and fm1_open run their device `app.c` via WASM.
- **RemoteFM1** (`Quixotic7/RemoteFM1`): flash once, then the FM-1 is just a USB panel (keys = notes ch16, buttons = notes ch15, encoders = relative CC 16-22, MASTER = 14-bit CC 7/39, screen as 16x16 tiles over SysEx or vendor bulk) for a firmware running on the PC (`.fm1core`, via FM1VST). No reflashing per iteration. Stock V15 cannot run on the host.
- CPU time on hardware is the real constraint: host runs do not model it. Measure `fm1_ticks()` deltas on the device.

---

## 7. Non-negotiables for any firmware you ship

1. **Keep an update path.** Never ship without OTA. The platform must still answer the handshake (`F0 00 32 45 00 00 00 40 7F F7` -> identity block) and the upgrade command (`F0 22 24 35 7F F7`, plus `7D` = drop to ROM boot) so users can get off your firmware. Without this the unit is locked to you.
2. **Boot guard + rescue.** Arm the watchdog first (8 s). Count failed boots; after two, enter USB rescue/ROM boot. Holding **OCT-** at power-on must enter rescue (screen says `<NAME> USB RESCUE`, audio off, updater only). Dinghy's `bootguard.h` and `recovery.c` do this; copy them intact.
3. **Write the update record last.** The first sector of a new image is written last so an interrupted write comes back in update mode (3 short LED flashes, black screen).
4. **Only write your own flash range.** Gate every erase/program through `FL_RANGE_OK`. Never write below `0x4000`.
5. **Don't leave stock settings corrupted.** Felucca-family data in `0x97000..0xDFFFF` and `0xFC000` confuses stock V15 when users go back; document `System > Reset Patches` or ship a cleanup.
6. **Transitions**: advise going via stock V15 or TransitFM1 (answers as `FM-1_015`, no sound, refuses oversized foreign packages) when moving between custom firmwares.
7. **Test the recovery on a unit that you can afford to unbrick** and have a plain-USB route (`WL82 UBOOT1.00` + MvaveFM1Unbricker) or the RP2040 Transporter ready.

### Debugging toolbox
- Crash screen: red, shows vector, **PC**, return address -> look up in `build/*.dis`.
- Optional USB CDC console (Felucca `console.c`, `inp` stats command).
- `fm1_fault` stops audio, draws crash data, waits 4 s, reboots.
- Reset reason: `fm1_reset_reason()` -> `fm1_boot.p3_rst` bits: power-on, VDDIO low, WDT, VCM, long-press, 1.2 V, soft.
- Retained RAM at `0x01C7C000` survives resets; `fm1_unbrick.py` saves it as `retained-ram.bin` in UBOOT mode.

---

## 8. Catalog of existing firmwares (from the hub README, by lineage)

Most are GPL-3.0 forks of Felucca (Leo Kuroshita / Hügelton Instruments), often via SLOOP (isod89) or Melodee (keremimo). Nearly all carry web installers + browser emulators.

**Felucca family (38):** Felucca, Felucca [Salt], Melodee, ChoralRoot FM-1, X0X, GHOULBOX 2.0, Jangada, REDACTED, Hortator, April OS, WaveLoop, Rainbow mode, fm1-chord, DUELL, MAKU, Polly, TRIBE, Golana, FANTASMA/Pelucco, Skiff, Felucca 8 Patterns, LCD-4, PIGEON (sampler), NOIZ DEMONS, Tuna, X0X-RMX, DUB-1, Unholy Union, Melodee (Tess), REGGAE-OS, Glitchbox, FM-1 T1, Patricktronics, FMini-1, Clipper, Wavetable Odeath Mod, AmbWave, fm1-studio-tess.

**SLOOP family (22):** SLOOP, sloopDX, FM1 Move, FM1 Quest, JIANT FM, **ORBIT**, NoteSorcery, SLOOP ALG, FM80S, SLOOP DX7 Banks, SLOOP Floyd FM, SLICE64-FM, winampFM, No Man Sky FM, MYCELIUM, GR!MM, TheReFmB1rth, Kawa Tracker, BREAK//174, Loom FM-1, Ravel FM-1, Bunker Evolved.

**Other instruments (60, mixed lineage):** baud girl, Groove OS, Bubba Machine, zp12, FiMba-1, Lunar Modulator, AMB-1, CTL-1, PurpleMonkey, B-Boy Edition, fm1-polyseq, FM-106 (Juno-106 SysEx), ETCH, AMBII, MC-1, OberVave, MONK-1, **m-vave/fm1_open (official)**, OPN-1 (Mega Drive/YM), CS-1, Frodhes, Vector37 / Speak37 / Erik37 (SMK-37 ports), HYP-1 / LOF-1 / ECO-1 / GRAV-1, Tonitor, BEETLE, FOMAJAM, MIN-1, Pocket GammaWave, TERKINSTEIN, Niagara Drift, MNM-1, SIDOU (SID), TripDeck, Evander's Music Box, P6, FMEL-1, MD-One, LOOM-8, Hersen MPC, GRAN, SID-1, Shine On, B1 Drawbar Organ, fm1-gator, Mutable Dreams, Prysm, fm_lab, Bytemania, Selva1, ZEN-1, 386 DX KaraokeBot, fm1-gm, BOP-1, kidboy, FoMni-1, FuMi-1, CoralFlower, Pocket Guitar.

**Platforms / builders:** fm1-rocket-os (clip launcher), **Optimist** (modular build-your-own: engines ANALOG 2, DIGITAL, PHASE, LOFI, SAMPLE, VOICE, TRIO, WHEEL, GRAIN, FM6, SLICE, PHYS, ACID, with live flash/RAM budget), **Dinghy** (template), Modular-1 (Nord-Modular-style patcher), Hexagon Console (teased), OpenIFW-fm1 (WASM host sim + installer, `FM-1_982`).

**Non-audio / experiments:** FM-1 Doom (`98N`), FM-1 NES (bare metal), Mocky (bitmap display over MIDI), fm1-mdx (X68000 MDX player), GameDude (Game Boy emu, Peanut-GB), Fart Machine One, Trumpagotchi, Trireme (USB HID keyboard/macropad with Vial), **RemoteFM1** (thin client).

**Binary patchers of stock V15:** czietz patcher (detune/aftertouch/colours), smememe macropad patch (55-input MIDI macropad).

**Related devices:** SMK-37 / Pro shares the same SoC, bootloader, loader and chip key (different matrix/pins/flash map). Several firmwares are ports (genkigenki's `fm1-to-smk37` port kit, hub at genkigenki.github.io/smk37). Don't assume pin maps carry over.

**Technical building blocks you can reuse:**
- DSP engines (MIT, `Felucca-Engines` submodule): DRUM, NOISE, PHYS (DaisySP/Rings), FM6 (msfa/Dexed, Apache-2.0), SLICE, PHASE, GRAIN, SAMPLE (CC0 Versilian samples), DIGITAL (FM4->FM6).
- DX7 SysEx: bulk bank 4104 bytes, single voice, Dexed parameter-change SysEx accepted by stock.
- Felucca editor SysEx protocol over USB-MIDI (`web/EDITOR_PROTOCOL.md`; v7+, 104 parameters, motion/p-locks, `BACKUP_LIST/GET/PUT`). ORBIT has its own (`web/EDITOR_PROTOCOL.md`, ORP7 projects / OPB2 banks). Always read capability blocks from `INFO`, don't hardcode parameter ids.
- Sample upload: `tools/fm1_sample_upload.py`, `sampleio.py` (ORBIT), 4 user slots; PIGEON has its own sample tool.
- Stock M-VAVE FM1 SysEx: handshake only answers parameter id `0x40`.

---

## 9. Licensing and credit

- Felucca-family code: **GPL-3.0-only**. Keep copyright headers (Leo Kuroshita, Hügelton Instruments; isod89 for SLOOP; keremimo for Melodee), `LICENSING.md`, ship corresponding source with every release. Engines MIT; msfa/Dexed Apache-2.0; AC79 SDK files Apache-2.0 (travel with the package).
- fm1_open: GPLv3 **with the FM1 SDK linking exception**; the engine library is a separate binary SDK with its own terms; distribution builds need `FM1_SOURCE_URL` to a matching source archive.
- fm1-nes: Apache-2.0. Doom: GPL-2.0+/3.0.
- OP-1 derived tables (ORBIT CLUSTER) keep Teenage Engineering's rights; samples need their own attribution (`ATTRIBUTION.txt`).
- To list in the FM-1 Firmware Hub (fm1.designburgapps.com): public GPL source, GitHub releases each with a `.fwsc`, a screenshot, and ask via the hub's card.

---

## 10. Starting recipe (do this in order)

1. Take the flash backup (see the `mvave-fm1-firmware` skill, section 5).
2. Clone Dinghy, run `tests/run_host.sh` unchanged, confirm WAV + PNGs.
3. Install the toolchain + SDK files, run `./build.sh` unchanged, read the size report.
4. Change `app_audio()` / `app_main()` only; host-run after every change.
5. Choose your `FM-1_9NN` identity and `APP_NAME`; build with `--release`.
6. Install on a unit with a known recovery path; verify `fm1_install.py --info` shows your identity; then test: OCT- rescue, a deliberate crash (two boots -> rescue), power-cycle mid-install if you can, install of another firmware over yours, return to stock V15.
7. Time the audio ISR on hardware; leave headroom for USB and key scan.
8. Only then publish: tag, `.fwsc`, `SHA256SUMS`, source archive, notes with identity and tested-on-hardware status (be explicit about what was and was not tested, as ORBIT does).

## 11. Pitfalls collected from the repos

- A custom firmware without OTA/rescue = permanent lock-in. Don't.
- Flashing custom over custom without a stock/TransitFM1 stop has bricked units (TransitFM1 0.1.2 was withdrawn after a unit was left dark).
- `-32767 << 7` style constants can hit the ROM-address check.
- Saving settings while notes ring causes dropouts.
- Felucca 0.9-beta -> 1.0.x data layout clash can soft-brick; fix is erasing `0x97000+0x8000` and `0xFC000+0x2000` in UBOOT mode (deletes user data).
- Update interrupted by a flat battery can leave a unit with no USB device at all; only the RP2040 Transporter / Flipper recovery helps.
- Windows-only official build (fm1_open) pins JieLi toolchain **2.5.3** and checks all 22 toolchain files against `sdk/manifest.json`; older kits pin 2.5.2.
- macOS lacks a SCSI backend for `jl-uboot-tool`; use Linux/Windows for raw flash work. In toolbox containers, host-side `modprobe sg` and `chmod 666 /dev/sg0` are needed (see the `mvave-fm1-firmware` skill, section 10).
- Project/sample formats are not interchangeable between firmwares; keep per-firmware backups.

## 12. Local build container (`docker/`)

`docker/` + `mvave-build.sh` give a podman image with the JieLi toolchain, so nothing is installed on the host.
Usage and status are in `readme/build-container.md`. Short form: `./mvave-build.sh fetch-vendor && ./mvave-build.sh image && ./mvave-build.sh clone dinghy && ./mvave-build.sh build dinghy` -> `out/dinghy/dinghy.fwsc`.
Verified: base layer + Dinghy host mode (WAV/PNG) and the hash guard. **Not verified**: the toolchain stage and a real `.fwsc`, because JieLi's hosts (`pkgman.jieliapp.com`, `gitee.com`, Aliyun OSS) were unreachable from this network (the first replied "Connection denied by Geolocation", the others failed TLS/connect). Pinned hashes (toolchain `f686586b...`, from Optimist) mean files obtained elsewhere can be dropped into `docker/vendor/` safely. Never bypass certificate checks.
