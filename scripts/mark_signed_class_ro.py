#!/usr/bin/env python3
"""Sets the SignedClassRO flag (1 << 4) in __objc_imageinfo of arm64e slices whose classes are signed.

LLVM 21+ signs class_ro pointers for arm64e but doesn't put the flag into the image info, while
Xcode does. Without it the Objective-C runtime turns class_ro authentication off for the whole
process. The binary has to be re-signed afterwards (ldid -S).

Usage: python3 scripts/mark_signed_class_ro.py <binary>...
"""
import struct, sys

def slices(data):
    if struct.unpack(">I", data[:4])[0] == 0xCAFEBABE:
        for i in range(struct.unpack(">I", data[4:8])[0]):
            cpu, sub, offset, size, _ = struct.unpack(">IIIII", data[8 + i * 20:28 + i * 20])
            yield cpu, sub, offset
    else:
        cpu, sub = struct.unpack("<II", data[4:12])
        yield cpu, sub, 0

def imageinfo_offset(data, base):
    ncmds = struct.unpack("<I", data[base + 16:base + 20])[0]
    offset = base + 32
    for _ in range(ncmds):
        cmd, size = struct.unpack("<II", data[offset:offset + 8])
        if cmd == 0x19:
            nsects = struct.unpack("<I", data[offset + 64:offset + 68])[0]
            for s in range(nsects):
                sect = offset + 72 + s * 80
                if data[sect:sect + 16].rstrip(b"\0") == b"__objc_imageinfo":
                    return base + struct.unpack("<I", data[sect + 48:sect + 52])[0]
        offset += size
    return None

for path in sys.argv[1:]:
    data = bytearray(open(path, "rb").read())
    changed = False
    for cpu, sub, base in slices(data):
        if cpu != 0x100000C or sub & 0xFF != 2:
            continue
        where = imageinfo_offset(data, base)
        if where is None:
            continue
        flags = struct.unpack("<I", data[where + 4:where + 8])[0]
        if not flags & 0x10:
            data[where + 4:where + 8] = struct.pack("<I", flags | 0x10)
            changed = True
            print(f"{path}: image info flags {flags:#x} -> {flags | 0x10:#x}")
    if changed:
        open(path, "wb").write(data)
