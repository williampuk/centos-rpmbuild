#!/usr/bin/env python3
"""Verify that the configured CentOS Stream Koji build is the expected kernel."""

import os
import sys
import xmlrpc.client


def required_packages(path: str) -> list[str]:
    with open(path, encoding="utf-8") as f:
        return [
            line.strip()
            for line in f
            if line.strip() and not line.lstrip().startswith("#")
        ]


def main() -> int:
    hub = os.environ["KOJI_HUB"]
    build_id = int(os.environ["KERNEL_BUILD_ID"])
    version = os.environ["KERNEL_VERSION"]
    release = os.environ["KERNEL_RELEASE"]
    arch = os.environ["TARGET_ARCH"]
    expected_nvr = f"kernel-{version}-{release}"

    required = required_packages("/kernel-rpms.txt")
    session = xmlrpc.client.ServerProxy(hub, allow_none=True)

    build = session.getBuild(build_id)
    if not build:
        raise SystemExit(f"Koji build ID {build_id} does not exist")

    actual_nvr = build.get("nvr")
    if actual_nvr != expected_nvr:
        raise SystemExit(
            f"Koji build ID {build_id} is {actual_nvr!r}, "
            f"expected {expected_nvr!r}"
        )

    # Python's raw xmlrpc.client accepts positional RPC arguments only.
    # Koji listRPMs() takes buildID as its first argument.
    rpms = session.listRPMs(build_id)

    selected: dict[str, dict] = {}
    for rpm in rpms:
        if rpm.get("name") in required and rpm.get("arch") == arch:
            selected[rpm["name"]] = rpm

    missing = [name for name in required if name not in selected]
    if missing:
        raise SystemExit(
            f"Required {arch} RPMs missing from Koji build {build_id}: "
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

    return 0


if __name__ == "__main__":
    sys.exit(main())
