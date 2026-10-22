# FM-1 firmware build container

Podman image that builds Felucca-family FM-1 firmwares (Dinghy, Felucca, ORBIT, SLOOP, Optimist...) without installing
JieLi's toolchain on the host. Driven by `../mvave-build.sh`.

```sh
./mvave-build.sh fetch-vendor     # JieLi toolchain + 3 SDK files -> docker/vendor/ (hash-verified)
./mvave-build.sh image            # build the image (needs vendor/ filled)
./mvave-build.sh clone dinghy     # sources into src/
./mvave-build.sh run dinghy tests/run_host.sh      # host-mode run: WAV + PNG screens, no toolchain needed
./mvave-build.sh build dinghy     # -> out/dinghy/dinghy.fwsc
./mvave-build.sh build orbit      # ORBIT 0.7.1 identity FM-1_900 (never pass --release for ORBIT)
```

Flash the result from the host (not from this container): see `../skills/mvave-fm1-firmware/SKILL.md` (back up first).

## What is in the image
Debian bookworm, JieLi pi32v2 clang 4.0.1 (`/opt/jieli`, version 20250324.1), the three AC79 SDK files
(`/opt/ac79`, tag AC79NN_SDK_V1.2.1_2023-12-13), Python venv with Pillow 12.2.0 + fonttools, gcc, make, git.
`JIELI_TOOLCHAIN` and `AC79_SDK` are preset, so each project's own `build.sh` runs unchanged (it uses the toolchain natively
because the container is Linux x86-64).

## Verified here (2026-10-22)
- base layer builds; Dinghy host mode runs in it (`run dinghy tests/run_host.sh` -> `dinghy.wav` + PNGs);
- the image build rejects missing and wrong-hash vendor files.

## NOT verified here
- The toolchain stage and a real `.fwsc` build: JieLi's servers (`pkgman.jieliapp.com`, `gitee.com`, the Aliyun bucket)
  were unreachable from this network (geo-block / TLS failure), so `fetch-vendor` could not run. Run it on a network that
  can reach them, or copy the four files into `docker/vendor/` (see `docker/vendor/README.md`), then `image` and `build`.
- Never disable certificate checks to get past that; the hashes pin the files.

## Notes
- Runs with `--userns=keep-id` and `:Z` volume labels, so Fedora/SELinux works and outputs belong to you.
- Keep the image local: JieLi's licence does not allow redistributing the toolchain. Do not `podman push` it.
- Not covered: `m-vave/fm1_open` (needs the Windows toolchain 2.5.3 and PowerShell) and `fm1-nes` (own toolchain/jl-uboot flow).
