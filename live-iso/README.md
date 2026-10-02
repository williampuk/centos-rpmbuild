# CentOS Stream 10 RPM-builder Live ISO

This directory builds a **CentOS Stream 10 Live ISO** with the RPM build toolchain used by this repository preinstalled.

The image is based on the CentOS Alternative Images SIG's KIWI description for the `c10s` branch. CentOS's current local-build documentation still points to the read-only Pagure repository; the newer GitLab migration target is not used because its `c10s` content does not currently contain the Live profiles required for this build. The build prefers the text-only `MIN-Live` profile. If the current upstream Stream 10 recipe does not expose `MIN-Live`, it falls back to another supported Live profile (preferring `GNOME-Live`) rather than silently building a non-Live image.

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

`rpmlint` is supplied by EPEL 10. `customize.py` uses the EPEL repository already present in the upstream image description when available, and adds a profile-scoped EPEL 10 repository when needed.

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
├── SELECTED_PROFILE.txt
└── UPSTREAM_COMMIT.txt
```

`UPSTREAM_COMMIT.txt` records the exact CentOS KIWI description commit used for that build. `SELECTED_PROFILE.txt` records the exact upstream Live profile that was built.

## GitHub Actions

`.github/workflows/build-live-iso.yml` builds the ISO on `ubuntu-24.04` for:

- manual `workflow_dispatch` runs;
- pull requests that modify this directory or the workflow; and
- pushes to `main` affecting the ISO build.

The resulting ISO, checksum, selected profile, and upstream commit are uploaded as the `centos-stream-10-rpm-builder-live` workflow artifact.

## How the build works

1. Clone `https://pagure.io/centos-sig-alt-images/kiwi-descriptions.git` at branch `c10s`.
2. Parse the KIWI XML namespace-independently and print all profiles found.
3. Prefer `MIN-Live`; if it is unavailable, select another supported `*-Live` profile.
4. Add the packages from `packages.txt` only to the selected profile.
5. Add a profile-scoped EPEL 10 repository if the upstream recipe does not already have EPEL configured.
6. Run `kiwi-ng --type=iso --profile=<selected-profile> ...` in a privileged `quay.io/centos/centos:stream10` container.
7. Generate `SHA256SUMS` for the resulting ISO.

The upstream recipe is intentionally not vendored here, so each build starts from the current CentOS Stream 10 Alternative Images recipe while recording the exact upstream commit and profile used.
