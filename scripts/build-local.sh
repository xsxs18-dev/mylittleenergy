#!/bin/bash
# Builds the rootless .deb on Linux without GitHub Actions.
#
# The Objective-C parts (tweak, CC module) are loaded into arm64e system processes. iOS 18 only
# accepts arm64e Objective-C classes whose metadata is signed, which needs clang 21 or newer, so
# they are compiled with $LLVM (the official LLVM release, e.g. ~/llvm-23) and linked with the
# ld64 of $THEOS_OBJC. The daemon is arm64 only.
# The Swift parts (app, widgets) need a Swift toolchain, so they use $THEOS_SWIFT (Theos with
# kabiroberai's swift-5.8 Linux toolchain and the iOS 16.5 SDK; arm64 only, so the old clang is fine).
#
# Usage: scripts/build-local.sh   ->  packages/com.xsxs18.mylittleenergy_<version>_iphoneos-arm64.deb
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME=${THEOS_PACKAGE_SCHEME:-rootless}
case "$SCHEME" in
    rootless) ARCH=iphoneos-arm64; PREFIX=/var/jb ;;
    roothide) ARCH=iphoneos-arm64e; PREFIX= ;;
    *) echo "Unsupported package scheme: $SCHEME" >&2; exit 1 ;;
esac
export THEOS_PACKAGE_SCHEME="$SCHEME"
THEOS_OBJC=${THEOS_OBJC:-$HOME/theos}
if [ "$SCHEME" = roothide ]; then THEOS_OBJC=${THEOS_ROOTHIDE:-$HOME/theos-roothide}; fi
THEOS_SWIFT=${THEOS_SWIFT:-$HOME/theos-swift}
LLVM=${LLVM:-$HOME/llvm-23}
# Parts can be left out for test builds, e.g. SWIFT_PARTS=App OBJC_PARTS="Daemon Tweak"
OBJC_PARTS=${OBJC_PARTS:-Daemon Tweak CCModule}
SWIFT_PARTS=${SWIFT_PARTS:-App Widgets}
VERSION=$(sed -n 's/^Version: //p' control)
PACKAGE=$(sed -n 's/^Package: //p' control)
STAGE=.theos/local-stage
LOGS=.theos/logs
OUT=packages/${PACKAGE}_${VERSION}_${ARCH}.deb
STAGE_ROOT="$STAGE$PREFIX"

for tool in make perl python3; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "Missing build dependency: $tool" >&2
		exit 1
	fi
