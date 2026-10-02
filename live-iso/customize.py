#!/usr/bin/env python3
"""Add the RPM build toolchain to a CentOS Stream 10 Live KIWI profile."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

PREFERRED_PROFILE = "MIN-Live"
FALLBACK_PROFILES = ("GNOME-Live", "KDE-Live", "MAX-Live")
EPEL_URL = "https://dl.fedoraproject.org/pub/epel/10/Everything/$basearch/"
MARKER = "centos-rpmbuild custom packages"


def local_name(tag: str) -> str:
    """Return an XML tag's local name, ignoring an optional namespace."""
    return tag.rsplit("}", 1)[-1].split(":", 1)[-1]


def children_named(element: ET.Element, name: str):
    for child in element:
        if local_name(child.tag) == name:
            yield child


def elements_named(root: ET.Element, name: str):
    for element in root.iter():
        if local_name(element.tag) == name:
            yield element


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
        for element in elements_named(root, "profile")
        if "name" in element.attrib
    }


def select_profile(available: set[str]) -> str:
    if not available:
        raise SystemExit(
            "No KIWI profiles were found in config.xml. "
            "The upstream recipe format may have changed."
        )

    print("Upstream KIWI profiles:")
    for name in sorted(available):
        print(f"  - {name}")

    if PREFERRED_PROFILE in available:
        return PREFERRED_PROFILE

    for fallback in FALLBACK_PROFILES:
        if fallback in available:
            print(
                f"WARNING: {PREFERRED_PROFILE!r} is not available upstream; "
                f"falling back to {fallback!r}."
            )
            return fallback

    live_profiles = sorted(name for name in available if name.endswith("-Live"))
    if live_profiles:
        selected = live_profiles[0]
        print(
            f"WARNING: none of the preferred Live profiles are available; "
            f"falling back to {selected!r}."
        )
        return selected

    raise SystemExit(
        f"No usable Live profile found. Available profiles: "
        f"{', '.join(sorted(available))}"
    )


def configured_packages(root: ET.Element, profile: str) -> set[str]:
    result: set[str] = set()
    for section in elements_named(root, "packages"):
        profiles = {
            part.strip()
            for part in section.attrib.get("profiles", "").split(",")
            if part.strip()
        }
        if profiles and profile not in profiles:
            continue
        for package in children_named(section, "package"):
            name = package.attrib.get("name")
            if name:
                result.add(name)
    return result


def has_epel_repository(root: ET.Element, profile: str) -> bool:
    for repo in elements_named(root, "repository"):
        profiles = {
            part.strip()
            for part in repo.attrib.get("profiles", "").split(",")
            if part.strip()
        }
        if profiles and profile not in profiles:
            continue

        alias = repo.attrib.get("alias", "").lower()
        source_path = ""
        source = next(children_named(repo, "source"), None)
        if source is not None:
            source_path = source.attrib.get("path", "").lower()

        if "epel" in alias or "/epel/" in source_path or "repo=epel" in source_path:
            return True
    return False


def insert_before_first_packages(xml: str, fragment: str) -> str:
    match = re.search(r"<(?:[A-Za-z_][\\w.-]*:)?packages\\b", xml)
    if not match:
        raise SystemExit("Could not find a <packages> section in upstream config.xml")
    return xml[: match.start()] + fragment + xml[match.start() :]


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
    parser.add_argument("--profile-out", type=Path, required=True)
    args = parser.parse_args()

    xml = args.config.read_text(encoding="utf-8")
    if MARKER in xml:
        raise SystemExit(f"{args.config} already contains this customization")

    root = ET.fromstring(xml)
    profile = select_profile(profile_names(root))
    print(f"Selected KIWI profile: {profile}")

    requested = read_packages(args.packages)
    existing = configured_packages(root, profile)
    missing = [package for package in requested if package not in existing]

    # rpmlint is provided by EPEL 10. The official AltImages recipe commonly
    # carries EPEL already; add a profile-scoped EPEL 10 repository when needed.
    if "rpmlint" in requested and not has_epel_repository(root, profile):
        repo_fragment = f'''  <!-- {MARKER}: EPEL -->
  <repository type="rpm-md" alias="epel-rpmbuild" profiles="{escape(profile)}" priority="99">
    <source path="{EPEL_URL}"/>
  </repository>

'''
        xml = insert_before_first_packages(xml, repo_fragment)

    if missing:
        package_lines = "\n".join(
            f'    <package name="{escape(package)}"/>' for package in missing
        )
        package_fragment = f'''  <!-- {MARKER} -->
  <packages type="image" profiles="{escape(profile)}">
{package_lines}
  </packages>

'''
        xml = insert_before_image_end(xml, package_fragment)

    # Fail here, before KIWI starts, if our edit produced malformed XML.
    ET.fromstring(xml)
    args.config.write_text(xml, encoding="utf-8")
    args.profile_out.write_text(profile + "\n", encoding="utf-8")

    print(f"Customized {args.config} for profile {profile}")
    if missing:
        print("Added packages:")
        for package in missing:
            print(f"  - {package}")
    else:
        print("All requested packages were already present upstream")


if __name__ == "__main__":
    main()
