#!/usr/bin/env python3
"""Fails if a property list in the project doesn't parse (a broken Info.plist only shows up on the device)."""
import glob, plistlib, sys

files = ["App/Resources/Info.plist", "Widgets/Info.plist", "CCModule/Resources/Info.plist", "layout/Library/LaunchDaemons/com.xsxs18.mylittleenergyd.plist"]
files += glob.glob("*/entitlements.plist")
failed = False
for path in files:
    try:
        with open(path, "rb") as handle:
            plistlib.load(handle)
    except Exception as error:
        print(f"{path}: {error}")
        failed = True
sys.exit(1 if failed else 0)
