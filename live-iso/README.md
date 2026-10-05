# CentOS Stream 10 RPM-builder Live ISO

This directory builds a **CentOS Stream 10 `MIN-Live` ISO** with the RPM build toolchain used by this repository preinstalled.

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