done
python3 scripts/test_migration.py
python3 scripts/release_build.py --check
python3 scripts/strings.py . > /dev/null
python3 scripts/check_plists.py
rm -rf .theos ./*/.theos
mkdir -p "$STAGE_ROOT" "$LOGS" packages

if [ ! -x "$LLVM/bin/clang" ]; then
	echo "Missing $LLVM/bin/clang (LLVM 21 or newer, see README)"
	exit 1
fi
OBJC_TOOLS=(TARGET_CC="$LLVM/bin/clang" TARGET_CXX="$LLVM/bin/clang++" TARGET_LD="$THEOS_OBJC/toolchain/linux/iphone/bin/clang++")

build() {
	local theos=$1 parts=$2 log="$LOGS/$(echo "$2" | tr ' ' '-').log"
	shift 2
	echo "==> Building $parts"
	if ! THEOS="$theos" make stage SUBPROJECTS="$parts" FINALPACKAGE=1 "$@" > "$log" 2>&1; then
		grep -v "no version information available" "$log" | grep -E "error|Error" | head -40
		echo "Build failed, full log: $log"
		exit 1
	fi
	grep -v "no version information available" "$log" | grep -E "warning:" | sort -u | head -20 || true
	cp -a .theos/_/. "$STAGE_ROOT/"
}

build "$THEOS_OBJC" "$OBJC_PARTS" "${OBJC_TOOLS[@]}"
if [ "$SCHEME" = roothide ]; then
    build "$THEOS_OBJC" "$SWIFT_PARTS" SDKBINPATH="$THEOS_SWIFT/toolchain/linux/iphone/bin" SWIFTBINPATH="$THEOS_SWIFT/toolchain/linux/iphone/bin" THEOS_VENDOR_SWIFT_SUPPORT_PATH="$THEOS_SWIFT/vendor/swift-support" _THEOS_PLATFORM_SWIFT="$THEOS_SWIFT/toolchain/linux/host/bin/swift"
else
    build "$THEOS_SWIFT" "$SWIFT_PARTS"
fi

# Same version everywhere, like the CI build does with plutil.
python3 - "$STAGE_ROOT" "$VERSION" <<'PY'
import plistlib, sys
root, version = sys.argv[1], sys.argv[2]
import os
for path in ("Applications/MyLittleEnergy.app/Info.plist", "Applications/MyLittleEnergy.app/PlugIns/MyLittleEnergyWidgets.appex/Info.plist", "Library/ControlCenter/Bundles/MyLittleEnergyModule.bundle/Info.plist"):
    if not os.path.exists(f"{root}/{path}"):
        continue
    with open(f"{root}/{path}", "rb") as handle:
        plist = plistlib.load(handle)
    plist["CFBundleShortVersionString"] = version
    with open(f"{root}/{path}", "wb") as handle:
        plistlib.dump(plist, handle, fmt=plistlib.FMT_BINARY)
PY

# Same image info flags as Xcode (see scripts/mark_signed_class_ro.py), then sign again.
for binary in "$STAGE_ROOT/Library/MobileSubstrate/DynamicLibraries/MyLittleEnergy.dylib" "$STAGE_ROOT/Library/ControlCenter/Bundles/MyLittleEnergyModule.bundle/MyLittleEnergyModule"; do
	[ -f "$binary" ] || continue
	if [ -n "$(python3 scripts/mark_signed_class_ro.py "$binary")" ]; then
		ldid -S "$binary"
	fi
done

# arm64e code goes into SpringBoard and other system processes. iOS 18 crashes them if the
# Objective-C classes in it aren't signed, which older clang versions can't do.
find "$STAGE_ROOT" -type f \( -name "*.dylib" -o -perm -u+x \) -print0 | while IFS= read -r -d '' binary; do
	if head -c 4 "$binary" | od -An -tx1 | grep -qE "ca fe ba be|cf fa ed fe"; then
		if ! python3 scripts/check_arm64e.py "$binary" > /dev/null; then
			python3 scripts/check_arm64e.py "$binary" || true
			echo "Refusing to package: $binary has unsigned Objective-C classes in its arm64e slice (needs clang 21+ or Xcode)."
			exit 1
		fi
	fi
done

# A page hash that doesn't match the code makes the kernel kill the process.
find "$STAGE_ROOT" -type f \( -name "*.dylib" -o -perm -u+x \) -print0 | while IFS= read -r -d '' binary; do
	if head -c 4 "$binary" | od -An -tx1 | grep -qE "ca fe ba be|cf fa ed fe"; then
		python3 scripts/verify_signature.py "$binary" > /dev/null || { python3 scripts/verify_signature.py "$binary" || true; echo "Refusing to package: bad code signature in $binary"; exit 1; }
	fi
done

# layout/DEBIAN is staged under var/jb as well; it belongs at the top.
rm -rf "$STAGE_ROOT/DEBIAN"
mkdir -p "$STAGE/DEBIAN"
cp layout/DEBIAN/* "$STAGE/DEBIAN/"
if [ "$SCHEME" = roothide ]; then
    # RootHide packages have no /var/jb archive prefix; bootstrap tools resolve these paths.
    sed -i 's|/var/jb/|/|g' "$STAGE"/DEBIAN/* "$STAGE_ROOT/Library/LaunchDaemons/com.xsxs18.mylittleenergyd.plist"
fi
{
	sed "s/^Architecture: .*/Architecture: $ARCH/" control
	echo "Icon: file://$PREFIX/Applications/MyLittleEnergy.app/AppIcon60x60@3x.png"
	echo "Installed-Size: $(du -ks --exclude=DEBIAN "$STAGE" | cut -f1)"
} > "$STAGE/DEBIAN/control"

rm -f "$OUT"
COPYFILE_DISABLE=1 "$THEOS_OBJC/bin/dm.pl" -Zxz -z9 -b "$STAGE" "$OUT"
python3 scripts/check_package.py "$OUT"
echo "==> $OUT ($(du -h "$OUT" | cut -f1))"

# Publish only after compilation, signature checks and package validation succeed.
python3 scripts/release_build.py "$OUT" --push-source
