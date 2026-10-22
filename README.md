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
ORBIT 0.7.1 install with the unit reporting `FM-1_900` afterwards (screen/audio were not inspected).
Verified in the container: base image, Dinghy host mode, the vendor hash guard.
CI (GitHub Actions, run on 2026-10-22): the full image built with JieLi's toolchain (hash-verified) and **Dinghy and ORBIT
built real `.fwsc` packages** in it. Felucca failed on a missing Pillow text-layout library (libraqm); fixed in the Containerfile and
checked locally, but its full build has not yet passed in CI. None of those packages has been flashed from this container's output.
**Not verified:** a flash of a container-built package, ORBIT's behaviour on the unit (screen/audio were not inspected),
rollback from a custom firmware, and the claims taken from other repos' documentation.
The firmware catalog in the development skill comes from the community hub README; only the platform bases were read in depth.

## Sources
`aroum/fm1-custom-fw` (hub), `hugelton/Felucca`, `zvenson/dinghy`, `dspaudio/orbit`, `Quixotic7/MvaveFM1Unbricker`,
`m-vave/fm1_open`, `Keitark/fm1-nes`, `Quixotic7/RemoteFM1`, `Quixotic7/TransitFM1`, `kagaimiq/jl-uboot-tool`.
Those projects keep their own licences (mostly GPL-3.0). **This repo's own text has no licence yet (so, by default, all rights reserved): the owner should add one.**
