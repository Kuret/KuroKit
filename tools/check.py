"""Offline checks for KuroKit, run before /reload in game.

  tools/.venv/Scripts/python.exe -I tools/check.py

- Every .lua file must compile under Lua 5.1 (WoW's Lua version).
- Every file the TOC lists must exist, and every .lua file in the addon
  must be listed in the TOC (an unlisted file is silently never loaded).
- Globals: the compiled bytecode is scanned for global reads and writes.
  * Writes are only allowed for an explicit allowlist (saved variables, slash
    commands, ...). Anything else is an accidental global (missing `local`).
  * Reads of lowercase or very short names (`M`, `db`, ...) are flagged unless
    they're Lua/WoW builtins: WoW's API globals are CamelCase, so such a read
    is almost always a local that's out of scope (e.g. `local M = f(function()
    M:Foo() end)` -- M isn't in scope inside its own initializer).
"""
import pathlib
import re
import struct
import sys

from lupa import lua51

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = ROOT / "KuroKit"
TOC = ADDON / "KuroKit.toc"

ALLOWED_WRITES = re.compile(r"^(KuroKitDB|KuroKit|KuroKit_[A-Za-z]+|SLASH_[A-Z0-9_]+|BINDING_(NAME|HEADER)_KUROKIT_[A-Z0-9_]+)$")

# Lowercase / short globals that are fine to read (Lua stdlib + WoW Lua helpers).
ALLOWED_READS = set("""
    _G assert collectgarbage date debugstack error format geterrorhandler getfenv getmetatable
    hooksecurefunc ipairs issecretvalue issecurevariable math max min next pairs pcall print rawequal rawget rawset
    securecall select setfenv setmetatable string strjoin strlen strlower strmatch strsplit strsub
    strtrim strupper table time tinsert tonumber tostring tremove type unpack wipe xpcall bit
    floor ceil abs sort
""".split())

GETGLOBAL, SETGLOBAL = 5, 7


def toc_files():
    files = []
    for line in TOC.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return files


class Lua51Dump:
    """Minimal reader for Lua 5.1 string.dump output: yields (op, name, line)."""

    def __init__(self, data):
        self.d, self.p = data, 0
        assert data[:4] == b"\x1bLua" and data[4] == 0x51, "not a Lua 5.1 chunk"
        self.little = data[6] == 1
        self.int_size, self.size_t = data[7], data[8]
        self.num_size = data[10]
        self.p = 12
        self.e = "<" if self.little else ">"

    def u8(self):
        v = self.d[self.p]
        self.p += 1
        return v

    def uint(self, size):
        fmt = {4: "I", 8: "Q"}[size]
        v = struct.unpack_from(self.e + fmt, self.d, self.p)[0]
        self.p += size
        return v

    def string(self):
        n = self.uint(self.size_t)
        s = self.d[self.p:self.p + n - 1].decode("utf-8", "replace") if n else None
        self.p += n
        return s

    def function(self, out):
        self.string()  # source
        self.uint(self.int_size)
        self.uint(self.int_size)
        self.p += 4  # nups, numparams, is_vararg, maxstacksize
        code = [self.uint(4) for _ in range(self.uint(self.int_size))]
        consts = []
        for _ in range(self.uint(self.int_size)):
            t = self.u8()
            if t == 0:
                consts.append(None)
            elif t == 1:
                consts.append(bool(self.u8()))
            elif t == 3:
                self.p += self.num_size
                consts.append(0)
            elif t == 4:
                consts.append(self.string())
            else:
                raise ValueError(f"bad constant type {t}")
        for _ in range(self.uint(self.int_size)):
            self.function(out)
        lines = [self.uint(self.int_size) for _ in range(self.uint(self.int_size))]
        for _ in range(self.uint(self.int_size)):  # locvars
            self.string()
            self.uint(self.int_size)
            self.uint(self.int_size)
        for _ in range(self.uint(self.int_size)):  # upvalue names
            self.string()
        for pc, ins in enumerate(code):
            op = ins & 0x3F
            if op in (GETGLOBAL, SETGLOBAL):
                bx = (ins >> 14) & 0x3FFFF
                out.append((op, consts[bx], lines[pc] if pc < len(lines) else 0))

    def globals(self):
        out = []
        self.function(out)
        return out


def suspicious_read(name):
    if name in ALLOWED_READS:
        return False
    return len(name) <= 2 or name[0].islower()


def main():
    lua = lua51.LuaRuntime(encoding=None)  # raw bytes: bytecode is binary
    compile_chunk = lua.eval("""function(src, name)
        local f, err = loadstring(src, name)
        if not f then return nil, err end
        return string.dump(f), false
    end""")
    problems = []

    listed = toc_files()
    for rel in listed:
        if not (ADDON / rel).is_file():
            problems.append(f"TOC lists missing file: {rel}")

    listed_lower = {p.lower() for p in listed}
    for path in sorted(ADDON.rglob("*")):
        if path.suffix.lower() not in (".lua", ".xml"):
            continue
        rel = path.relative_to(ADDON).as_posix()
        if rel.lower() == "bindings.xml":
            continue  # the game loads an addon's Bindings.xml by itself; it must not be in the TOC
        if rel.lower() not in listed_lower:
            problems.append(f"not listed in TOC (never loads): {rel}")
        if path.suffix.lower() != ".lua":
            continue
        dumped, err = compile_chunk(path.read_bytes(), ("@" + rel).encode())
        if err:
            problems.append(f"syntax: {err.decode('utf-8', 'replace')}")
            continue
        raw = bytes(dumped)
        for op, name, line in Lua51Dump(raw).globals():
            if op == SETGLOBAL and not ALLOWED_WRITES.match(name):
                problems.append(f"{rel}:{line}: writes global '{name}' (missing local?)")
            elif op == GETGLOBAL and suspicious_read(name):
                problems.append(f"{rel}:{line}: reads global '{name}' (out-of-scope local?)")

    if problems:
        print("\n".join(problems))
        print(f"\n{len(problems)} problem(s)")
        return 1
    print(f"OK: {len(listed)} TOC entries; Lua 5.1 syntax, TOC and globals all clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
