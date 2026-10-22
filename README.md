# mvave-fm1

A starting point for working with the **M-VAVE FM-1** synthesizer (JieLi AC791N): back it up, flash community firmware,
recover it, and write your own firmware. Written as [Claude Code](https://claude.com/claude-code) skills plus a podman
build container. Nothing here is affiliated with M-VAVE. Flashing firmware is at your own risk.

```
skills/
  mvave-fm1-firmware/              back up, flash (ORBIT example), restore, unbrick; protocol, flash map, safety rules
  mvave-fm1-software-development/  write firmware: hardware API, memory map, chip rules, build/package, firmware catalog
readme/
  build-container.md               how the build container works and what is verified
docker/
  Containerfile                    podman image: JieLi pi32v2 clang + SDK files + Python/Pillow + gcc
  vendor/README.md                 the JieLi files you must supply (hash-pinned; not in this repo)
mvave-build.sh                     fetch-vendor | image | clone | build | run | shell | check
```

## Use the skills
Copy (or symlink) the folders in `skills/` into `~/.claude/skills/` (or a project's `.claude/skills/`). They are also plain
Markdown: read them directly.

Order of work: **back up first** (`mvave-fm1-firmware`, section 5.2), then flash, then develop.

## Build firmware in a container (also what CI does: `.github/workflows/build.yml`)
```sh
./mvave-build.sh fetch-vendor        # on a network that can reach JieLi's hosts; or copy the files into docker/vendor/
./mvave-build.sh image
./mvave-build.sh clone dinghy
./mvave-build.sh run dinghy tests/run_host.sh    # try an idea on the PC: WAV + PNG, no toolchain needed
./mvave-build.sh build dinghy                    # -> out/dinghy/dinghy.fwsc
```
Flashing happens on the host with the installers described in the firmware skill, never inside the container.

## Status: what is and is not verified
Verified on real hardware (one FM-1, Linux): identity read, full-flash double-read backup via MvaveFM1Unbricker, and an
ORBIT 0.7.1 install (upstream release package) with the unit reporting `FM-1_900` afterwards. The owner then tested the installed
firmware and reports it works (their report; no measurements recorded here).
CI (GitHub Actions, 2026-10-22, run 39823372989): the full image built with JieLi's toolchain (hash-verified) and **Dinghy, Felucca
and ORBIT all built without a failing step** (an initial run exposed a missing Pillow text library, libraqm, now in the Containerfile).
The `fwsc-packages` artifact is 1.35 MB zipped, consistent with three packages, but I could not download it to inspect it. No
package built here has been flashed.
**Not verified:** a flash of a container-built package, rollback from a custom firmware to stock, and the claims taken from other repos' documentation.
The firmware catalog in the development skill comes from the community hub README; only the platform bases were read in depth.

## Sources and related repos
Read in depth while writing the skills:

| Repo | What it is | Licence (per its repo) |
|---|---|---|
| [aroum/fm1-custom-fw](https://github.com/aroum/fm1-custom-fw) | Community hub: catalog of ~130 firmwares, hardware teardown, SysEx/OTA reverse-engineering notes | see repo |
| [hugelton/Felucca](https://github.com/hugelton/Felucca) | The hardware layer and platform most community firmwares fork | GPL-3.0 |
| [zvenson/dinghy](https://github.com/zvenson/dinghy) | Smallest Felucca-based template: a sine synth plus updater, USB rescue, MIDI, audio, host mode | GPL-3.0 |
| [dspaudio/orbit](https://github.com/dspaudio/orbit) | ORBIT groovebox firmware (the one flashed in the example); web installer at [dspaudio.github.io/orbit](https://dspaudio.github.io/orbit/) | GPL-3.0 |
| [isod89/sloop-fm1](https://github.com/isod89/sloop-fm1) | SLOOP, the groovebox ORBIT descends from | see repo |
| [m-vave/fm1_open](https://github.com/m-vave/fm1_open) | M-VAVE's official open firmware and binary SDK (Windows toolchain) | GPLv3 + SDK linking exception |
| [Keitark/fm1-nes](https://github.com/Keitark/fm1-nes) | Bare-metal example (NES emulator), application-only update flow | Apache-2.0 |
| [Quixotic7/MvaveFM1Unbricker](https://github.com/Quixotic7/MvaveFM1Unbricker) | Full-flash backup, restore to stock V15, soft-brick recovery over plain USB | see repo |
| [kagaimiq/jl-uboot-tool](https://github.com/kagaimiq/jl-uboot-tool) | Reads/writes JieLi flash in `WL82 UBOOT1.00` mode (used by the Unbricker) | MIT |
| [Quixotic7/RemoteFM1](https://github.com/Quixotic7/RemoteFM1) | Turns the FM-1 into a USB panel for firmware running on a computer | see repo |
| [Quixotic7/TransitFM1](https://github.com/Quixotic7/TransitFM1) | Safe stopover firmware between two custom firmwares | see repo |
| [w0ts/optimist](https://github.com/w0ts/optimist) | Modular firmware builder; source of the pinned toolchain hashes used in `docker/` | GPL-3.0 |

Pointed to by the skills but not read in depth:
[AL-255/FM-1-RE](https://github.com/AL-255/FM-1-RE) (protocol and firmware reverse engineering),
[kurogedelic/FM-1-transporter](https://github.com/kurogedelic/FM-1-transporter) (RP2040 hard-brick recovery),
[merthsoft/flipper-fm1-recovery](https://github.com/merthsoft/flipper-fm1-recovery) (Flipper Zero recovery),
[czietz/fm1-firmware-patcher](https://github.com/czietz/fm1-firmware-patcher) and
[smememe/fm1-macropad-patch](https://github.com/smememe/fm1-macropad-patch) (binary patches of stock V15),
[kagaimiq/jielie](https://github.com/kagaimiq/jielie) (JieLi chip documentation),
[r/MVaveFM1](https://www.reddit.com/r/MVaveFM1/) (community), and the other firmwares listed in the hub.
Check each repo's own licence before reusing its code.

## Licence
MIT, see `LICENSE`: this repo's own text, scripts and workflow.
