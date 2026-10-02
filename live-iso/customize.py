#!/usr/bin/env python3
"""Add the RPM build toolchain to the CentOS Stream 10 MIN-Live KIWI recipe."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

PROFILE = "MIN-Live"
MARKER = "centos-rpmbuild custom packages"


def read_packages(path: Path) -> list[str]:
    packages: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        packages.append(line)
    if not packages:
        raise SystemExit(f"No packages found in {path}")
    return packages


def insert_before_image_end(xml: str, fragment: str) -> str:
    matches = list(re.finditer(r"</(?:[A-Za-z_][\\w.-]*:)?image\\s*>", xml))
    if not matches:
        raise SystemExit("Could not find </image> in upstream config.xml")
    match = matches[-1]
    return xml[: match.start()] + fragment + xml[match.start() :]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--packages", type=Path, required=True)
    args = parser.parse_args()

    xml = args.config.read_text(encoding="utf-8")
    if MARKER in xml:
        raise SystemExit(f"{args.config} already contains this customization")

    # Validate that the upstream file is at least well-formed XML before editing it.
    ET.fromstring(xml)

    requested = read_packages(args.packages)
    package_lines = "\n".join(
        f'    <package name="{escape(package)}"/>' for package in requested
    )

    package_fragment = f'''  <!-- {MARKER} -->
  <packages type="image" profiles="{PROFILE}">
{package_lines}
  </packages>

'''

    xml = insert_before_image_end(xml, package_fragment)

    # Fail before KIWI starts if our edit produced malformed XML.
    ET.fromstring(xml)
    args.config.write_text(xml, encoding="utf-8")

    print(f"Customized {args.config} for KIWI profile {PROFILE}")
    print("Added packages:")
    for package in requested:
        print(f"  - {package}")


if __name__ == "__main__":
    main()
