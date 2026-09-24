# Building the Milk-V Duo S NUT UPS image

This document describes how to prepare a build host, install all required dependencies, build the tailored Milk-V Duo S ARM64 image, verify the result, and use the GitHub Actions build path.

The authoritative build configuration is `config/versions.env`. The image build is intentionally reproducible: it pins the Armbian build framework and the `cockpit-ups-wol` application source used to assemble the appliance.

## 1. What the build produces

The build creates a compressed ARM64 SD-card image for the Milk-V Duo S together with a SHA256 checksum and a manifest describing the exact source revisions used.

Expected files under `output/`:

```text
milk-v-duo-s-nut-ups_<image-revision>_arm64_trixie_<app-commit>.img.xz
milk-v-duo-s-nut-ups_<image-revision>_arm64_trixie_<app-commit>.img.xz.sha256
BUILD-MANIFEST.txt
```

The image contains the Debian/Armbian base, Milk-V Duo S kernel/boot support, Cockpit, NUT, SSH, USB diagnostics and the pinned ARM64 `cockpit-ups-wol` package. Site-specific UPS/NAS credentials and an armed policy are deliberately not baked into the image.

## 2. Recommended build host

For a native local build, use a dedicated Linux machine or VM. The pinned Armbian build framework documents the following native build-host baseline:

- Armbian or Debian 13 (Trixie) for native builds;
- at least 8 GiB RAM;
- about 50 GiB free disk space;
- `x86_64`, `aarch64` or `riscv64` host architecture;
- `sudo` or root privileges.

For this repository, **Debian 13 x86_64 is the recommended local build host** because it matches Armbian's documented native host and has the simplest Go/Node toolchain setup.

The GitHub Actions workflow currently uses Ubuntu 24.04 as its hosted CI environment. CI is useful for validation and artifact generation, while Debian 13 remains the preferred local/native development host.

Do not build the image on the Milk-V Duo S itself. The build process is intentionally performed on a larger machine and cross-builds the ARM64 appliance package/image.

## 3. Clone the repository

```bash
git clone https://github.com/ami3go/Milk-V-DUO-S-NUT-UPS-image.git
cd Milk-V-DUO-S-NUT-UPS-image
```

Inspect the pinned versions before building:

```bash
cat config/versions.env
```

At minimum, check:

```text
ARMBIAN_REF
ARMBIAN_BOARD
ARMBIAN_BRANCH
ARMBIAN_RELEASE
COCKPIT_UPS_WOL_REF
GO_VERSION
NODE_VERSION
IMAGE_REVISION
```

Do not casually replace the pinned commits with `main` or `latest` when preparing a release image.

## 4. Install base host dependencies

The commands below target Debian 13. Run them as a normal user with `sudo` access.

```bash
sudo apt update
sudo apt install -y \
    ca-certificates \
    curl \
    git \
    sudo \
    xz-utils \
    coreutils \
    findutils \
    dpkg-dev \
    build-essential \
    jq \
    rsync \
    unzip \
    zip \
    wget \
    gnupg
```

These packages provide the tools required by this repository before Armbian's own dependency installer runs.

The image build later executes:

```bash
sudo ./compile.sh requirements
```

inside the pinned Armbian build tree. That Armbian target installs the framework-specific host dependencies required to build the bootloader, kernel, root filesystem and final image. Do not maintain a second copied list of all Armbian packages in this repository; use the pinned framework's dependency resolver.

## 5. Install Go

The application-package builder requires the Go major/minor series specified by `GO_VERSION` in `config/versions.env`.

At the time this guide was written the repository selects:

```text
GO_VERSION=1.26.x
```

A current matching release is Go 1.26.7. On a Debian 13 x86_64 build host, it can be installed from the official Go archive as follows:

```bash
cd /tmp
curl -fLO https://go.dev/dl/go1.26.7.linux-amd64.tar.gz
echo 'ffb5f8de10c62550dfddab66b36b57030721e0a44a3218e9e1181d7b59f121ca  go1.26.7.linux-amd64.tar.gz' | sha256sum -c -
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.26.7.linux-amd64.tar.gz
```

Add Go to the current shell and your login environment:

```bash
export PATH=/usr/local/go/bin:$PATH
printf '\nexport PATH=/usr/local/go/bin:$PATH\n' >> "$HOME/.profile"
```

Verify:

```bash
go version
```

Expected major/minor version:

```text
go version go1.26.x linux/amd64
```

If `config/versions.env` changes to another Go series, install a matching version instead. For an ARM64 build host, use the corresponding official `linux-arm64` archive and checksum.

## 6. Install Node.js and npm

The Cockpit frontend build requires the Node major series specified by `NODE_VERSION` in `config/versions.env`.

