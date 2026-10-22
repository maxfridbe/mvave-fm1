# vendor/

Files the image needs from JieLi. They are not in this repo (JieLi's licence does not allow passing the toolchain on).
`../mvave-build.sh fetch-vendor` downloads and verifies them; or put them here yourself:

| File | SHA-256 | From |
|---|---|---|
| `jieli-linux-toolchains-20250324.1.tar.xz` | `f686586bcfb45e0f0bb27fd2b39c7a7f313cb4f0e88a66a14da621ffa8225958` | https://jl-update.oss-cn-shenzhen.aliyuncs.com/jieli-linux-toolchains-20250324.1.tar.xz |
| `uboot.boot` | `4e3b4c220dc96641cb5a723f41e68ce41d5261ae9434bb33fbd7f2c59976ded4` | `cpu/wl82/tools/uboot.boot` at tag `AC79NN_SDK_V1.2.1_2023-12-13` of https://gitee.com/Jieli-Tech/fw-AC79_AIoT_SDK |
| `cfg_tool.bin` | `276579954f076886a6a7694f65dc71c034a63a2c204b76749065c0ac7b010d1b` | `cpu/wl82/tools/cfg_tool.bin`, same tag |
| `eq_cfg_hw.bin` | `41167491bffed4651750719c973d2758adeb9021a5670d02d6a53c85ed80ea7d` | `cpu/wl82/tools/cfg/eq_cfg_hw.bin`, same tag |

The image build refuses any file whose hash differs. These hashes are the ones the Optimist firmware project pins.
If JieLi's servers refuse your network (they geo-block some regions), download the files on another machine and copy
them here; do not disable certificate checks.
