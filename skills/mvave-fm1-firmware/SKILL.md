---
name: mvave-fm1-firmware
description: Back up, flash, restore and recover firmware on the M-VAVE FM-1 (JieLi AC791N / WL82). Use when asked to back up the FM-1, install custom firmware such as ORBIT, go back to stock V15, or unbrick a unit. Covers the SysEx OTA protocol, flash map, tooling, safety rules and the exact order of operations.
---

# M-VAVE FM-1: backup, flash, restore (skill)

Sources researched: `aroum/fm1-custom-fw` (resource hub + REVERSE_ENGINEERING.md), `dspaudio/orbit` (ORBIT 0.7.1 firmware and installer), `Quixotic7/MvaveFM1Unbricker` (flash backup/restore tool).

## 1. Hardware facts

| Item | Value |
|---|---|
| SoC | JieLi AC7911B (AC791N / WL82 family), pi32v2 core, QFN-48 |
| Flash | 1 MiB SPI NOR (Puya P25Q80H), JEDEC ID `0x856014`, chip key `0x980F` |
| Display | 240x240 TFT |
| Execution | XIP from SPI flash |
| Recovery buttons | None on PCB. Recovery relies on firmware (OCT-) or the chip's mask ROM |
| Signature check | None (no RSA/ECDSA). Only container header, size and CRC/byte checksums |

### Flash map (1 MiB)

| Range | Contents | Rule |
|---|---|---|
| `0x00000-0x03FFF` | Boot head (UBOOT/SPL) | **NEVER write or erase.** Everything depends on it |
| `0x04000-0x92FFF` | Firmware app (0x8F000 bytes). Stock V15 lives here | What installers rewrite |
| `0x93000-0xE8FFF` | Stock settings store. Felucca-family firmwares keep songs/sounds at `0x97000-0xDFFFF` | Contains user data |
| `0xE0000` | Staged update loader (Felucca family) | |
| `0xE9000` | Bluetooth data | |
| `0xEA000-0xFBFFF` | Factory voices | |
| `0xFC000-0xFEFFF` | Globals (Felucca family) | |
| `0xFF000-0xFFFFF` | Reserved | |

## 2. Device states and USB identities

| State | How it appears | Notes |
|---|---|---|
| Normal firmware | USB-MIDI device, port name contains `FM-1` | SysEx handshake answers identity `FM-1_015` (stock V15), `FM-1_900` (ORBIT) |
| OTA loader | USB `4D4A:4155`, name `ota-FM-1...` | Entered during an update. ORBIT's loader is `ota-FM-1_9XX` |
| Mask-ROM boot | USB `4C4A:8057`, SCSI disk `WL82 UBOOT1.00` | Needed for raw flash read/write. **Never format this disk** |
| Dead (no USB at all) | Nothing enumerates | Needs hardware: FM-1 Transporter (RP2040) or Flipper Zero |

Ways into mask-ROM boot (`WL82 UBOOT1.00`):
1. Software, unit still running stock V15 or Felucca family: send SysEx `F0 22 24 35 7D F7` (`fm1_unbrick.py softkey`). Writes nothing, a power cycle undoes it.
2. Crash guard: three quick power-on/off cycles with a crashing firmware, or leave a hung unit on for 2 minutes (watchdog + boot-loop guard).
3. Hold OCT- and OCT+ at power-on for 10 s (update mode if firmware reaches its main loop).
4. ORBIT/Felucca "USB rescue boot": hold **OCT-** at power-on.

## 3. SysEx protocol (from REVERSE_ENGINEERING.md and `orbit/tools/fm1_install.py`)

