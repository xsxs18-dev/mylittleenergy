# Installation and migration

MyLittleEnergy uses package ID `com.xsxs18.mylittleenergy`, app group `group.com.xsxs18.mylittleenergy` and URL scheme `mylittleenergy://`.

Version 1.0.13 is free and has no purchase activation or expiry checks. Settings and battery history are retained when upgrading. Obsolete receipts are removed; they are never needed by the free app. The old Voltix package is replaced, with existing settings/history copied only when the destination is absent. Symlinks are not migration sources.

Rootless and RootHide are separate package variants. The RootHide build resolves app/data paths through the RootHide API, uses architecture `iphoneos-arm64e` and has no `/var/jb` archive prefix. Do not install one variant over a different bootstrap. Migration between different jailbreak environments has not been verified.

Device testing remains necessary for respring, cold jailbreak entry, widgets, charging controls and version compatibility.
