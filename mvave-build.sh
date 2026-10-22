#!/usr/bin/env bash
# Build FM-1 firmwares in a podman container (docker/Containerfile).
#
#   ./mvave-build.sh fetch-vendor        download + verify the JieLi toolchain and SDK files into docker/vendor/
#   ./mvave-build.sh image               build the image (linux/amd64)
#   ./mvave-build.sh image-base          build only the base layer (no JieLi files): enough for host-mode runs
#   ./mvave-build.sh clone [NAME...]     git clone firmware sources into src/ (default: dinghy felucca orbit)
#   ./mvave-build.sh build NAME [ARGS]   run NAME's ./build.sh in the container; copies *.fwsc to out/NAME/
#   ./mvave-build.sh run NAME CMD...     any command in NAME's source dir, e.g. tests/run_host.sh
#   ./mvave-build.sh shell [NAME]        interactive shell
#   ./mvave-build.sh check               show what is installed in the image
#
# Flashing is NOT done here: use fm1_install.py on the host (see skills/mvave-fm1-firmware/SKILL.md).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE="${MVAVE_IMAGE:-mvave-fw-builder:20250324.1}"
VENDOR="$ROOT/docker/vendor"
SRC="$ROOT/src"
OUT="$ROOT/out"
PODMAN="${PODMAN:-podman}"

TC_VER=20250324.1
TC_FILE="jieli-linux-toolchains-$TC_VER.tar.xz"
TC_URL="https://jl-update.oss-cn-shenzhen.aliyuncs.com/$TC_FILE"
SDK_TAG=AC79NN_SDK_V1.2.1_2023-12-13
SDK_URL="https://gitee.com/Jieli-Tech/fw-AC79_AIoT_SDK/raw/$SDK_TAG/cpu/wl82/tools"

# name -> "url [git clone flags]"
declare -A REPOS=(
    [dinghy]="https://github.com/zvenson/dinghy"
    [felucca]="https://github.com/hugelton/Felucca --recurse-submodules"
    [orbit]="https://github.com/dspaudio/orbit"
    [sloop]="https://github.com/isod89/sloop-fm1"
    [optimist]="https://github.com/w0ts/optimist"
)

die() { echo "mvave-build: $*" >&2; exit 1; }

fetch_one() {   # fetch_one URL DEST SHA256
    local url=$1 dest=$2 sha=$3
    if [ -f "$dest" ] && echo "$sha  $dest" | sha256sum -c - >/dev/null 2>&1; then
        echo "ok      $(basename "$dest") (already here, hash matches)"
        return
    fi
    echo "fetch   $url"
    # no -k: a certificate problem or a geo-block is reported, never bypassed
    curl -fL --retry 3 --connect-timeout 30 -o "$dest.part" "$url" \
        || { rm -f "$dest.part"; die "could not download $url (blocked network? get the file elsewhere and copy it to $VENDOR)"; }
    if ! echo "$sha  $dest.part" | sha256sum -c - >/dev/null 2>&1; then
        rm -f "$dest.part"
        die "$(basename "$dest"): SHA-256 mismatch, file discarded"
    fi
    mv "$dest.part" "$dest"
    echo "ok      $(basename "$dest")"
}

cmd_fetch_vendor() {
    mkdir -p "$VENDOR"
    fetch_one "$TC_URL" "$VENDOR/$TC_FILE" f686586bcfb45e0f0bb27fd2b39c7a7f313cb4f0e88a66a14da621ffa8225958
    fetch_one "$SDK_URL/uboot.boot" "$VENDOR/uboot.boot" 4e3b4c220dc96641cb5a723f41e68ce41d5261ae9434bb33fbd7f2c59976ded4
    fetch_one "$SDK_URL/cfg_tool.bin" "$VENDOR/cfg_tool.bin" 276579954f076886a6a7694f65dc71c034a63a2c204b76749065c0ac7b010d1b
    fetch_one "$SDK_URL/cfg/eq_cfg_hw.bin" "$VENDOR/eq_cfg_hw.bin" 41167491bffed4651750719c973d2758adeb9021a5670d02d6a53c85ed80ea7d
}