- Handshake query (host to device): `F0 00 32 45 00 00 00 40 7F F7`. Device answers with a 34-byte (unpacked) identity block starting `00 59 11`, text like `FM-1_015`. Only parameter ID `0x40` answers.
- Enter upgrade: `F0 22 24 35 7F F7`. Soft-key to ROM boot: `F0 22 24 35 7D F7`.
- Wire packing: 8-bit data packed into 7-bit bytes, LSB-first bitstream (7 wire bytes per 8 data bytes).
- Update is **device-pull**, not host-push:
  1. Step 1: running firmware pulls parts of the package, writes a JieLi `UPDATA_PARM` record, reboots into the OTA loader.
  2. Step 2: loader pulls the whole logical image (header, entry list descending, then bulk ascending). The host just answers read requests.
  3. Completion: device requests address `0xF0000000`, host replies `"success\0"`. Device reboots.
- Read request (unpacked, 15 bytes): `00 59 30 | ... | flags | addr(4 LE) | len(3 LE) | checksum`. Checksum is `~sum(bytes[6:14]) & 0xFF`.
- Response body: `00 59 30, len+8 (2 LE), 0, flags, addr(4 LE), len(3 LE), data..., checksum`. Max 512 data bytes per response.
- `.fwsc` package: 0x30-byte blocks, the first 20 each carry one marker byte at offset `0x2F` that encodes the package identity (`FM-1_900`). The "logical image" is the package with those 20 bytes removed. Containers carry `@JMUA` / `JLUFW` signatures and target tag `AC791N`.

## 4. Tooling

| Tool | Purpose | Needs |
|---|---|---|
| `src/orbit/tools/fm1_install.py` (from ORBIT; `./mvave-build.sh clone orbit`) | Install `.fwsc` over USB-MIDI, `--info` reads identity only | Python, `mido`, `python-rtmidi` |
| ORBIT web installer, https://dspaudio.github.io/orbit/ | Same, in Chrome/Edge over Web MIDI | Chrome/Edge, SysEx permission |
| `Quixotic7/MvaveFM1Unbricker` `fm1_unbrick.py` | **Full 1 MiB flash backup** (double read, compared), restore stock V15, soft-key, repair-settings | Linux root + `sg` module (`sudo modprobe sg`), `jl-uboot-tool` (fetched by `setup`) |
| `kagaimiq/jl-uboot-tool` | Raw read/write of WL82 flash in UBOOT mode | Same |
| FM-1 Transporter (RP2040), Flipper Zero recovery | Hard-brick, nothing enumerates | Hardware |
| TransitFM1 (quixotic7.github.io/TransitFM1) | Bridge firmware for switching between custom builds | |

Important gaps to remember:
- **ORBIT's "Backup" saves projects and presets only (ORP7/OPB2). It does NOT back up the existing firmware.** A firmware backup requires the full-flash dump via `fm1_unbrick.py backup` (UBOOT mode).
- Stock V15 can be restored from M-VAVE's official `FM-1.fwsc` (https://www.m-vave.com/product?id=fm-1). Expected: identity `FM-1_015`, firmware-region SHA-256 `6edf3c37fb5bbbc33607c89375ee024d5477c17914d72221c8c68e58a8255686` (region `0x4000..0x92FFF`).
- macOS is not supported for the UBOOT tools (no SCSI back end). Linux works as root.

## 5. Procedure: back up, then install ORBIT

Community guidance: do not flash one custom firmware directly over another. Go through stock V15 first, or use TransitFM1.

### 5.0 Preconditions
- USB **data** cable, plugged in **directly** (no hub). Avoid docks and hub chains.
- Battery or mains power stable for the whole write.
- Chrome/Edge or Python with `mido`+`python-rtmidi`.
- Have `FM-1.fwsc` (stock V15) downloaded so you can roll back.
- Have ORBIT's package: `curl -LO https://github.com/dspaudio/orbit/releases/download/v0.7.1/orbit.fwsc` and `SHA256SUMS` from the same release, then `sha256sum -c SHA256SUMS` from inside that folder (v0.7.1 was `842a69569eaedd0e063e8caa13e7de5f6fb0412bed5b6fccbf11ed3dbdd8c68d`).

