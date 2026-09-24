#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/config/versions.env"

WORK_DIR="${WORK_DIR:-$ROOT/.work}"
APP_DIR="$WORK_DIR/cockpit-ups-wol"
OVERLAY_PACKAGES="$ROOT/userpatches/overlay/packages"
VERSION="image-${COCKPIT_UPS_WOL_REF:0:12}"

for cmd in git go npm dpkg-deb; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "missing required build tool: $cmd" >&2
        exit 1
    }
done

mkdir -p "$WORK_DIR" "$OVERLAY_PACKAGES"

if [[ ! -d "$APP_DIR/.git" ]]; then
    git clone --filter=blob:none "$COCKPIT_UPS_WOL_REPO" "$APP_DIR"
fi

git -C "$APP_DIR" fetch --force origin "$COCKPIT_UPS_WOL_REF"
git -C "$APP_DIR" checkout --detach "$COCKPIT_UPS_WOL_REF"
git -C "$APP_DIR" reset --hard "$COCKPIT_UPS_WOL_REF"
git -C "$APP_DIR" clean -ffd

(
    cd "$APP_DIR/cockpit"
    npm ci --ignore-scripts --no-audit --no-fund
    npm run typecheck
    npm run build
)

(
    cd "$APP_DIR"
    VERSION="$VERSION" ./scripts/release/build-bundles.sh
    VERSION="$VERSION" ./scripts/release/build-deb.sh
)

deb="$(find "$APP_DIR/release" -maxdepth 1 -type f -name '*_arm64.deb' -print -quit)"
[[ -n "$deb" && -s "$deb" ]] || {
    echo "ARM64 cockpit-ups-wol Debian package was not produced" >&2
    exit 1
}

install -m 0644 "$deb" "$OVERLAY_PACKAGES/cockpit-ups-wol_arm64.deb"
sha256sum "$OVERLAY_PACKAGES/cockpit-ups-wol_arm64.deb" \
    >"$OVERLAY_PACKAGES/cockpit-ups-wol_arm64.deb.sha256"

echo "staged: $OVERLAY_PACKAGES/cockpit-ups-wol_arm64.deb"
