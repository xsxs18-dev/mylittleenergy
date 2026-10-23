#!/usr/bin/env python3
"""Checks how a Mach-O's arm64e slice signs its Objective-C metadata.

iOS 18 authenticates the class_ro pointer (and isa/superclass) of every class in an arm64e image.
Binaries from compilers without Objective-C pointer authentication (clang < 21, e.g. older Linux
toolchains) store plain pointers there and crash in readClass() as soon as they load.

Usage: python3 scripts/check_arm64e.py <binary>...   (exit code 1 if a class has unsigned pointers)
"""
import struct, sys

def arm64e_slice(data):
    magic = struct.unpack(">I", data[:4])[0]
    if magic == 0xCAFEBABE:
        for i in range(struct.unpack(">I", data[4:8])[0]):
            cpu, sub, offset, size, _ = struct.unpack(">IIIII", data[8 + i * 20:28 + i * 20])
            if cpu == 0x100000C and sub & 0xFF == 2:
                return data[offset:offset + size]
        return None
    cpu, sub = struct.unpack("<II", data[4:12])
    return data if cpu == 0x100000C and sub & 0xFF == 2 else None

def analyze(macho):
    ncmds = struct.unpack("<I", macho[16:20])[0]
    offset = 32
    segments, sections, fixups = [], [], None
    for _ in range(ncmds):
        cmd, size = struct.unpack("<II", macho[offset:offset + 8])
        if cmd == 0x19:  # LC_SEGMENT_64
            name = macho[offset + 8:offset + 24].rstrip(b"\0").decode()
            vmaddr, vmsize, fileoff = struct.unpack("<QQQ", macho[offset + 24:offset + 48])
            nsects = struct.unpack("<I", macho[offset + 64:offset + 68])[0]
            segments.append((name, vmaddr, fileoff))
            for s in range(nsects):
                base = offset + 72 + s * 80
                sect = macho[base:base + 16].rstrip(b"\0").decode()
                addr, sz = struct.unpack("<QQ", macho[base + 32:base + 48])
                sections.append((sect, addr, sz))
        elif cmd == 0x80000034:  # LC_DYLD_CHAINED_FIXUPS
            fixups = struct.unpack("<II", macho[offset + 8:offset + 16])
        offset += size
    if not fixups:
        return None
    blob = macho[fixups[0]:fixups[0] + fixups[1]]
    starts = struct.unpack("<I", blob[4:8])[0]
    count = struct.unpack("<I", blob[starts:starts + 4])[0]
    result = {}
    for index in range(count):
        seg_off = struct.unpack("<I", blob[starts + 4 + index * 4:starts + 8 + index * 4])[0]
        if not seg_off:
            continue
        base = starts + seg_off
        page_size, fmt, segment_offset, _, page_count = struct.unpack("<IHHQIH", blob[base:base + 22])[1:]
        seg_vm, seg_file = segments[index][1], segments[index][2]
        for page in range(page_count):
            start = struct.unpack("<H", blob[base + 22 + page * 2:base + 24 + page * 2])[0]
            if start == 0xFFFF:
                continue
            location = seg_file + page * page_size + start
            while True:
                value = struct.unpack("<Q", macho[location:location + 8])[0]
                address = seg_vm + (location - seg_file)
                section = next((name for name, addr, sz in sections if addr <= address < addr + sz), "?")
                auth = (value >> 63) & 1
                stats = result.setdefault(section, [0, 0])
                stats[0 if auth else 1] += 1
                step = (value >> 51) & 0x7FF
                if not step:
                    break
                location += step * 8
    return result

failed = False
for path in sys.argv[1:]:
    macho = arm64e_slice(open(path, "rb").read())
    if macho is None:
        print(f"{path}: no arm64e slice")
        continue
    result = analyze(macho) or {}
    data = result.get("__objc_data", [0, 0])
    print(f"{path}")
    for section in sorted(result):
        if section.startswith("__objc") or section == "__const":
            print(f"   {section:22} signed {result[section][0]:4}  plain {result[section][1]:4}")
    if data[0] + data[1] and data[0] == 0:
        print("   -> classes are NOT signed: crashes on iOS 18 arm64e")
        failed = True
sys.exit(1 if failed else 0)