The repository currently selects:

```text
NODE_VERSION=24.x
```

Using `nvm` is convenient because it keeps the build-host Node version separate from the operating system packages.

Install nvm:

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.7/install.sh | bash
```

Load it into the current shell:

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
```

Install and select Node 24:

```bash
nvm install 24
nvm use 24
nvm alias default 24
```

Verify:

```bash
node --version
npm --version
```

The Node major version must be `v24`. The exact patch can advance within the selected `24.x` series unless/until the repository changes to an exact patch pin.

## 7. Preflight the build host

Run the following from the image repository:

```bash
for cmd in git go node npm dpkg-deb sha256sum find cp bash sudo; do
    command -v "$cmd" || { echo "MISSING: $cmd"; exit 1; }
done

go version
node --version
npm --version
dpkg-deb --version | head -n1
df -h .
free -h
```

Recommended preflight conditions:

- at least 8 GiB RAM available to the build VM/host;
- about 50 GiB or more free disk space;
- working Internet access to GitHub, Debian mirrors, Go/npm module registries and Armbian source mirrors;
- working `sudo` access;
- system clock reasonably correct, so TLS/package verification works.

Validate the repository shell scripts before starting the expensive build:

```bash
bash -n build.sh
bash -n scripts/build-cockpit-ups-wol-deb.sh
bash -n userpatches/customize-image.sh
```

## 8. Build the image

From the repository root:

```bash
bash ./build.sh
```

The script performs the following steps automatically:

1. reads all source/toolchain selectors from `config/versions.env`;
2. clones or updates the pinned `cockpit-ups-wol` source;
3. builds and type-checks the Cockpit frontend with npm;
4. cross-builds the project binaries and Debian packages;
5. stages the ARM64 `.deb` into the Armbian image overlay;
6. clones or updates the pinned Armbian build framework;
7. copies this repository's `userpatches` into the Armbian tree;
8. runs `sudo ./compile.sh requirements` to install Armbian build-host dependencies;
9. builds `milkv-duos-arm`, `edge`, Debian Trixie, minimal/headless;
10. compresses the resulting image with xz;
11. copies the final image into `output/`;
12. writes the image SHA256 checksum and `BUILD-MANIFEST.txt`.

The Armbian build itself runs with these important parameters:

```text
BOARD=milkv-duos-arm
BRANCH=edge
RELEASE=trixie
BUILD_MINIMAL=yes
BUILD_DESKTOP=no
KERNEL_ONLY=no
KERNEL_CONFIGURE=no
EXPERT=yes
COMPRESS_OUTPUTIMAGE=xz
```

The first build downloads toolchains, sources and rootfs packages, so it is much heavier than subsequent cached builds.

## 9. Build directories

By default:

```text
.work/                         temporary/cached build workspace
.work/cockpit-ups-wol/         pinned application checkout
.work/armbian-build/           pinned Armbian checkout and build cache
userpatches/overlay/packages/  generated ARM64 application package staged for image build
output/                        final image, checksum and manifest
```

You may override the workspace and output locations:

```bash
WORK_DIR=/fast-disk/duo-build \
OUT_DIR=/fast-disk/duo-output \
bash ./build.sh
```

This is useful when the repository itself is on a small filesystem.

## 10. Verify the result

After a successful build:

```bash
cd output
ls -lh
```

Verify the checksum:

```bash
sha256sum -c *.img.xz.sha256
```

Inspect the manifest:

```bash
cat BUILD-MANIFEST.txt
```

The manifest should record at least:

- image filename and image revision;
- Armbian repository and exact commit;
- Armbian board, branch and release;
- `cockpit-ups-wol` repository and exact commit.

Keep the image, checksum and manifest together. The image should not be considered traceable/reproducible if the manifest is missing.

## 11. Clean build

For a completely fresh local rebuild, remove generated work and output data:

```bash
rm -rf .work output userpatches/overlay/packages
```

Then rebuild:

```bash
bash ./build.sh
```

Use a clean build when validating a release or when diagnosing suspected stale Armbian/npm/Go build-cache behavior.

For normal development, keeping `.work/` dramatically reduces download/build time.

## 12. GitHub Actions build

The repository includes:

```text
.github/workflows/build-image.yml
```

The workflow:

- validates the shell scripts;
- installs the configured Go and Node major versions using GitHub Actions setup actions;
- prepares the runner;
- runs `bash ./build.sh`;
- verifies the produced image checksum;
- uploads the image, checksum and build manifest as a workflow artifact.

To build manually in GitHub:

1. open the repository on GitHub;
2. open **Actions**;
3. select **Build Milk-V Duo S image**;
4. choose **Run workflow** on `main`;
5. after completion, download the `milk-v-duo-s-nut-ups-image` artifact.

The workflow also runs when relevant build files change on `main`.

## 13. Create a release image

Tags matching `image-v*` cause the workflow to publish the generated image files as a GitHub release.

Example:

```bash
git switch main
git pull --ff-only
git tag image-v0.1.0
git push origin image-v0.1.0
```

Before creating a release tag:

1. confirm `config/versions.env` contains the intended pins;
2. confirm CI passes on the same commit;
3. review `docs/DEFAULT_IMAGE_DELTA.md`;
4. update `docs/TAILORING_PLAN.md` if implementation status changed;
5. do not call the image production-ready until the corresponding physical Duo S/UPS acceptance tests pass.

## 14. Flash the image

Decompressing is optional if your imaging tool accepts `.img.xz` directly.

On Linux, an example manual flow is:

```bash
xz -dk output/milk-v-duo-s-nut-ups_*.img.xz
lsblk
```

Identify the SD-card block device carefully. Then write the image, replacing `/dev/sdX` with the **whole SD card**, not a partition:

```bash
sudo dd if=output/milk-v-duo-s-nut-ups_*.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

`dd` will destroy the contents of the selected target device. Verify the device name with `lsblk` before running it.

Graphical tools such as Raspberry Pi Imager, Balena Etcher or Armbian Imager can also write compressed images where supported.

## 15. First boot after flashing

The generic image intentionally does not contain site-specific UPS configuration.

After boot:

1. complete normal Armbian first-login/user provisioning;
2. connect wired Ethernet;
3. connect the UPS USB cable;
4. verify the system is reachable over SSH or Cockpit;
5. run:

```bash
sudo cockpit-ups-wol-setup --tui
```

The application remains in its safe non-destructive setup/dry-run flow until the real topology has been validated and explicitly armed.

Useful checks:

```bash
lsusb
systemctl status cockpit.socket
systemctl status cockpit-ups-wol-agent.service
systemctl status cockpit-ups-wol-health.timer
upsc ups@localhost
cockpit-ups-wolctl health
```

## 16. Common build failures

### `missing required build tool: go` or `npm`

The local application package is built before the Armbian framework dependency stage. Install the Go and Node versions described above and verify they are in `PATH`.

### `sudo: command not found` or no sudo permission

Install/configure `sudo`, or use a build account with the required administrative rights. Armbian's dependency/bootstrap stage requires privileged package installation.

### Not enough disk space

Check:

```bash
df -h .
du -sh .work/* 2>/dev/null || true
```

Move `WORK_DIR` to a larger disk or remove `.work/` and retry. Plan for at least about 50 GiB free for the Armbian build.

### npm dependency or frontend build failure

First verify the selected Node major version:

```bash
node --version
npm --version
```

Then do a clean application checkout/build cache reset:

```bash
rm -rf .work/cockpit-ups-wol
bash ./build.sh
```

### Armbian source/toolchain failure

Clean only the Armbian workspace and retry:

```bash
rm -rf .work/armbian-build
bash ./build.sh
```

Do not work around a failed pinned source by silently changing `ARMBIAN_REF`; investigate and document any required pin update.

### Build succeeds but no `.img.xz` appears

Inspect the Armbian output and logs under:

```text
.work/armbian-build/output/
```

The wrapper intentionally fails if the Armbian build does not produce a compressed image.

## 17. Dependency ownership

There are three dependency layers:

| Layer | Installed/managed by |
| --- | --- |
| Basic host tools (`git`, `curl`, `dpkg-deb`, etc.) | build-host administrator |
| Go and Node/npm used to build `cockpit-ups-wol` | build-host administrator / GitHub Actions |
| Kernel/rootfs/bootloader build dependencies | pinned Armbian `compile.sh requirements` |
| Packages inside the final appliance (`cockpit`, NUT, SSH, etc.) | image customization and `cockpit-ups-wol` Debian package dependencies |

This separation is intentional. The Milk-V Duo S itself does not need Go, Node, compilers or the Armbian build framework installed.

## 18. Build checklist

Before accepting an image artifact:

- [ ] correct `config/versions.env` reviewed;
- [ ] build scripts pass `bash -n`;
- [ ] sufficient RAM and free disk space;
- [ ] Go matches configured major/minor series;
- [ ] Node matches configured major series;
- [ ] `bash ./build.sh` completes successfully;
- [ ] `sha256sum -c` passes;
- [ ] build manifest records the expected commits;
- [ ] image delta documentation is current;
- [ ] CI passes for release commit;
- [ ] physical Milk-V Duo S acceptance remains a separate required gate before production use.