cmd_image() {
    "$PODMAN" build --platform linux/amd64 -t "$IMAGE" -f "$ROOT/docker/Containerfile" "$ROOT/docker"
    echo "image $IMAGE built. Keep it local: JieLi's toolchain licence forbids redistribution."
}

cmd_image_base() {
    "$PODMAN" build --platform linux/amd64 --target base -t mvave-fw-base -f "$ROOT/docker/Containerfile" "$ROOT/docker"
}

cmd_clone() {
    mkdir -p "$SRC"
    local names=("$@")
    [ ${#names[@]} -gt 0 ] || names=(dinghy felucca orbit)
    local n spec url flags
    for n in "${names[@]}"; do
        spec=${REPOS[$n]:-} ; [ -n "$spec" ] || die "unknown firmware '$n' (known: ${!REPOS[*]})"
        if [ -d "$SRC/$n/.git" ]; then echo "have    src/$n"; continue; fi
        url=${spec%% *}; flags=""; [ "$spec" = "$url" ] || flags=${spec#* }
        # shellcheck disable=SC2086
        git clone --depth 1 $flags "$url" "$SRC/$n"
    done
}

# run CMD in the container with src/NAME as /work; keep-id so build output belongs to the calling user
in_container() {   # in_container NAME -- CMD...
    local name=$1; shift
    local dir="$SRC/$name"
    [ -d "$dir" ] || die "no src/$name: run ./mvave-build.sh clone $name"
    "$PODMAN" image exists "$IMAGE" || die "no image $IMAGE: run ./mvave-build.sh image"
    local tty=(); [ -t 0 ] && [ -t 1 ] && tty=(-it)
    "$PODMAN" run --rm "${tty[@]}" --platform linux/amd64 --userns=keep-id -e HOME=/tmp \
        -v "$dir:/work:Z" -w /work "$IMAGE" "$@"
}

cmd_build() {
    local name=${1:-}; [ -n "$name" ] || die "usage: build NAME [build.sh args]"; shift
    in_container "$name" sh ./build.sh "$@"
    mkdir -p "$OUT/$name"
    local f found=0
    while IFS= read -r f; do
        cp -f "$f" "$OUT/$name/"; found=1
        echo "package out/$name/$(basename "$f")  sha256 $(sha256sum "$f" | cut -d' ' -f1)"
    done < <(find "$SRC/$name/build" -maxdepth 1 -name '*.fwsc' 2>/dev/null)
    [ "$found" = 1 ] || echo "mvave-build: no .fwsc under src/$name/build (check the build output above)" >&2
}

cmd_run() {
    local name=${1:-}; [ -n "$name" ] || die "usage: run NAME CMD..."; shift
    in_container "$name" "$@"
}

cmd_shell() {
    local name=${1:-dinghy}
    in_container "$name" bash
}

cmd_check() {
    "$PODMAN" image exists "$IMAGE" || die "no image $IMAGE"
    "$PODMAN" run --rm --platform linux/amd64 "$IMAGE" sh -c \
        '/opt/jieli/pi32v2/bin/clang --version | head -1; ls /opt/ac79/cpu/wl82/tools /opt/ac79/cpu/wl82/tools/cfg; python3 -c "import PIL,fontTools;print(\"Pillow\",PIL.__version__)"; gcc --version | head -1'
}

case "${1:-}" in
    fetch-vendor) cmd_fetch_vendor ;;
    image) cmd_image ;;
    image-base) cmd_image_base ;;
    clone) shift; cmd_clone "$@" ;;
    build) shift; cmd_build "$@" ;;
    run) shift; cmd_run "$@" ;;
    shell) shift; cmd_shell "$@" ;;
    check) cmd_check ;;
    *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
