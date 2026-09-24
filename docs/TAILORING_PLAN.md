# Milk-V Duo S UPS appliance image tailoring plan

This document is the implementation roadmap for turning the minimal Milk-V Duo S ARM64 Armbian image into a reliable, low-write, recoverable `cockpit-ups-wol` appliance.

The plan deliberately separates **image-layer policy** from **site-specific UPS configuration**. The image may contain software, safe defaults, diagnostics and recovery infrastructure, but it must not contain site credentials, NAS addresses, Wake-on-LAN targets or an automatically armed shutdown policy.

## Goals

The tailored image should:

- boot reliably on a Milk-V Duo S with 512 MiB RAM;
- run Debian/Armbian ARM64 with systemd;
- provide Cockpit as the management surface;
- include Network UPS Tools and `cockpit-ups-wol`;
- minimize avoidable SD-card writes;
- recover safely from interrupted installation and interrupted boot;
- remain manageable when the UPS or network is unavailable;
- default to a non-destructive state;
- make migration to another ARM64 controller straightforward;
- remain reproducible from pinned source revisions.

## Non-goals

The generic image must not bake in:

- UPS USB serial numbers or a site-specific driver choice;
- NUT usernames or passwords;
- Synology/NAS IP addresses or credentials;
- managed-host IP addresses or MAC addresses;
- Wi-Fi credentials;
- administrator passwords or private SSH keys;
- a static IP address that could conflict on another network;
- an `armed` shutdown/recovery state.

Those values belong to first-boot or later Cockpit configuration and to the transactional configuration managed by `cockpit-ups-wol`.

## Implementation phases

### Phase 0 — reproducible build foundation — DONE

- [x] Pin the Armbian build-framework commit.
- [x] Pin `cockpit-ups-wol` to a specific commit.
- [x] Build the target as `milkv-duos-arm` / ARM64.
- [x] Use Debian 13 Trixie minimal/headless userspace.
- [x] Build the `cockpit-ups-wol` ARM64 Debian package on the build host rather than compiling on the 512 MiB target.
- [x] Produce compressed `.img.xz`, SHA256 checksum and build manifest.
- [x] Provide a GitHub Actions build path.

Acceptance: the same pins must produce an equivalent appliance composition, and every image artifact must state the source revisions used to build it.

### Phase 1 — base appliance composition — IN PROGRESS

- [x] Install `cockpit-ups-wol` and its Debian dependencies.
- [x] Install OpenSSH server and USB diagnostics (`usbutils`).
- [x] Enable Cockpit socket activation.
- [x] Enable SSH access.
- [x] Keep Armbian ZRAM enabled when supplied by the base image.
- [x] Disable system suspend, hibernate and hybrid sleep.
- [x] Bound persistent and runtime journal usage.
- [ ] Set a stable appliance hostname default, e.g. `nut-ups`, while still allowing first-boot override.
- [ ] Set default timezone to `Europe/Sofia` only if the image is intended as a personal deployment image; keep UTC for a generic public appliance build.
- [ ] Verify root filesystem auto-resize on first boot with the pinned Armbian release.
- [ ] Add explicit image version/source metadata visible from Cockpit/CLI.

Acceptance: booting a freshly flashed image must provide Ethernet, SSH, Cockpit and the installed application without automatically configuring or arming a UPS.

### Phase 2 — 512 MiB RAM profile

- [ ] Measure idle RAM after first boot before application setup.
- [ ] Measure RAM with Cockpit idle and during an active Cockpit session.
- [ ] Measure RAM with NUT + `cockpit-ups-wol` running.
- [ ] Define a memory budget for OS, NUT, agent and interactive Cockpit usage.
- [ ] Tune Armbian ZRAM percentage based on measured pressure rather than guesswork.
- [ ] Keep Cockpit socket-activated so it is not permanently resident when unused.
- [ ] Disable or remove unnecessary daemons only after confirming they are not dependencies of Armbian networking, first-boot provisioning or package maintenance.
- [ ] Add an OOM/low-memory diagnostic to the hardware acceptance checklist.

