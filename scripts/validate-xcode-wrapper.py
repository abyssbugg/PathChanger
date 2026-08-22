#!/usr/bin/env python3
"""Validate parity between SwiftPM configuration and the Xcode wrapper."""

from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT_SPEC = ROOT / "project.yml"
PROJECT_FILE = ROOT / "PathChanger.xcodeproj" / "project.pbxproj"
PACKAGE_FILE = ROOT / "Package.swift"
SHIPPED_PLIST = ROOT / "Resources" / "Info.plist"
# There used to be a second, unused Info.plist at PathChanger/Info.plist that was excluded
# from both build definitions. It has been removed; this path is retained only so the check
# below can assert it does not come back.
REMOVED_DUPLICATE_PLIST = ROOT / "PathChanger" / "Info.plist"
ENTITLEMENTS = ROOT / "Resources" / "PathChanger.entitlements"
APP_ENTRY = ROOT / "PathChanger" / "PathChangerApp.swift"
TEST_ROOT = ROOT / "Tests" / "PathChangerTests"
LOCALIZATION_ROOT = ROOT / "PathChanger" / "Resources"
APP_ICON = ROOT / "Resources" / "AppIcon.icns"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def require_text(path: Path, snippets: list[str]) -> str:
    require(path.is_file(), f"Missing required file: {path.relative_to(ROOT)}")
    text = path.read_text(encoding="utf-8")
    for snippet in snippets:
        require(snippet in text, f"{path.relative_to(ROOT)} missing: {snippet}")
    return text


def require_nonempty_string(plist_data: dict[str, object], key: str) -> str:
    value = plist_data.get(key)
    require(isinstance(value, str) and bool(value.strip()), f"{key} must be a non-empty string")
    return value


def validate_required_paths() -> None:
    required_files = [
        PACKAGE_FILE,
        SHIPPED_PLIST,
        ENTITLEMENTS,
        APP_ENTRY,
        LOCALIZATION_ROOT / "en.lproj" / "Localizable.strings",
        LOCALIZATION_ROOT / "ja.lproj" / "Localizable.strings",
        APP_ICON,
    ]
    for path in required_files:
        require(path.is_file(), f"Missing required file: {path.relative_to(ROOT)}")
    require(TEST_ROOT.is_dir(), f"Missing required directory: {TEST_ROOT.relative_to(ROOT)}")
    require(
        not REMOVED_DUPLICATE_PLIST.exists(),
        "PathChanger/Info.plist must not be reintroduced: Resources/Info.plist is the only "
        "shipped plist, and a second one silently diverges",
    )


def validate_package() -> None:
    package = require_text(
        PACKAGE_FILE,
        [
            '.macOS(.v14)',
            '.executable(name: "PathChanger", targets: ["PathChanger"])',
            'https://github.com/sparkle-project/Sparkle',
            '.product(name: "Sparkle", package: "Sparkle")',
            'path: "Tests/PathChangerTests"',
        ],
    )
    require(
        'exclude: ["Info.plist"]' not in package,
        "Package.swift should no longer exclude PathChanger/Info.plist: that file has been removed",
    )


def validate_app_entry() -> None:
    entry_text = APP_ENTRY.read_text(encoding="utf-8")
    entry_count = len(re.findall(r"(?m)^\s*@main\s*$", entry_text))
    require(entry_count == 1, f"Expected one @main annotation in PathChangerApp.swift, found {entry_count}")


def validate_shipped_plist() -> None:
    with SHIPPED_PLIST.open("rb") as handle:
        shipped = plistlib.load(handle)
    require(shipped.get("CFBundleIdentifier") == "com.pathchanger.app", "Unexpected shipped bundle identifier")
    require_nonempty_string(shipped, "CFBundleShortVersionString")
    require_nonempty_string(shipped, "CFBundleVersion")
    require_nonempty_string(shipped, "SUFeedURL")
    require_nonempty_string(shipped, "SUPublicEDKey")
    # The privileged tunnel path uses NSAppleScript, which needs this declared to work under
    # the hardened runtime.
    require_nonempty_string(shipped, "NSAppleEventsUsageDescription")


def validate_project_spec() -> None:
    spec = require_text(
        PROJECT_SPEC,
        [
            "name: PathChanger",
            'macOS: "14.0"',
            "PRODUCT_BUNDLE_IDENTIFIER: com.pathchanger.app",
            "INFOPLIST_FILE: Resources/Info.plist",
            "CODE_SIGN_ENTITLEMENTS: Resources/PathChanger.entitlements",
            "path: PathChanger/Resources",
            "path: Resources/AppIcon.icns",
            "path: Resources/PathChanger.entitlements",
            "package: Sparkle",
            "hostApplication: PathChanger",
            "PathChangerTests:",
        ],
    )
    require("INFOPLIST_FILE: PathChanger/Info.plist" not in spec, "Wrapper must not select the excluded plist")
    require("PathChanger/PathChangerApp.swift" not in spec, "Wrapper must include the source tree, not duplicate the entry file")


def validate_generated_project() -> None:
    require(PROJECT_FILE.is_file(), "Generated PathChanger.xcodeproj/project.pbxproj is missing")


def main() -> int:
    """Return 0 on success and 1 on validation failure."""
    try:
        require(ROOT.is_dir(), f"Repository root is not a directory: {ROOT}")
        validate_required_paths()
        validate_package()
        validate_app_entry()
        validate_shipped_plist()
        validate_project_spec()
        validate_generated_project()
        print("Xcode wrapper parity checks passed")
        return 0
    except AssertionError as error:
        print(f"Xcode wrapper parity check failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
