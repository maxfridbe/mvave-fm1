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

## Sources
`aroum/fm1-custom-fw` (hub), `hugelton/Felucca`, `zvenson/dinghy`, `dspaudio/orbit`, `Quixotic7/MvaveFM1Unbricker`,
`m-vave/fm1_open`, `Keitark/fm1-nes`, `Quixotic7/RemoteFM1`, `Quixotic7/TransitFM1`, `kagaimiq/jl-uboot-tool`.
Those projects keep their own licences (mostly GPL-3.0); nothing from them is copied here, and the scripts download them at use time.
JieLi's toolchain is not redistributable and is never included or pushed.

## Licence
MIT, see `LICENSE`: this repo's own text, scripts and workflow.