Target: normal UPS monitoring should operate with comfortable free/reclaimable memory; opening Cockpit must not destabilize the safety agent.

### Phase 3 — SD-card endurance and filesystem policy

- [x] Limit journald persistent storage to 64 MiB and runtime storage to 16 MiB.
- [x] Limit journal retention to seven days and enable compression.
- [ ] Confirm no disk-backed swap is created by the final image.
- [ ] Review mount options for safe write reduction (`noatime` or equivalent) without weakening crash consistency.
- [ ] Audit periodic timers for unnecessary write-heavy services.
- [ ] Set sensible log rotation for application-specific logs.
- [ ] Ensure transient runtime files use `/run`/tmpfs where appropriate.
- [ ] Add storage-health and free-space checks to the health report.
- [ ] Document high-endurance/industrial microSD as the recommended medium.

Important: SD-write reduction must not move safety-critical persistent state into volatile storage. Durable outage epochs, shutdown intent, recovery progress and known-good configuration remain persistent.

### Phase 4 — network and remote-management defaults

- [ ] Prefer wired Ethernet for the appliance role.
- [ ] Keep DHCP enabled for first boot.
- [ ] Do not ship a hard-coded static address.
- [ ] Verify mDNS/hostname discovery only if its memory/service cost is acceptable.
- [ ] Keep Cockpit on its standard HTTPS port unless there is a concrete conflict.
- [ ] Keep NUT on its standard port unless configured otherwise.
- [ ] Decide whether Wi-Fi remains available as an optional recovery path or is disabled to reduce attack surface and RAM usage.
- [ ] Disable Bluetooth unless there is a documented project use case.
- [ ] Verify the restricted NUT firewall mode generated by `cockpit-ups-wol` on this board.

Acceptance: first boot must be reachable over Ethernet without prior site configuration, while network exposure remains limited to documented management/NUT services.

### Phase 5 — first-boot appliance experience

- [ ] Add a first-login appliance status banner showing hostname, IP address, Cockpit URL, image version, application version and whether setup is complete.
- [ ] Add a first-boot health check covering RAM, storage, Ethernet, USB host, clock synchronization and required systemd units.
- [ ] Direct the administrator to `sudo cockpit-ups-wol-setup --tui` when configuration is incomplete.
- [ ] Keep `cockpit-ups-wol` in `dry-run` until explicit validation and arming.
- [ ] Never auto-select a UPS when discovery is ambiguous.
- [ ] Make incomplete/interrupted first-boot setup recoverable on the next boot.

Suggested operator flow:

```text
flash image
  -> boot / resize filesystem
  -> DHCP Ethernet
  -> create/login administrator
  -> open Cockpit or SSH
  -> attach UPS USB
  -> run cockpit-ups-wol setup
  -> discover/select UPS
  -> configure managed hosts/Synology
  -> verify shutdown plan
  -> verify Wake-on-LAN
  -> record known-good configuration
  -> remain dry-run
  -> explicitly arm
```

### Phase 6 — hardware watchdog and boot recovery

- [ ] Determine whether the SG2000 watchdog is exposed and reliable with the pinned kernel.
- [ ] If reliable, integrate it through systemd `RuntimeWatchdogSec`/`RebootWatchdogSec` rather than a bespoke watchdog daemon.
- [ ] Test abrupt reset while writing non-critical logs.
- [ ] Test abrupt reset during `cockpit-ups-wol` transactional configuration update.
- [ ] Test abrupt reset during active outage handling.
- [ ] Verify boot reconciliation never treats a reboot as proof that utility power is stable.
- [ ] Verify the controller remains fail-safe when NUT communication is unknown after reboot.

Acceptance: repeated brownouts/reboots must not cause duplicate destructive actions, premature host wake-up, or loss of durable power-state history.

### Phase 7 — backup, restore and migration

