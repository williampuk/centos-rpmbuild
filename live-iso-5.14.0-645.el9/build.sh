#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/config.env"

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

echo "Pinned kernel target:"
echo "  NVR:       ${KERNEL_NVR}"
echo "  Koji ID:   ${KERNEL_BUILD_ID}"
echo "  Arch:      ${TARGET_ARCH}"
echo

echo "Cloning CentOS AltImages KIWI descriptions:"
echo "  repo:   ${UPSTREAM_REPO}"
echo "  branch: ${UPSTREAM_BRANCH}"

if ! git clone --branch "${UPSTREAM_BRANCH}" "${UPSTREAM_REPO}" "${UPSTREAM_DIR}"; then
  cat >&2 <<EOF
ERROR: Unable to clone the CentOS AltImages KIWI descriptions.

Pagure serves this repository using Git's dumb HTTP transport, so this
build intentionally performs a normal clone rather than a shallow clone.

Repository:
  ${UPSTREAM_REPO}
EOF
  exit 1
fi

# This variant pins the binary kernel build, not the whole CentOS image recipe.
# We still record the exact c9s recipe commit used so every build remains traceable.
git -C "${UPSTREAM_DIR}" rev-parse HEAD > "${OUT_DIR}/UPSTREAM_COMMIT.txt"

echo "Requested additional non-kernel packages:"
grep -Ev '^[[:space:]]*(#|$)' "${SCRIPT_DIR}/packages.txt" | sed 's/^/  - /'

echo "Pinned kernel RPM names:"
grep -Ev '^[[:space:]]*(#|$)' "${SCRIPT_DIR}/kernel-rpms.txt" | sed 's/^/  - /'

echo "Building CentOS Stream 9 ${KIWI_PROFILE} ISO with pinned kernel ${KERNEL_VERSION}-${KERNEL_RELEASE}..."

docker run --rm --privileged \
  -v /dev:/dev \
  -v "${UPSTREAM_DIR}:/kiwi:rw" \
  -v "${OUT_DIR}:/out:rw" \
  -v "${SCRIPT_DIR}/packages.txt:/packages.txt:ro" \
  -v "${SCRIPT_DIR}/kernel-rpms.txt:/kernel-rpms.txt:ro" \
  -e "KIWI_PROFILE=${KIWI_PROFILE}" \
  -e "KERNEL_BUILD_ID=${KERNEL_BUILD_ID}" \
  -e "KERNEL_VERSION=${KERNEL_VERSION}" \
  -e "KERNEL_RELEASE=${KERNEL_RELEASE}" \
  -e "TARGET_ARCH=${TARGET_ARCH}" \
  -e "KOJI_HUB=${KOJI_HUB}" \
  -e "KOJI_TOPURL=${KOJI_TOPURL}" \
  "${CONTAINER_IMAGE}" \
  bash -euxo pipefail -c '
    dnf -y install dnf-plugins-core epel-release
    dnf config-manager --set-enabled crb
    dnf -y install kiwi policycoreutils curl-minimal createrepo_c rpm python3

    command -v curl >/dev/null

    pinned_repo=/pinned-kernel-repo
    mkdir -p "${pinned_repo}"

    mapfile -t kernel_packages < <(
      grep -Ev "^[[:space:]]*(#|$)" /kernel-rpms.txt
    )

    echo "Verifying CentOS Stream Koji build identity and RPM list..."
    python3 - <<'PY' | tee /out/KOJI_BUILD_INFO.txt
import os
import sys
import xmlrpc.client

hub = os.environ["KOJI_HUB"]
build_id = int(os.environ["KERNEL_BUILD_ID"])
expected_nvr = "kernel-" + os.environ["KERNEL_VERSION"] + "-" + os.environ["KERNEL_RELEASE"]
arch = os.environ["TARGET_ARCH"]

with open("/kernel-rpms.txt", encoding="utf-8") as f:
    required = [
        line.strip()
        for line in f
        if line.strip() and not line.lstrip().startswith("#")
    ]

session = xmlrpc.client.ServerProxy(hub, allow_none=True)
build = session.getBuild(build_id)
if not build:
    raise SystemExit(f"Koji build ID {build_id} does not exist")

actual_nvr = build.get("nvr")
if actual_nvr != expected_nvr:
    raise SystemExit(
        f"Koji build ID {build_id} is {actual_nvr!r}, expected {expected_nvr!r}"
    )

rpms = session.listRPMs(buildID=build_id)
selected = {}
for rpm in rpms:
    if rpm.get("name") in required and rpm.get("arch") == arch:
        selected[rpm["name"]] = rpm

missing = [name for name in required if name not in selected]
if missing:
    raise SystemExit(
        "Required RPMs missing from Koji build "
        + str(build_id)
        + ": "
        + ", ".join(missing)
    )

print(f"Koji hub: {hub}")
print(f"Build ID: {build_id}")
print(f"NVR: {actual_nvr}")
print(f"Task ID: {build.get('task_id')}")
print(f"State: {build.get('state')}")
print("Selected RPMs:")
for name in required:
    rpm = selected[name]
    print(
        f"  {rpm['name']}-{rpm['version']}-{rpm['release']}."
        f"{rpm['arch']}.rpm"
    )
