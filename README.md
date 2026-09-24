# Milk-V Duo S NUT UPS appliance image

Reproducible ARM64 SD-card image for the **Milk-V Duo S (SG2000, 512 MiB)**, tailored for the [`cockpit-ups-wol`](https://github.com/ami3go/cockpit-ups-wol) UPS controller.

## Design

This repository builds the operating-system/appliance layer. The UPS orchestration application remains in `ami3go/cockpit-ups-wol` and is consumed at a pinned commit.

The image is based on a pinned Armbian build revision using:

- board: `milkv-duos-arm`
- architecture: ARM64 / Cortex-A53
- Debian userspace
- headless/minimal image
- systemd
- wired Ethernet preferred
- Cockpit
- Network UPS Tools (NUT)
- `cockpit-ups-wol` ARM64 Debian package
- conservative settings for a 512 MiB, SD-card-based appliance

The Armbian board definition identifies the target as the Milk-V Duo S ARM variant with an SG2000 Cortex-A53, 512 MiB RAM, 100 Mbit Ethernet, SD/eMMC, Wi-Fi/Bluetooth and USB 2.0.

## Safety model

The image **never arms automatic shutdown/recovery during image creation or first boot**.

After flashing and booting:

1. connect the controller to a battery-backed UPS output;
2. connect Ethernet and the UPS USB interface;
3. log in over SSH or local serial console;
4. run:

```bash
sudo cockpit-ups-wol-setup --tui
```

The project installer performs UPS discovery, NUT configuration, transactional installation, health probation and known-good configuration creation. New installations remain in safe `dry-run` mode until explicitly validated and armed.

## Reproducibility

`config/versions.env` pins both:

- the Armbian build-framework commit;
- the `cockpit-ups-wol` application commit.

Changing either pin is an explicit image update.

## Local build

A Linux build host is required. Armbian recommends a machine with substantial free disk space; building inside a VM or dedicated build container is preferable to building directly on the Duo S.

Required host tools include Git, Go, Node.js/npm, `dpkg-deb`, and the packages required by the Armbian build framework.

```bash
sudo ./build.sh
```

The resulting compressed SD-card image and checksum are copied to `output/`.

## First boot

Armbian performs its normal first-login/user provisioning. The appliance packages are already present, but `cockpit-ups-wol` is deliberately not configured until the administrator runs its setup wizard with the real UPS attached.

Useful commands after setup:

```bash
systemctl status cockpit.socket
systemctl status cockpit-ups-wol-agent.service
systemctl status cockpit-ups-wol-health.timer
upsc ups@localhost
cockpit-ups-wolctl health
```

Cockpit is then available on the controller's HTTPS port 9090.

## Image policy

The image intentionally avoids board-specific logic in the safety agent. Milk-V-specific boot/kernel support belongs here; NUT shutdown/recovery policy belongs in `cockpit-ups-wol`. This keeps migration to a larger ARM64 board such as a Radxa ROCK 3C straightforward if the 512 MiB target proves too constrained.

## Status

Initial image-build scaffolding. A successful CI build does **not** replace physical acceptance testing with a real Duo S, real UPS, power interruption/recovery, and Synology DSM where applicable.
