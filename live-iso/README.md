# CentOS Stream 10 RPM-builder Live ISO

This directory builds a **CentOS Stream 10 `MIN-Live` ISO** with the RPM build toolchain used by this repository preinstalled.

For a beginner-friendly explanation of the complete build mechanism, architecture, debugging journey, and lessons learned, open [`build-guide.html`](./build-guide.html).

The image uses the CentOS Alternative Images SIG's official KIWI description for the `c10s` branch and builds the documented `MIN-Live` profile.

The upstream KIWI XML is deliberately left untouched. Extra packages are supplied with KIWI's supported `--add-package` command-line option instead. This keeps the build independent of how CentOS organizes or refactors its XML files and components.

## Included packages

The package list lives in `packages.txt`:

- `rpm-build`
- `rpmdevtools`
- `redhat-rpm-config`
- `yum-utils`
- `rpmlint`
- `gcc`
- `make`
- `git`
- `tar`
- `which`
- `xorriso` — burn ISO images to CD/DVD/BD media

The CentOS AltImages recipe includes EPEL repository configuration, which is needed for packages such as `rpmlint`.

## Build locally

Requirements:

- Linux x86_64 host
- Docker
- Git
- enough free disk space for the expanded Live image and ISO

Run:

```bash
bash ./live-iso/build.sh
```

Artifacts are written to:

```text
live-iso/out/
├── *.iso
├── SHA256SUMS
└── UPSTREAM_COMMIT.txt
```

`UPSTREAM_COMMIT.txt` records the exact CentOS KIWI description commit used for the build.

## GitHub Actions

`.github/workflows/build-live-iso.yml` builds the ISO on `ubuntu-24.04` for:

- manual `workflow_dispatch` runs;
- pull requests that modify this directory or the workflow; and
- pushes to `main` affecting the ISO build.

The resulting ISO, checksum, and upstream commit are uploaded as the `centos-stream-10-rpm-builder-live` workflow artifact.

## How the build works

1. Clone the CentOS Alternative Images SIG KIWI descriptions and check out `c10s`.
2. Record the exact upstream commit.
3. Start a privileged CentOS Stream 10 container.
4. Install KIWI and its build dependencies in that container.
5. Read `packages.txt` and turn each line into a KIWI `--add-package=<name>` argument.
6. Build the official `MIN-Live` profile without modifying the upstream XML.
7. Generate `SHA256SUMS` for the resulting ISO.

The key build command is conceptually:

```bash
kiwi-ng \
  --type=iso \
  --profile=MIN-Live \
  system build \
  --description=/kiwi \
  --target-dir=/out \
  --add-package=rpm-build \
  --add-package=rpmdevtools \
  ...
```

This approach uses KIWI's public command-line package override mechanism instead of depending on CentOS's internal XML layout.


## Burn an ISO to DVD

The Live image includes `xorriso`, so after booting it on a machine with a writable optical drive you can burn an existing ISO directly to DVD.

First identify the optical drive:

```bash
lsblk
xorriso -devices
```

On a typical Linux system the drive is `/dev/sr0`.

Then burn the ISO:

```bash
sudo xorriso -as cdrecord \
  -v \
  dev=/dev/sr0 \
  blank=as_needed \
  -eject \
  /path/to/image.iso
```

What the important arguments mean:

- `-as cdrecord`: use xorriso's cdrecord-compatible command syntax.
- `dev=/dev/sr0`: select the optical writer.
- `blank=as_needed`: blank rewritable media when necessary; on blank write-once media no blanking is performed.
- `-v`: show verbose progress.
- `-eject`: eject the disc when writing finishes.

**Check the device name carefully before writing.** `/dev/sr0` is common but is not guaranteed on every machine.

The ISO file itself can live on another USB stick, SSD, local partition, or network-mounted filesystem. Keeping large ISO files outside the Live system's RAM-backed writable overlay is usually preferable.


## Releases

A dedicated workflow at `.github/workflows/release-live-iso.yml` creates GitHub Releases from version tags beginning with `v`.

Examples:

```bash
git tag v0.0.1
git push origin v0.0.1
```

or a prerelease:

```bash
git tag v0.0.1-beta
git push origin v0.0.1-beta
```

The workflow:

1. checks out the exact tagged commit;
2. builds the Live ISO;
3. renames it to include the tag, for example:
   `centos-stream-10-rpm-builder-live-v0.0.1-x86_64.iso`;
4. regenerates `SHA256SUMS`;
5. creates `BUILD_INFO.txt` containing the release tag, repository commit, architecture, and upstream CentOS KIWI commit;
6. creates a GitHub Release with generated release notes;
7. marks tags containing a suffix such as `-beta` or `-rc.1` as prereleases;
8. uploads the ISO, checksum, upstream commit, and build-info file as release assets.

The tag pattern is intentionally broad (`v*`), so values such as `v0.0.1`, `v1.2.3-beta`, and `v2.0.0-rc.1` will all trigger the release workflow.

If a release already exists for the tag and the workflow is rerun, the workflow replaces the assets instead of trying to create a duplicate release.