### 5.1 Identify what is on the unit
```sh
python3 -m venv .venv && .venv/bin/pip install mido python-rtmidi
.venv/bin/python src/orbit/tools/fm1_install.py --info
```
Read-only. Reports the connected identity (e.g. `FM-1_015`).

### 5.2 Back up the existing firmware and data (full flash)
```sh
git clone https://github.com/Quixotic7/MvaveFM1Unbricker
cd MvaveFM1Unbricker
python3 -m venv .venv
.venv/bin/python fm1_unbrick.py setup
sudo modprobe sg
.venv/bin/python fm1_unbrick.py softkey        # unit on normal screen; type UBOOT. Drops it to WL82 UBOOT1.00
sudo .venv/bin/python fm1_unbrick.py find      # expect exactly one WL82 UBOOT1.00
sudo .venv/bin/python fm1_unbrick.py info      # must show chip key 0x980F and flash ID 0x856014
sudo .venv/bin/python fm1_unbrick.py backup ../backups/fm1-$(date +%Y%m%d)
```
`backup` reads the 1 MiB flash twice, compares the reads, and prints a SHA-256. If the two reads differ, change the cable/port and retry. Nothing is written by `backup`. Copy the dump somewhere safe and record its SHA-256.

If the unit still has its own projects/presets under custom firmware, also export them from that firmware's editor (Projects / Backup).

Do NOT run `restore` as part of backing up. It writes.

### 5.3 Install ORBIT
Power cycle the unit back to normal mode (unplug, off, wait 5 s, on). Then either:

```sh
.venv/bin/python src/orbit/tools/fm1_install.py downloads/orbit.fwsc
```
or use https://dspaudio.github.io/orbit/ in Chrome/Edge.

The installer checks the model and package before writing. Flags: `--port NAME`, `--yes`, `--force`. Exit codes: 0 done, 1 cancelled/error, 2 bad args or package, 3 FM-1 not found, 4 connection lost, 5 timeout, 6 wrong model/identity mismatch/foreign loader.
Keep USB and power connected through the write and reboot. Afterwards `fm1_install.py --info` should report `FM-1_900`.

ORBIT status: its own README says 0.7.1 was software-tested only and 0.7.0's install/version/PING were verified on an FM-1; power-loss recovery is unverified. Independently, one owner installed the 0.7.1 release on a stock-V15 unit with this procedure (identity became `FM-1_900`) and reports the firmware works.

### 5.4 Recovery and rollback
- Interrupted write: power-cycling re-enters update mode (3 short LED flashes, black screen). Re-run the installer, it resumes only if it recognizes ORBIT's loader (`ota-FM-1_9XX`).
- Hold **OCT-** at power-on for ORBIT's rescue update screen (`FM-1_000`).
- Black screen but `WL82 UBOOT1.00` visible: `sudo .venv/bin/python fm1_unbrick.py restore FM-1.fwsc` (writes only `0x4000..0x92FFF`, type `WRITE`, verifies byte for byte). If verify fails, **do not power off**, rerun.
- Back on stock but presets corrupted: stock **System > Reset Patches**; else `softkey` then `repair-settings --factory DUMP.bin` (needs a clean factory dump; untested on a real unit).
- Nothing enumerates: FM-1 Transporter (RP2040, wire D6/D7/GND) or Flipper Zero recovery.
- Restoring the full backup: restore firmware region with `restore`; user data regions can be written back sector by sector with jl-uboot-tool, never touching below `0x4000`.

## 6. Safety rules (hard)
1. Never write or erase below `0x4000`. Never `erasechip`.
2. Always take a verified (double-read) backup before any write.
3. Write the extracted firmware region at `0x4000`, never the raw `.fwsc` into flash.
4. Only operate on a device that reports as `WL82` with key `0x980F` / flash ID `0x856014`. One device at a time.
5. Cancel any OS "format disk" prompt for `WL82 UBOOT1.00`.
6. Custom firmware must keep a bootloader/OTA re-entry path, otherwise the unit can be locked out of MIDI updates.
7. Do not flash custom over custom without going via stock V15 or TransitFM1.
8. Never power off after a failed verify.