- [ ] Add a supported appliance configuration export command.
- [ ] Include project config, host definitions, NUT configuration, policy values and known-good revision metadata.
- [ ] Exclude plaintext secrets by default or encrypt them when explicitly included.
- [ ] Add a restore validation step before replacing live configuration.
- [ ] Make exports architecture-independent so a Duo S configuration can move to a larger ARM64 board.
- [ ] Test migration from Duo S image to a Radxa-class ARM64 host.

Acceptance: migration must be `install image -> import -> validate -> reconnect UPS -> dry-run -> arm`, not manual reconstruction of configuration.

### Phase 8 — security hardening

- [ ] Review SSH defaults and prefer key authentication after administrator enrollment.
- [ ] Do not ship shared credentials or private keys.
- [ ] Confirm Cockpit TLS behavior and document certificate replacement.
- [ ] Verify package provenance and checksum validation for all application artifacts.
- [ ] Keep application and Armbian revisions pinned for release images.
- [ ] Audit listening sockets in the final image.
- [ ] Verify restricted NUT firewall mode on IPv4 and, if enabled, IPv6.
- [ ] Define an update policy that cannot silently replace a known-good image with an unvalidated kernel/application combination.

### Phase 9 — update and rollback model

- [ ] Distinguish OS package updates from application configuration revisions.
- [ ] Preserve a known-good application configuration before every functional change.
- [ ] Decide whether kernel/bootloader upgrades are automatic, manual or release-image-only. For the production UPS controller, manual/release-image-only is preferred until tested.
- [ ] Add image release notes listing base Armbian pin, kernel version and application pin.
- [ ] Add rollback instructions for a failed application update.
- [ ] Define how to recover a failed OS upgrade using a replacement SD card plus configuration export.

### Phase 10 — physical acceptance gate

A release image is not production-ready until tested on the real Milk-V Duo S.

Required tests:

- [ ] cold boot from fully removed power;
- [ ] repeated reboot/brownout cycles;
- [ ] Ethernet DHCP and reconnect after switch/router recovery;
- [ ] USB UPS enumeration after cold boot and reconnect;
- [ ] NUT driver detection and stable monitoring;
- [ ] Cockpit login and configuration under memory pressure;
- [ ] simulated mains outage;
- [ ] managed Linux host shutdown;
- [ ] Synology DSM NUT-secondary shutdown where applicable;
- [ ] controller-last shutdown/FSD behavior;
- [ ] power restoration while battery is below recovery threshold;
- [ ] no Wake-on-LAN until utility stability and charge/runtime gates pass;
- [ ] default 80% charge gate where `battery.charge` is trustworthy;
- [ ] reboot during outage;
- [ ] reboot during partial recovery;
- [ ] USB disconnect/UPS communication loss;
- [ ] SD-card free-space and log-growth check after extended runtime;
- [ ] 24 h, 72 h and multi-day soak test.

## Configuration ownership

The boundary should stay simple:

| Concern | Image repository | `cockpit-ups-wol` |
| --- | --- | --- |
| Bootloader/kernel/DTB | Yes | No |
| Debian/Armbian base | Yes | No |
| RAM/SD-card appliance tuning | Yes | No |
| Cockpit/NUT package presence | Yes | Installer/package definition |
| UPS discovery/policy | No | Yes |
| Synology behavior | No | Yes |
| Host shutdown/WoL policy | No | Yes |
| Durable outage state | No | Yes |
| Site credentials and addresses | No | Yes, configured after boot |
| Image reproducibility | Yes | Release/package reproducibility |

## Definition of done

The Duo S image is considered tailored and production-candidate when:

1. a clean image can be reproduced from pinned revisions;
2. it boots into a reachable but unarmed appliance state;
3. idle and Cockpit-active memory usage are acceptable on 512 MiB;
4. SD-card write behavior is bounded and measured;
5. USB/NUT operation is stable on the real UPS;
6. interrupted boot/configuration/outage tests recover safely;
7. configuration can be exported and restored;
8. Synology and normal managed hosts pass physical outage/recovery acceptance;
9. the release records every difference from the underlying Armbian image in `DEFAULT_IMAGE_DELTA.md`.
