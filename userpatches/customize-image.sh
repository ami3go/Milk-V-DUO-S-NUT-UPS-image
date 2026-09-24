#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE="$1"
LINUXFAMILY="$2"
BOARD="$3"
BUILD_DESKTOP="$4"

[[ "$BOARD" == "milkv-duos-arm" ]] || {
    echo "refusing to customize unexpected board: $BOARD" >&2
    exit 1
}

[[ "$RELEASE" == "trixie" ]] || {
    echo "refusing to customize unexpected release: $RELEASE" >&2
    exit 1
}

export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

pkg=/tmp/overlay/packages/cockpit-ups-wol_arm64.deb
[[ -s "$pkg" ]] || {
    echo "missing staged cockpit-ups-wol ARM64 package: $pkg" >&2
    exit 1
}

# Copy appliance-owned files before enabling services.  The overlay contains
# only generic OS tuning/documentation; UPS-specific configuration is created
# later by cockpit-ups-wol-setup on the real controller.
cp -a /tmp/overlay/rootfs/. /

apt-get update
apt-get install -y --no-install-recommends \
    openssh-server \
    usbutils \
    "$pkg"

# Cockpit is socket activated, so it consumes very little RAM while idle.
# Enabling units in the image creates boot-time symlinks; no daemon is started
# inside the image-build chroot.
systemctl enable cockpit.socket || true
systemctl enable ssh.service || systemctl enable ssh.socket || true

# Armbian normally supplies ZRAM.  If its service is present, ensure it is
# enabled rather than adding disk-backed swap to the SD card.
if systemctl list-unit-files armbian-zram-config.service >/dev/null 2>&1; then
    systemctl enable armbian-zram-config.service || true
fi

# Do not let an SBC UPS controller enter system sleep states.
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target || true

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/overlay/packages/*.deb /tmp/overlay/packages/*.sha256

# Marker used for diagnostics; it is not proof that physical hardware has
# passed acceptance testing.
install -d -m 0755 /etc/cockpit-ups-wol-image
cat >/etc/cockpit-ups-wol-image/build-info <<EOF
board=$BOARD
release=$RELEASE
linuxfamily=$LINUXFAMILY
desktop=$BUILD_DESKTOP
EOF