## 7. ORBIT quick reference
- 4-track groovebox: 3 synths + drums, Event Tape, 17 engines / 189 sounds, USB audio, USB/TRS MIDI, 16 MIDI-learn slots.
- Controls: HOME = Tape/Visualizer, GLO = Mixer, hold HOME = settings (SCREEN/LIGHTS/AUDIO/SYSTEM), OCT- at power-on = recovery.
- Projects saved as ORP7, preset banks as OPB2. Older ORBIT (<0.7.0) cannot read them and its autosave may overwrite. SLOOP 2.6 FUN6 files are rejected.
- Editor and installer: web, Chrome/Edge, Web MIDI with SysEx.
- Build from source needs the pi32v2 toolchain (`tools/get_toolchain.sh`) and AC79 SDK `AC79NN_SDK_V1.2.1_2023-12-13`; use `sh build.sh`, **not** `--release`. Output `build/orbit.fwsc`. GPL-3.0-only.

## 8. Host-side notes (Linux)
- Needs `mido` + `python-rtmidi` in a venv. `lsusb` may be missing (toolbox containers); use sysfs (`/sys/bus/usb/devices/*/idVendor`) to spot `4c4a:8057`, `4d4a:4155`.
- ALSA sequencer `/dev/snd/seq` must exist (needed by rtmidi).
- UBOOT tools need root and the `sg` kernel module.
- Keep flash dumps (`backups/`) outside any public repo: they contain your device's songs, sounds and settings.

## 9. Reference links
- Hub: https://github.com/aroum/fm1-custom-fw
- ORBIT: https://github.com/dspaudio/orbit and https://dspaudio.github.io/orbit/
- Unbricker: https://github.com/Quixotic7/MvaveFM1Unbricker
- jl-uboot-tool: https://github.com/kagaimiq/jl-uboot-tool
- Transporter: https://github.com/kurogedelic/FM-1-transporter
- Protocol RE: https://github.com/AL-255/FM-1-RE, stock bootloader source https://github.com/jvitkauskas/fm1-bootloader
- Community: https://www.reddit.com/r/MVaveFM1/

## 10. Lessons from a real run (toolbox container, Fedora host)
- Running inside a toolbox/distrobox: `modprobe` must run on the host (`distrobox-host-exec sudo modprobe sg`). `/dev/sg0` shows as `nobody:nogroup` in the container and even container root cannot open it. Fix: `distrobox-host-exec sudo chmod 666 /dev/sg0` after **each** time the device re-enumerates, then run the tool as the normal user.
- `fm1_unbrick.py softkey` needs `--yes` when there is no TTY.
- A boot-mode session lasts roughly one tool run. Running `info` and then `backup` separately made the chip reset (`host status:07`, `ENODEV`) and the FM-1 returned to normal USB `4c4a:c755`. Run `backup` directly right after `softkey` + `chmod`, and re-do both if the node disappears.
- USB ids seen: normal `4c4a:c755` (FM-1, MIDI + audio), boot mode `4c4a:8057` (`WL82 UBOOT1.00`).
- One unit reporting `FM-1_015`: firmware region `0x4000..0x92FFF` SHA-256 `8c1d13a5934eb3c70a5fec644577618a31b2a96c8748a7b692c506a86505dbb1`. This does **not** equal the documented official-V15 region hash (`6edf3c37...`), so do not rely on `restore --verify-v15` to reproduce that unit byte for byte; the dump is the true rollback source.
- Install result (2026-10-22): `fm1_install.py orbit.fwsc --yes` took the unit from `FM-1_015` to `FM-1_900` (ORBIT 0.7.1) with exit 0. Pipe output through `tr '\r' '\n' | tail` to avoid the huge progress line. Run the checksum from inside the package folder (`sha256sum -c SHA256SUMS`).