PY

    echo "Downloading exact kernel RPM family from verified Koji build ${KERNEL_BUILD_ID}..."
    for package in "${kernel_packages[@]}"; do
      rpm_name="${package}-${KERNEL_VERSION}-${KERNEL_RELEASE}.${TARGET_ARCH}.rpm"
      rpm_url="${KOJI_TOPURL}/packages/kernel/${KERNEL_VERSION}/${KERNEL_RELEASE}/${TARGET_ARCH}/${rpm_name}"

      echo "  ${rpm_url}"
      curl --fail --location --retry 4 --retry-all-errors \
        --output "${pinned_repo}/${rpm_name}" \
        "${rpm_url}"
    done

    echo "Verifying downloaded RPM metadata..."
    for rpm_file in "${pinned_repo}"/*.rpm; do
      rpm -qp --queryformat "%{NAME}|%{VERSION}|%{RELEASE}|%{ARCH}\n" "${rpm_file}"
    done | tee /out/PINNED_KERNEL_RPMS.txt

    while IFS= read -r package; do
      expected="${package}|${KERNEL_VERSION}|${KERNEL_RELEASE}|${TARGET_ARCH}"
      if ! grep -Fxq "${expected}" /out/PINNED_KERNEL_RPMS.txt; then
        echo "ERROR: Expected pinned RPM metadata was not found: ${expected}" >&2
        exit 1
      fi
    done < <(printf "%s\n" "${kernel_packages[@]}")

    (
      cd "${pinned_repo}"
      sha256sum -- *.rpm
    ) > /out/KERNEL_RPM_SHA256SUMS

    createrepo_c "${pinned_repo}"

    mapfile -t packages < <(
      grep -Ev "^[[:space:]]*(#|$)" /packages.txt
    )

    package_args=()
    for package in "${packages[@]}"; do
      package_args+=(--add-package="${package}")
    done

    # Request the pinned kernel package names explicitly. The local repository has
    # priority 1, so DNF must choose these exact older RPMs over newer Stream 9
    # versions of the same package names.
    for package in "${kernel_packages[@]}"; do
      package_args+=(--add-package="${package}")
    done

    echo "Available KIWI profiles:"
    kiwi-ng image info --description=/kiwi --list-profiles || true

    echo "Building with local pinned-kernel repository at priority 1..."
    kiwi-ng \
      --type=iso \
      --profile="${KIWI_PROFILE}" \
      --color-output \
      system build \
      --description=/kiwi \
      --target-dir=/out \
      --clear-cache \
      --add-repo="dir:///pinned-kernel-repo,rpm-md,pinned-kernel,1,false,false,,,,false,baseurl" \
      "${package_args[@]}"
  '

mapfile -t isos < <(
  find "${OUT_DIR}" -maxdepth 1 -type f -name '*.iso' -print | sort
)
if (( ${#isos[@]} != 1 )); then
  echo "ERROR: Expected exactly one ISO in ${OUT_DIR}; found ${#isos[@]}." >&2
  printf '  %s\n' "${isos[@]}" >&2
  exit 1
fi

mapfile -t manifests < <(
  find "${OUT_DIR}" -maxdepth 1 -type f -name '*.packages' -print | sort
)
if (( ${#manifests[@]} != 1 )); then
  echo "ERROR: Expected exactly one KIWI package manifest; found ${#manifests[@]}." >&2
  printf '  %s\n' "${manifests[@]}" >&2
  exit 1
fi

manifest="${manifests[0]}"

# KIWI's package manifest is pipe-delimited:
# name|epoch|version|release|arch|disturl|license
mapfile -t kernel_packages < <(
  grep -Ev '^[[:space:]]*(#|$)' "${SCRIPT_DIR}/kernel-rpms.txt"
)

{
  echo "Kernel pin verification"
  echo "======================="
  echo "Expected: ${KERNEL_VERSION}-${KERNEL_RELEASE}.${TARGET_ARCH}"
  echo "Manifest: ${manifest}"
  echo

  for package in "${kernel_packages[@]}"; do
    mapfile -t matches < <(
      awk -F'|' -v p="${package}" '$1 == p { print $3 "|" $4 "|" $5 }' "${manifest}"
    )

    if (( ${#matches[@]} != 1 )); then
      echo "ERROR: Expected exactly one ${package} entry, found ${#matches[@]}." >&2
      printf '  %s\n' "${matches[@]}" >&2
      exit 1
    fi

    expected="${KERNEL_VERSION}|${KERNEL_RELEASE}|${TARGET_ARCH}"
    if [[ "${matches[0]}" != "${expected}" ]]; then
      echo "ERROR: ${package} is not pinned correctly." >&2
      echo "  expected: ${expected}" >&2
      echo "  actual:   ${matches[0]}" >&2
      exit 1
    fi

    printf '%-24s %s\n' "${package}" "${matches[0]}"
  done
} | tee "${OUT_DIR}/KERNEL_PIN_VERIFIED.txt"

# Ensure no second runtime kernel-core slipped into the image.
mapfile -t runtime_cores < <(
  awk -F'|' '$1 == "kernel-core" { print $3 "|" $4 "|" $5 }' "${manifest}"
)
if (( ${#runtime_cores[@]} != 1 )); then
  echo "ERROR: Expected exactly one installed kernel-core, found ${#runtime_cores[@]}." >&2
  printf '  %s\n' "${runtime_cores[@]}" >&2
  exit 1
fi

(
  cd "${OUT_DIR}"
  sha256sum -- *.iso > SHA256SUMS
)

cat > "${OUT_DIR}/BUILD_INFO.txt" <<EOF
CentOS Stream: 9
KIWI profile: ${KIWI_PROFILE}
Pinned kernel NVR: ${KERNEL_NVR}
Pinned kernel Koji build ID: ${KERNEL_BUILD_ID}
Target architecture: ${TARGET_ARCH}
CentOS KIWI upstream commit: $(cat "${OUT_DIR}/UPSTREAM_COMMIT.txt")
EOF

echo
echo "Build output:"
ls -lh "${OUT_DIR}"
echo
cat "${OUT_DIR}/KERNEL_PIN_VERIFIED.txt"
echo
cat "${OUT_DIR}/SHA256SUMS"
