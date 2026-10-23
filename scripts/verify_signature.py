#!/usr/bin/env python3
"""Verifies every slice's code directory page hashes and prints the arm64e image info flags.

Usage: python3 scripts/verify_signature.py <binary>...   (exit code 1 on a hash mismatch)
"""
import hashlib, struct, sys

def slices(data):
    if struct.unpack(">I", data[:4])[0] == 0xCAFEBABE:
        for i in range(struct.unpack(">I", data[4:8])[0]):
            cpu, sub, offset, size, _ = struct.unpack(">IIIII", data[8 + i * 20:28 + i * 20])
            yield cpu, sub, data[offset:offset + size]
    else:
        cpu, sub = struct.unpack("<II", data[4:12])
        yield cpu, sub, data

def check(macho):
    ncmds = struct.unpack("<I", macho[16:20])[0]
    offset, sig, flags = 32, None, None
    for _ in range(ncmds):
        cmd, size = struct.unpack("<II", macho[offset:offset + 8])
        if cmd == 0x1D:
            sig = struct.unpack("<II", macho[offset + 8:offset + 16])
        elif cmd == 0x19:
            for s in range(struct.unpack("<I", macho[offset + 64:offset + 68])[0]):
                sect = offset + 72 + s * 80
                if macho[sect:sect + 16].rstrip(b"\0") == b"__objc_imageinfo":
                    fo = struct.unpack("<I", macho[sect + 48:sect + 52])[0]
                    flags = struct.unpack("<I", macho[fo + 4:fo + 8])[0]
        offset += size
    blob = macho[sig[0]:sig[0] + sig[1]]
    count = struct.unpack(">I", blob[8:12])[0]
    bad = checked = 0
    for i in range(count):
        kind, off = struct.unpack(">II", blob[12 + i * 8:20 + i * 8])
        cd = blob[off:]
        if struct.unpack(">I", cd[:4])[0] != 0xFADE0C02:
            continue
        hash_offset, _, n_special, n_code, code_limit, hash_size, hash_type, _, page_shift = struct.unpack(">IIIIIBBBB", cd[16:40])
        algo = {1: hashlib.sha1, 2: hashlib.sha256}[hash_type]
        page = 1 << page_shift
        for p in range(n_code):
            chunk = macho[p * page:min((p + 1) * page, code_limit)]
            want = cd[hash_offset + p * hash_size:hash_offset + (p + 1) * hash_size]
            checked += 1
            if algo(chunk).digest()[:hash_size] != want:
                bad += 1
    return flags, checked, bad

failed = False
for path in sys.argv[1:]:
    for cpu, sub, macho in slices(open(path, "rb").read()):
        arch = "arm64e" if sub & 0xFF == 2 else "arm64"
        flags, checked, bad = check(macho)
        print(f"{path.split('/')[-1]} {arch}: page hashes {checked - bad}/{checked} ok, objc image info {flags:#x}" if flags is not None else f"{path.split('/')[-1]} {arch}: page hashes {checked - bad}/{checked} ok")
        failed |= bad > 0
sys.exit(1 if failed else 0)
