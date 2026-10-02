#!/usr/bin/env python3
"""Add the RPM build toolchain to the CentOS Stream MIN-Live KIWI profile."""

from __future__ import annotations

import argparse
from pathlib import Path
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

PROFILE = "MIN-Live"
EPEL_URL = "https://dl.fedoraproject.org/pub/epel/10/Everything/$basearch/"
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


def profile_names(root: ET.Element) -> set[str]:
    return {
        element.attrib["name"]
        for element in root.findall("./profiles/profile")
        if "name" in element.attrib
    }


def configured_packages(root: ET.Element) -> set[str]:
    result: set[str] = set()
    for section in root.findall("./packages"):
        profiles = {
            part.strip()
            for part in section.attrib.get("profiles", "").split(",")
            if part.strip()
        }
        if profiles and PROFILE not in profiles:
            continue
        for package in section.findall("./package"):
            name = package.attrib.get("name")
            if name:
                result.add(name)
    return result


def has_epel_repository(root: ET.Element) -> bool:
    for repo in root.findall("./repository"):
        alias = repo.attrib.get("alias", "").lower()
        source = repo.find("./source")
        source_path = source.attrib.get("path", "").lower() if source is not None else ""
        if "epel" in alias or "/epel/" in source_path or "repo=epel" in source_path:
            return True
    return False


def insert_before_first_packages(xml: str, fragment: str) -> str:
    index = xml.find("<packages")
    if index < 0:
        raise SystemExit("Could not find a <packages> section in upstream config.xml")
    return xml[:index] + fragment + xml[index:]


def insert_before_image_end(xml: str, fragment: str) -> str:
    index = xml.rfind("</image>")
    if index < 0:
        raise SystemExit("Could not find </image> in upstream config.xml")
    return xml[:index] + fragment + xml[index:]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--packages", type=Path, required=True)
    args = parser.parse_args()

    xml = args.config.read_text(encoding="utf-8")
    if MARKER in xml:
        raise SystemExit(f"{args.config} already contains this customization")

    root = ET.fromstring(xml)
    if PROFILE not in profile_names(root):
        raise SystemExit(
            f"Upstream KIWI description has no {PROFILE!r} profile; "
            "the CentOS recipe may have changed"
        )

    requested = read_packages(args.packages)
    existing = configured_packages(root)
    missing = [package for package in requested if package not in existing]

    # rpmlint is provided by EPEL 10. The official AltImages recipe commonly
    # carries EPEL already; add a build-only EPEL repo when it does not.
    if "rpmlint" in requested and not has_epel_repository(root):
        repo_fragment = f'''  <!-- {MARKER}: EPEL -->
  <repository type="rpm-md" alias="epel-rpmbuild" profiles="{PROFILE}" priority="99">
    <source path="{EPEL_URL}"/>
  </repository>

'''
        xml = insert_before_first_packages(xml, repo_fragment)

    if missing:
        package_lines = "\n".join(
            f'    <package name="{escape(package)}"/>' for package in missing
        )
        package_fragment = f'''  <!-- {MARKER} -->
  <packages type="image" profiles="{PROFILE}">
{package_lines}
  </packages>

'''
        xml = insert_before_image_end(xml, package_fragment)

    # Fail here, before KIWI starts, if our edit produced malformed XML.
    ET.fromstring(xml)
    args.config.write_text(xml, encoding="utf-8")

    print(f"Customized {args.config} for profile {PROFILE}")
    if missing:
        print("Added packages:")
        for package in missing:
            print(f"  - {package}")
    else:
        print("All requested packages were already present upstream")


if __name__ == "__main__":
    main()
