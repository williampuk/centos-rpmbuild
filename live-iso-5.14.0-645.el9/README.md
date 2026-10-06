# CentOS Stream 9 Live ISO — pinned kernel 5.14.0-645.el9

This directory is a **separate pinned-kernel variant** of the normal `live-iso/` build.

It builds the same CentOS Stream 9 `MIN-Live` RPM-builder environment, but it requires the running kernel family and development files to be exactly:

```text
5.14.0-645.el9.x86_64
```

The normal `live-iso/` directory intentionally follows the current CentOS Stream 9 kernel. This directory exists for hardware/vendor-driver compatibility where the exact kernel version is a hard requirement.

For a Linux-newbie-friendly explanation of the mechanism and the tradeoffs, open [`build-guide.html`](./build-guide.html).

## What is actually pinned?

The kernel pin is **not implemented by pinning a Linux source Git commit**.

A source commit tells us which source code was used, but the Live ISO installs **binary RPM packages**. What matters for the resulting system is which binary kernel RPMs DNF/KIWI selected.

This variant pins the exact CentOS Stream Koji build:

```text
NVR:       kernel-5.14.0-645.el9
Koji ID:   91148
Arch:      x86_64
```

The values are kept in `config.env`.

The pinned RPM family is listed in `kernel-rpms.txt`:

```text
kernel
kernel-core
kernel-modules-core
kernel-modules
kernel-modules-extra
kernel-devel
kernel-headers
```

The build downloads those exact RPMs from the CentOS Stream Koji file store, verifies their RPM metadata, creates a tiny local RPM repository, and gives that repository DNF priority `1`.

The ordinary CentOS Stream 9 repositories remain available for every other package.

## Important distinction: kernel-pinned is not fully frozen

This build guarantees the requested **kernel family**.

It does **not** freeze every package in CentOS Stream 9.

Conceptually:

```text
Pinned:
  kernel* = 5.14.0-645.el9

Still rolling:
  glibc
  bash
  NetworkManager
  curl
  gcc
  ...
```

The CentOS AltImages `c9s` KIWI description also continues to move. The exact recipe commit used for each build is recorded in `UPSTREAM_COMMIT.txt`.

If full historical reproducibility is required later, the next level is to pin:
- the KIWI-description Git commit;
- the Stream 9 repository snapshot/compose;
- EPEL repository state;
- the build-container digest;
- all package versions.

## Why repository priority is needed

Current CentOS Stream 9 repositories contain newer kernels than `5.14.0-645.el9`.

Simply asking for `kernel-devel` would therefore select a newer package.

The build creates:

```text
/pinned-kernel-repo
├── kernel-5.14.0-645.el9.x86_64.rpm
├── kernel-core-5.14.0-645.el9.x86_64.rpm
├── kernel-modules-core-5.14.0-645.el9.x86_64.rpm
├── kernel-modules-5.14.0-645.el9.x86_64.rpm
├── kernel-modules-extra-5.14.0-645.el9.x86_64.rpm
├── kernel-devel-5.14.0-645.el9.x86_64.rpm
├── kernel-headers-5.14.0-645.el9.x86_64.rpm
└── repodata/
```

and passes it to KIWI as an additional RPM-MD repository with priority `1`.

Because it has higher package-manager priority than the normal repositories, package names such as `kernel-core` resolve to the exact pinned RPM rather than a newer Stream package.

## Final verification

The build does not trust package resolution blindly.

KIWI emits a `*.packages` manifest with normalized package metadata:

```text
name|epoch|version|release|arch|disturl|license
```

After the image is built, `build.sh` checks that every package listed in `kernel-rpms.txt` is exactly:

```text
version = 5.14.0
release = 645.el9
arch    = x86_64
```

It also requires **exactly one** `kernel-core` entry, preventing a newer second runtime kernel from silently entering the image.

A successful build produces `KERNEL_PIN_VERIFIED.txt`.

