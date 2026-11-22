#!/usr/bin/env python3
"""Find CBaseEntityOutput::FireOutput in FF 2.0's Windows server.dll and print a SourceMod signature.

  python -I find_fireoutput.py <fortressforever/bin/server.dll>

FireOutput is the only function that pushes the debug string
"(%0.2f) output: (%s,%s) -> (%s,%s,%.1f)(%s)\\n". The function start is the first byte after
the int3/nop padding that precedes the reference. The signature is the function's first
bytes with absolute addresses (relocated operands) wildcarded, extended until it is unique.
"""
import re
import struct
import sys

STR = b"(%0.2f) output: (%s,%s) -> (%s,%s,%.1f)(%s)\n\x00"


def pe(data):
    peoff = struct.unpack_from("<I", data, 0x3C)[0]
    nsec = struct.unpack_from("<H", data, peoff + 6)[0]
    optsz = struct.unpack_from("<H", data, peoff + 20)[0]
    base = struct.unpack_from("<I", data, peoff + 24 + 28)[0]
    secs = []
    o = peoff + 24 + optsz
    for i in range(nsec):
        name = data[o:o + 8].rstrip(b"\0").decode()
        vsize, va, rsize, raw = struct.unpack_from("<IIII", data, o + 8)
        secs.append((name, va, vsize, raw, rsize))
        o += 40
    # base relocations: set of RVAs that hold absolute addresses
    dd = peoff + 24 + 96 + 5 * 8
    reloc_rva, reloc_size = struct.unpack_from("<II", data, dd)
    relocs = set()

    def r2o(rva):
        for n, va, vs, raw, rs in secs:
            if va <= rva < va + max(vs, rs):
                return rva - va + raw
        return None
    p, end = r2o(reloc_rva), r2o(reloc_rva) + reloc_size
    while p < end:
        page, size = struct.unpack_from("<II", data, p)
        if size == 0:
            break
        for i in range((size - 8) // 2):
            e = struct.unpack_from("<H", data, p + 8 + i * 2)[0]
            if e >> 12 == 3:
                relocs.add(page + (e & 0xFFF))
        p += size
    return base, secs, r2o, relocs


def main():
    data = open(sys.argv[1], "rb").read()
    base, secs, r2o, relocs = pe(data)
    text = [s for s in secs if s[0] == ".text"][0]
    so = data.find(STR)
    if so < 0:
        sys.exit("string not found")
    srva = next(va + so - raw for n, va, vs, raw, rs in secs if raw <= so < raw + rs)
    push = b"\x68" + struct.pack("<I", base + srva)
    t0, t1 = text[3], text[3] + text[4]
    refs = []
    i = data.find(push, t0, t1)
    while i >= 0:
        refs.append(i)
        i = data.find(push, i + 1, t1)
    if len(refs) != 1:
        sys.exit("%d references" % len(refs))
    # walk back to the padding before the function
    j = refs[0]
    while j > t0 and not (data[j - 1] in (0xCC, 0x90) and data[j - 2] in (0xCC, 0x90) and data[j - 3] in (0xCC, 0x90)):
        j -= 1
    func_rva = j - t0 + text[1]
    sig = []
    k = 0
    while True:
        rva = func_rva + k
        if any((rva - d) in relocs for d in range(4)):
            # wildcard the 4 relocated bytes
            sig.append(None)
        else:
            sig.append(data[j + k])
        k += 1
        if k >= 16:
            rx = re.compile(b"".join(b"." if b is None else re.escape(bytes([b])) for b in sig), re.S)
            hits = len(rx.findall(data, t0, t1))
            if hits == 1:
                break
        if k > 96:
            sys.exit("no unique signature")
    print("FireOutput at RVA 0x%x (reference at +0x%x)" % (func_rva, refs[0] - j))
    print("".join("\\x2A" if b is None else "\\x%02X" % b for b in sig))


if __name__ == "__main__":
    main()
