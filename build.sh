#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$ROOT/config/versions.env"

WORK_DIR="${WORK_DIR:-$ROOT/.work}"
OUT_DIR="${OUT_DIR:-$ROOT/output}"
ARMBIAN_DIR="$WORK_DIR/armbian-build"

for cmd in git sha256sum find cp bash; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "missing required host tool: $cmd" >&2
        exit 1
    }
done

mkdir -p "$WORK_DIR" "$OUT_DIR"

# Build the application package from the pinned source commit first.  This
# deliberately happens outside the target rootfs so Go/npm do not need to be
# installed on the 512 MiB appliance image.
WORK_DIR="$WORK_DIR" bash "$ROOT/scripts/build-cockpit-ups-wol-deb.sh"

if [[ ! -d "$ARMBIAN_DIR/.git" ]]; then
    git clone --filter=blob:none "$ARMBIAN_REPO" "$ARMBIAN_DIR"
fi

git -C "$ARMBIAN_DIR" fetch --force origin "$ARMBIAN_REF"
git -C "$ARMBIAN_DIR" checkout --detach "$ARMBIAN_REF"
git -C "$ARMBIAN_DIR" reset --hard "$ARMBIAN_REF"
git -C "$ARMBIAN_DIR" clean -ffd

rm -rf "$ARMBIAN_DIR/userpatches"
cp -a "$ROOT/userpatches" "$ARMBIAN_DIR/userpatches"

# Armbian's requirements target performs the privileged host preparation.
# The actual image build then runs as the invoking user.
(
    cd "$ARMBIAN_DIR"
    sudo ./compile.sh requirements
    sudo chown -R "$(id -u):$(id -g)" .

    ./compile.sh build \
        BOARD="$ARMBIAN_BOARD" \
        BRANCH="$ARMBIAN_BRANCH" \
        RELEASE="$ARMBIAN_RELEASE" \
        BUILD_MINIMAL=yes \
        BUILD_DESKTOP=no \
        KERNEL_ONLY=no \
        KERNEL_CONFIGURE=no \
        EXPERT=yes \
        COMPRESS_OUTPUTIMAGE=xz \
        SHARE_LOG=no \
        EXTRA_ROOTFS_NAME="cockpit-ups-wol-${IMAGE_REVISION}"
)

image="$(find "$ARMBIAN_DIR/output/images" -maxdepth 1 -type f -name '*.img.xz' -printf '%T@ %p\n' \
    | sort -nr | head -n1 | cut -d' ' -f2-)"
[[ -n "$image" && -s "$image" ]] || {
    echo "Armbian build completed without a compressed .img.xz output" >&2
    exit 1
}

name="milk-v-duo-s-nut-ups_${IMAGE_REVISION}_arm64_${ARMBIAN_RELEASE}_${COCKPIT_UPS_WOL_REF:0:12}.img.xz"
install -m 0644 "$image" "$OUT_DIR/$name"
(
    cd "$OUT_DIR"
    sha256sum "$name" >"$name.sha256"
    cat >BUILD-MANIFEST.txt <<EOF
image=$name
image_revision=$IMAGE_REVISION
armbian_repo=$ARMBIAN_REPO
armbian_ref=$ARMBIAN_REF
armbian_board=$ARMBIAN_BOARD
armbian_branch=$ARMBIAN_BRANCH
armbian_release=$ARMBIAN_RELEASE
cockpit_ups_wol_repo=$COCKPIT_UPS_WOL_REPO
cockpit_ups_wol_ref=$COCKPIT_UPS_WOL_REF
EOF
)

printf '\nBuild complete:\n  %s\n  %s\n' "$OUT_DIR/$name" "$OUT_DIR/$name.sha256"