`KOJI_BUILD_INFO.txt` records the result of querying CentOS Stream Koji at build time. The build aborts unless Koji build ID `91148` resolves to NVR `kernel-5.14.0-645.el9` and contains every required x86_64 RPM.

## Included non-kernel tools

The rest of the package set mirrors `live-iso/`:

- RPM development: `rpm-build`, `rpmdevtools`, `redhat-rpm-config`, `rpmlint`, GCC, make, Git
- legacy vendor-installer compatibility: `chkconfig`
- optical media: `xorriso`
- network management: NetworkManager, `nmcli`, `nmtui`, Wi-Fi support
- diagnostics: `ip`, `ss`, `ping`, `tracepath`, `dig`, `ethtool`, `tcpdump`, `traceroute`
- transfers/access: `curl`, `wget`, `ssh`, `scp`, `nc`

## Build locally

Requirements:

- Linux x86_64 host
- Docker
- Git
- Internet access to CentOS Stream repositories, EPEL, Pagure, and CentOS Stream Koji
- enough free disk space for the expanded Live filesystem and ISO

Run from the repository root:

```bash
bash ./live-iso-5.14.0-645.el9/build.sh
```

Outputs are written to:

```text
live-iso-5.14.0-645.el9/out/
├── *.iso
├── *.packages
├── SHA256SUMS
├── KERNEL_RPM_SHA256SUMS
├── PINNED_KERNEL_RPMS.txt
├── KOJI_BUILD_INFO.txt
├── KERNEL_PIN_VERIFIED.txt
├── UPSTREAM_COMMIT.txt
└── BUILD_INFO.txt
```

## Why both KERNEL_RPM_SHA256SUMS and SHA256SUMS?

`KERNEL_RPM_SHA256SUMS` records the bytes of the historical kernel RPM inputs downloaded from Koji.

`SHA256SUMS` records the final generated ISO.

That gives two useful integrity checkpoints:

```text
exact kernel RPM inputs
        │
        ▼
KERNEL_RPM_SHA256SUMS
        │
        ▼
      KIWI
        │
        ▼
final ISO
        │
        ▼
SHA256SUMS
```

## CI workflow

The dedicated workflow is:

```text
.github/workflows/build-live-iso-kernel-5.14.0-645-el9.yml
```

It runs when this directory or its workflow changes and uploads the complete build evidence.

It is separate from the ordinary Stream 9 `live-iso/` workflow.

## Releases

The pinned variant uses a version-first tag ending in `-kernel-5.14.0-645.el9`. The normal release workflow explicitly excludes `v*-kernel-*`, so exactly one release workflow handles each tag.

Use:

```bash
git tag v0.0.1-kernel-5.14.0-645.el9
git push origin v0.0.1-kernel-5.14.0-645.el9
```

Prerelease example:

```bash
git tag v0.0.1-beta-kernel-5.14.0-645.el9
git push origin v0.0.1-beta-kernel-5.14.0-645.el9
```

The corresponding workflow is:

```text
.github/workflows/release-live-iso-kernel-5.14.0-645-el9.yml
```

Release assets include the ISO, package manifest, kernel-verification evidence, kernel-RPM checksums, upstream recipe commit, and build information.

### Tag routing summary

| Tag | Workflow |
| --- | --- |
| `v0.0.1` | normal rolling Stream 9 Live ISO |
| `v0.0.1-beta` | normal rolling prerelease |
| `v0.0.1-kernel-5.14.0-645.el9` | pinned-kernel Live ISO |
| `v0.0.1-beta-kernel-5.14.0-645.el9` | pinned-kernel prerelease |

## Security consequence of pinning

The pin exists for compatibility, but it deliberately prevents the kernel from following later Stream 9 security/bug-fix updates.

Treat this as a conscious compatibility/security tradeoff.

If the driver/hardware constraint goes away, prefer the ordinary rolling `live-iso/` build.
