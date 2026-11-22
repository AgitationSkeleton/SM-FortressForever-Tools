#!/usr/bin/env python3
"""Dump a class vtable from Fortress Forever's Linux server.so, which ships with symbols.

  python -I elfvt.py <server.so> <ClassName> [filter]

Prints every slot as "linux <n>  windows <m>  <demangled name>". The Windows slot is
derived by the rule in windows_slots() below; check it against the game before relying
on it (gen_gamedata.py lists the slots that were checked on a Windows server).

Needs GNU binutils (readelf and c++filt) on PATH, or in the folder named by the
BINUTILS environment variable (for example a MinGW-w64 bin folder on Windows).
"""
import os
import re
import shutil
import struct
import subprocess
import sys


def _tool(name):
    d = os.environ.get("BINUTILS")
    if d:
        for cand in (name, name + ".exe"):
            p = os.path.join(d, cand)
            if os.path.isfile(p):
                return p
    p = shutil.which(name)
    if not p:
        sys.exit("%s not found: put GNU binutils on PATH or set BINUTILS" % name)
    return p


def _run(name, *args, stdin=None):
    return subprocess.run([_tool(name)] + list(args), input=stdin, capture_output=True,
                          text=True, errors="replace").stdout


class Elf:
    """Symbols and R_386_32 relocations of a 32-bit server.so."""

    def __init__(self, path):
        self.path = path
        self.data = open(path, "rb").read()
        self.secs = []
        for m in re.finditer(r"\]\s+(\S+)\s+\S+\s+([0-9a-f]{8})\s+([0-9a-f]{6,8})\s+([0-9a-f]{6,8})",
                             _run("readelf", "-SW", path)):
            self.secs.append((int(m.group(2), 16), int(m.group(3), 16), int(m.group(4), 16)))
        self.syms, self.byaddr = {}, {}
        for line in _run("readelf", "-sW", path).splitlines():
            p = line.split()
            if len(p) >= 8 and p[0].endswith(":"):
                try:
                    val, size = int(p[1], 16), int(p[2])
                except ValueError:
                    continue
                self.syms[p[7]] = (val, size)
                if p[3] == "FUNC" and val:
                    self.byaddr.setdefault(val, p[7])
        self.relsym = {}
        for line in _run("readelf", "-rW", path).splitlines():
            p = line.split()
            if len(p) >= 5 and p[2] == "R_386_32":
                self.relsym[int(p[0], 16)] = p[4]
        self._cache = {}

    def _v2o(self, addr):
        for a, o, s in self.secs:
            if a and a <= addr < a + s:
                return addr - a + o
        return None

    def vtable(self, cls):
        """Demangled names of the primary vtable of cls, from slot 0 (GCC's first destructor)."""
        if cls in self._cache:
            return self._cache[cls]
        mangled = "_ZTV%d%s" % (len(cls), cls)
        if mangled not in self.syms:
            sys.exit("no vtable symbol " + mangled)
        va, size = self.syms[mangled]
        off = self._v2o(va)
        names = []
        for i in range(2, size // 4):          # skip offset-to-top and typeinfo
            slot = va + i * 4
            if slot in self.relsym:
                names.append(self.relsym[slot])
            else:
                ptr = struct.unpack_from("<I", self.data, off + i * 4)[0]
                names.append(self.byaddr.get(ptr, "0x%08x" % ptr))
        dem = _run("c++filt", stdin="\n".join(names)).splitlines()
        # a secondary vtable starts with "-N" offset-to-top then a typeinfo symbol
        out = []
        for d in dem:
            if d.startswith("typeinfo for") or re.match(r"^0x[0-9a-f]{8}$", d) and out and \
                    int(d, 16) > 0xF0000000:
                break
            out.append(d)
        self._cache[cls] = out
        return out


def method_of(demangled):
    """'CBaseEntity::KeyValue(char const*, float)' -> ('KeyValue', 'KeyValue(char const*, float)')"""
    m = re.match(r"^(?:.*::)?(~?[A-Za-z_][A-Za-z0-9_]*)(\(.*)$", demangled)
    if not m:
        return demangled, demangled
    return m.group(1), m.group(1) + m.group(2)


def windows_slots(names):
    """Map Linux slot -> Windows slot for one vtable.

    * GCC emits two destructor slots (complete and deleting) where MSVC emits one, so
      every slot after them is one lower on Windows.
    * MSVC groups the overloads of a virtual declared in one class and lays them out in
      reverse declaration order; GCC keeps declaration order. So a run of consecutive
      slots with the same method name is reversed (KeyValue x3, SetModel x2,
      CommitSuicide x2, NetworkStateChanged_* pairs, CFFPlayer::Ignite x2).
    """
    win = {}
    i, n = 2, len(names)
    while i < n:
        name = method_of(names[i])[0]
        j = i
        while j + 1 < n and method_of(names[j + 1])[0] == name:
            j += 1
        for k in range(i, j + 1):
            win[k] = (i + (j - k)) - 1
        i = j + 1
    return win


def main():
    so, cls = sys.argv[1], sys.argv[2]
    flt = sys.argv[3].lower() if len(sys.argv) > 3 else None
    names = Elf(so).vtable(cls)
    win = windows_slots(names)
    for i, d in enumerate(names):
        if flt and flt not in d.lower():
            continue
        w = win.get(i)
        print("linux %4d  windows %4s  %s" % (i, "-" if w is None else w, d))


if __name__ == "__main__":
    main()
