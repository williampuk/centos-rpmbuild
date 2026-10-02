#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${WORK_DIR:-${SCRIPT_DIR}/.work}"
OUT_DIR="${OUT_DIR:-${SCRIPT_DIR}/out}"
UPSTREAM_DIR="${WORK_DIR}/kiwi-descriptions"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://gitlab.com/CentOS/AltImages/releng/kiwi-descriptions.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-c10s}"
CONTAINER_IMAGE="${CONTAINER_IMAGE:-quay.io/centos/centos:stream10}"
PROFILE_FILE="${OUT_DIR}/SELECTED_PROFILE.txt"

command -v git >/dev/null
command -v docker >/dev/null
command -v python3 >/dev/null

rm -rf "${WORK_DIR}" "${OUT_DIR}"
mkdir -p "${WORK_DIR}" "${OUT_DIR}"

echo "Cloning ${UPSTREAM_REPO} (${UPSTREAM_BRANCH})..."
git clone --depth 1 --branch "${UPSTREAM_BRANCH}" "${UPSTREAM_REPO}" "${UPSTREAM_DIR}"

git -C "${UPSTREAM_DIR}" rev-parse HEAD > "${OUT_DIR}/UPSTREAM_COMMIT.txt"
python3 "${SCRIPT_DIR}/customize.py" \
  --config "${UPSTREAM_DIR}/config.xml" \
  --packages "${SCRIPT_DIR}/packages.txt" \
  --profile-out "${PROFILE_FILE}"

KIWI_PROFILE="$(tr -d '\r\n' < "${PROFILE_FILE}")"
if [[ -z "${KIWI_PROFILE}" ]]; then
  echo "ERROR: customize.py did not select a KIWI profile" >&2
  exit 1
fi

echo "Building CentOS Stream 10 ${KIWI_PROFILE} ISO with KIWI..."
docker run --rm --privileged \
  -v /dev:/dev \
  -v "${UPSTREAM_DIR}:/kiwi:rw" \
  -v "${OUT_DIR}:/out:rw" \
  -e "KIWI_PROFILE=${KIWI_PROFILE}" \
  "${CONTAINER_IMAGE}" \
  bash -euxo pipefail -c '
    dnf -y install dnf-plugins-core epel-release
    dnf config-manager --set-enabled crb
    dnf -y install kiwi policycoreutils
    kiwi-ng \
      --type=iso \
      --profile="${KIWI_PROFILE}" \
      --color-output \
      system build \
      --description=/kiwi \
      --target-dir=/out
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
