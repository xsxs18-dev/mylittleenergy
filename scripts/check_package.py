#!/usr/bin/env python3
"""Validate the rootless Debian package without requiring dpkg (Python 3.9+)."""
import hashlib
import io
import plistlib
import sys
import tarfile
from pathlib import Path


def check(path):
    data = Path(path).read_bytes()
    assert data[:8] == b"!<arch>\n", "Not a Debian ar archive"
    archives = {}
    offset = 8
    while offset < len(data):
        header = data[offset:offset + 60]
        assert len(header) == 60 and header[58:] == b"`\n", "Invalid ar header"
        size = int(header[48:58])
        name = header[:16].decode().strip().rstrip("/")
        payload = data[offset + 60:offset + 60 + size]
        assert len(payload) == size, "Truncated archive"
        offset += 60 + size + size % 2
        if name.startswith(("data.tar", "control.tar")):
            archives[name.split(".")[0]] = tarfile.open(fileobj=io.BytesIO(payload))
    control = archives["control"]
    controls = {m.name.removeprefix("./"): m for m in control.getmembers()}
    metadata = control.extractfile(controls["control"]).read().decode()
    version = next(line.split(": ", 1)[1] for line in metadata.splitlines() if line.startswith("Version: "))
    arch = next(line.split(": ", 1)[1] for line in metadata.splitlines() if line.startswith("Architecture: "))
    assert arch in ("iphoneos-arm64", "iphoneos-arm64e"), "Unsupported package architecture"
    prefix = "var/jb/" if arch == "iphoneos-arm64" else ""
    for name in ("preinst", "postinst", "prerm", "postrm"):
        assert controls[name].mode & 0o111, f"{name} must be executable"
    archive = archives["data"]
    members = {m.name.removeprefix("./"): m for m in archive.getmembers()}
    binaries = (
        "Library/MobileSubstrate/DynamicLibraries/MyLittleEnergy.dylib",
        "usr/libexec/mylittleenergyd",
        "Applications/MyLittleEnergy.app/MyLittleEnergy",
        "Applications/MyLittleEnergy.app/PlugIns/MyLittleEnergyWidgets.appex/MyLittleEnergyWidgets",
        "Library/ControlCenter/Bundles/MyLittleEnergyModule.bundle/MyLittleEnergyModule",
    )
    for binary in binaries:
        name = prefix + binary
        member = members[name]
        magic = archive.extractfile(member).read(4)
        assert magic in (b"\xca\xfe\xba\xbe", b"\xcf\xfa\xed\xfe"), f"Invalid Mach-O: {name}"
        assert member.mode & 0o111, f"{name} must be executable"
    assert not any(name.startswith("var/jb/var/jb/") for name in members), "Double rootless prefix"
    for name, member in members.items():
        if member.isfile() and name.endswith(".plist"):
            raw = archive.extractfile(member).read()
            # The Substrate filter uses Apple's legacy OpenStep syntax.
            if name.endswith("/DynamicLibraries/MyLittleEnergy.plist"):
                assert b'"com.apple.UIKit"' in raw, "Missing UIKit injection filter"
                continue
            info = plistlib.loads(raw)
            if name.endswith("/Info.plist"):
                assert info["CFBundleShortVersionString"] == version, f"Version mismatch: {name}"
    assert prefix + "Library/LaunchDaemons/com.xsxs18.mylittleenergyd.plist" in members
    if not prefix:
        assert not any(name.startswith("var/jb/") for name in members), "RootHide package must not have a rootless prefix"
    print(f"PASS: package layout, binaries, versions, property lists and maintainer permissions ({version})")
    print(f"SHA256: {hashlib.sha256(data).hexdigest()}")


if __name__ == "__main__":
    check(sys.argv[1])
