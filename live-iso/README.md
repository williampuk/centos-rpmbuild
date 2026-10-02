# CentOS Stream 10 RPM-builder Live ISO

This directory builds a small **CentOS Stream 10 `MIN-Live` ISO** with the RPM build toolchain used by this repository preinstalled.

The image is based on the CentOS Alternative Images SIG's official KIWI description for the `c10s` branch. The build clones that upstream description, adds the packages in `packages.txt` to the `MIN-Live` profile, and runs KIWI inside a privileged CentOS Stream 10 container.

## Included packages

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

`rpmlint` is supplied by EPEL 10. `customize.py` uses the EPEL repository already present in the upstream image description when available, and adds a build-only EPEL 10 repository when needed.

## Build locally

Requirements:

- Linux x86_64 host
- Docker
- Git
- Python 3
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

`UPSTREAM_COMMIT.txt` records the exact CentOS KIWI description commit used for that build.

## GitHub Actions

`.github/workflows/build-live-iso.yml` builds the ISO on `ubuntu-24.04` for:

- manual `workflow_dispatch` runs;
- pull requests that modify this directory or the workflow; and
- pushes to `main` affecting the ISO build.

The resulting ISO, checksum, and upstream commit are uploaded as the `centos-stream-10-rpm-builder-live` workflow artifact.

## How the build works

1. Clone `https://gitlab.com/CentOS/AltImages/releng/kiwi-descriptions.git` at branch `c10s`.
2. Validate that the upstream recipe still contains the `MIN-Live` profile.
3. Add the packages from `packages.txt` only to that profile.
4. Add a build-only EPEL 10 repository if the upstream recipe does not already have EPEL configured.
5. Run `kiwi-ng --type=iso --profile=MIN-Live ...` in a privileged `quay.io/centos/centos:stream10` container.
6. Generate `SHA256SUMS` for the resulting ISO.

The upstream recipe is intentionally not vendored here, so each build starts from the current CentOS Stream 10 Alternative Images recipe while recording the exact upstream commit used.
