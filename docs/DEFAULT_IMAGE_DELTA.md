# Differences from the default Armbian image

This document records intentional changes made by `Milk-V-DUO-S-NUT-UPS-image` compared with the pinned upstream Armbian image configuration used as its base.

It is both operator documentation and a review checklist. Any future appliance-layer change should update this document in the same commit or pull request.

## Upstream baseline

The image currently pins:

- Armbian build repository: `https://github.com/armbian/build.git`
- Armbian revision: `998cebde2dae965f7d0b50cb44a4c20ed951cfb3`
- board: `milkv-duos-arm`
- branch: `edge`
- distribution: Debian 13 Trixie
- architecture: ARM64
- build type: minimal/headless

The application layer pins:

- `cockpit-ups-wol` repository: `https://github.com/ami3go/cockpit-ups-wol.git`
- application revision: `4959372f252001a576f0b3dedfaecc0a3d2a4d75`

The exact pins are authoritative in `config/versions.env`.

## Current implemented differences

### 1. Dedicated UPS appliance application is preinstalled

Default minimal Armbian does not contain the project application.

This image builds and installs the ARM64 `cockpit-ups-wol` Debian package during image creation. The package brings in the project runtime and required dependencies, including Cockpit and Network UPS Tools according to the package definition.

Reason: the target device should boot with the complete software stack already installed rather than compile or download the application on the 512 MiB controller.

Safety effect: software is present, but UPS enrollment and arming are still deferred to the real device after boot.

### 2. OpenSSH server is explicitly installed and enabled

The image installs `openssh-server` and enables the SSH service/socket.

Reason: a headless UPS controller must remain maintainable when Cockpit is unavailable or during initial network/setup work.

Security note: the image does not embed private SSH keys or shared site credentials. Administrator authentication remains a deployment concern.

### 3. USB diagnostic tooling is added

The image installs `usbutils`.

Reason: `lsusb` is valuable during physical UPS acceptance and troubleshooting of USB enumeration, driver selection and reconnect behavior.

### 4. Cockpit is explicitly enabled through socket activation

The image enables `cockpit.socket`.

Reason: Cockpit is the intended management engine, but socket activation avoids keeping the web service permanently resident when it is not being used. This is important on a 512 MiB board.

Behavior: Cockpit is available on demand after boot; opening Cockpit may temporarily increase RAM usage.

### 5. Existing Armbian ZRAM is preserved and enabled when available

The customization script checks for `armbian-zram-config.service` and enables it when present.

Reason: compressed RAM swap is preferable to adding disk-backed swap on a microSD-based appliance and gives the 512 MiB target more tolerance for short-lived Cockpit/package-management memory spikes.

What is intentionally not done yet: this repository does not currently override Armbian's ZRAM percentage or compression settings. Those values should be chosen after measurement on real hardware.

### 6. Suspend and hibernate targets are masked

The image masks:

- `sleep.target`
- `suspend.target`
- `hibernate.target`
- `hybrid-sleep.target`

Reason: a UPS controller must not disappear because of normal operating-system power-management policy. Its availability must be controlled by UPS power state and explicit system shutdown, not idle sleep.

### 7. systemd journal growth is bounded

The image installs `/etc/systemd/journald.conf.d/20-cockpit-ups-wol.conf` with:

- `SystemMaxUse=64M`
- `RuntimeMaxUse=16M`
- `MaxRetentionSec=7day`
- `Compress=yes`
- `RateLimitIntervalSec=30s`
- `RateLimitBurst=1000`

Reason: preserve enough recent history for power-event diagnosis without allowing logs to consume a small SD card indefinitely.

Important limitation: this reduces journal growth but is not yet a complete SD-endurance policy. Application logs, timers and other periodic writers still need measurement and review.

### 8. Image build metadata is added

The image creates `/etc/cockpit-ups-wol-image/build-info` containing build-time board/release/family metadata.

Reason: operators need to identify what appliance image is running when debugging hardware or release-specific problems.

Current limitation: the file records basic image metadata, but future revisions should include the image revision, Armbian commit and `cockpit-ups-wol` commit directly on the target as well.

### 9. Build reproducibility is stricter than a normal ad-hoc Armbian image build

Both Armbian and the application are pinned to exact commits. CI also pins the main Go and Node toolchain versions used to build the application package.

Reason: a safety-related UPS controller should not silently change kernel/application behavior simply because `latest` moved upstream.

### 10. CI produces appliance artifacts and checksums

The repository adds a GitHub Actions workflow that builds the pinned image and publishes:

- compressed `.img.xz` image;
- SHA256 checksum;
- `BUILD-MANIFEST.txt`.

Tagged `image-v*` builds can be published as releases.

Reason: make the image reviewable, reproducible and traceable to source inputs.

## Behavior intentionally left unchanged from Armbian

At the current stage, the following remain under normal Armbian behavior unless inherited indirectly from installed package dependencies:

- first-login/user creation;
- root filesystem resize behavior;
- DHCP/network stack defaults;
- CPU-frequency policy;
- Wi-Fi availability;
- Bluetooth availability;
- locale and timezone;
- package-update policy;
- kernel update policy;
- filesystem/mount options;
- Armbian's default ZRAM sizing and algorithm;
- base firewall policy.

This is deliberate. These items should only be changed after their impact on supportability, RAM, writes and recovery behavior has been tested.

## UPS-specific values deliberately not present in the image

Compared with a fully configured installed controller, the image intentionally contains no:

- selected UPS driver/port;
- UPS serial number;
- NUT authentication credentials;
- managed host/NAS addresses;
- Wake-on-LAN MAC addresses;
- shutdown ordering;
- Synology DSM credentials/configuration;
- static controller IP;
- Wi-Fi credentials;
- private SSH keys;
- `armed` state.

The real controller must acquire these through `cockpit-ups-wol-setup`/Cockpit and the project's transactional configuration path.

## Planned differences not implemented yet

The tailoring roadmap proposes additional changes, but they are **not part of the current image until implemented and marked here**:

- stable appliance hostname/default discovery behavior;
- optional timezone default;
- measured 512 MiB memory profile and ZRAM tuning;
- explicit no-disk-swap verification;
- mount/write-frequency tuning for SD endurance;
- removal/disablement of unnecessary services;
- Wi-Fi/Bluetooth policy;
- first-boot appliance status banner;
- first-boot hardware health report;
- SG2000 hardware watchdog integration if validated;
- supported configuration export/import and cross-board migration;
- stronger SSH/Cockpit hardening defaults;
- controlled OS/kernel update/rollback policy;
- long-duration physical acceptance and soak tests.

See `TAILORING_PLAN.md` for implementation order and acceptance criteria.

## Change-control rule

When the appliance changes a default inherited from Armbian, the same change should document:

1. what changed;
2. the exact configured value or behavior;
3. why the UPS appliance needs it;
4. the RAM/storage/security/reliability impact;
5. how to reverse it;
6. how it was tested on real hardware.

This prevents the image from accumulating undocumented tweaks that later make outage recovery or migration difficult to reason about.
