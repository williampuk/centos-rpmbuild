#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${WORK_DIR:-${SCRIPT_DIR}/.work}"
OUT_DIR="${OUT_DIR:-${SCRIPT_DIR}/out}"
UPSTREAM_DIR="${WORK_DIR}/kiwi-descriptions"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://pagure.io/centos-sig-alt-images/kiwi-descriptions.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-c9s}"
CONTAINER_IMAGE="${CONTAINER_IMAGE:-quay.io/centos/centos:stream9}"
KIWI_PROFILE="${KIWI_PROFILE:-MIN-Live}"

command -v git >/dev/null
command -v docker >/dev/null

rm -rf "${WORK_DIR}" "${OUT_DIR}"
mkdir -p "${WORK_DIR}" "${OUT_DIR}"

echo "Cloning CentOS AltImages KIWI descriptions from:"
echo "  ${UPSTREAM_REPO}"
echo "Branch: ${UPSTREAM_BRANCH}"

if ! git clone --branch "${UPSTREAM_BRANCH}" "${UPSTREAM_REPO}" "${UPSTREAM_DIR}"; then
  cat >&2 <<EOF
ERROR: Unable to clone the CentOS AltImages KIWI descriptions.

Note: Pagure serves this repository using Git's dumb HTTP transport, so this
build intentionally performs a normal clone rather than a shallow (--depth)
clone.

Repository:
  https://pagure.io/centos-sig-alt-images/kiwi-descriptions.git
EOF
  exit 1
fi

git -C "${UPSTREAM_DIR}" rev-parse HEAD > "${OUT_DIR}/UPSTREAM_COMMIT.txt"

echo "Requested additional packages:"
grep -Ev '^[[:space:]]*(#|$)' "${SCRIPT_DIR}/packages.txt" | sed 's/^/  - /'

echo "Building CentOS Stream 9 ${KIWI_PROFILE} ISO with KIWI..."
docker run --rm --privileged \
  -v /dev:/dev \
  -v "${UPSTREAM_DIR}:/kiwi:rw" \
  -v "${OUT_DIR}:/out:rw" \
  -v "${SCRIPT_DIR}/packages.txt:/packages.txt:ro" \
  -e "KIWI_PROFILE=${KIWI_PROFILE}" \
  "${CONTAINER_IMAGE}" \
  bash -euxo pipefail -c '
    dnf -y install dnf-plugins-core epel-release
    dnf config-manager --set-enabled crb
    dnf -y install kiwi policycoreutils

    echo "Available KIWI profiles:"
    kiwi-ng image info --description=/kiwi --list-profiles || true

    mapfile -t packages < <(grep -Ev "^[[:space:]]*(#|$)" /packages.txt)
    package_args=()
    for package in "${packages[@]}"; do
      package_args+=(--add-package="${package}")
    done

    echo "Adding packages through KIWI command-line overrides:"
    printf "  %s\n" "${packages[@]}"

    kiwi-ng \
      --type=iso \
      --profile="${KIWI_PROFILE}" \
      --color-output \
      system build \
      --description=/kiwi \
      --target-dir=/out \
      "${package_args[@]}"
  '

mapfile -t isos < <(find "${OUT_DIR}" -maxdepth 1 -type f -name '*.iso' -print | sort)
if (( ${#isos[@]} == 0 )); then
  echo "ERROR: KIWI completed without producing an ISO in ${OUT_DIR}" >&2
  exit 1
fi

(
  cd "${OUT_DIR}"
  sha256sum -- *.iso > SHA256SUMS
)

echo "Build output:"
ls -lh "${OUT_DIR}"
cat "${OUT_DIR}/SHA256SUMS"
