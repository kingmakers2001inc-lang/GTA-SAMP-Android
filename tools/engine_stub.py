#!/usr/bin/env python3
"""Engine import helper for builds without a matching libGTASA.so.

  stub   Writes and compiles a stand-in libGTASA.so that defines the given symbols,
         so libSAMP.so can link with -z defs. At runtime the game's real library is
         used; the stand-in only satisfies the linker.
  check  Lists the imports a real libGTASA.so does not export. Run it against a new
         game build before trusting a libSAMP.so built for it.

Symbol lists are one mangled name per line, optionally followed by "object" for data.
"""

import argparse
import os
import re
import subprocess
import sys


def read_symbols(path):
    symbols = []
    for line in open(path):
        parts = line.split()
        if parts:
            symbols.append((parts[0], len(parts) > 1 and parts[1] == "object"))
    return symbols


def exported_symbols(nm, lib):
    out = subprocess.check_output([nm, "-D", "--defined-only", lib]).decode()
    exported = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3:
            exported[parts[2]] = parts[1]
    return exported


def cmd_stub(args):
    symbols = read_symbols(args.symbols)
    lines = []
    for name, is_object in symbols:
        if not re.match(r"^[A-Za-z0-9_.$]+$", name):
            sys.exit("unexpected symbol name: " + name)
        if is_object:
            lines += [".data", ".globl %s" % name, ".type %s, %%object" % name, ".size %s, 16" % name,
                      "%s:" % name, ".zero 16"]
        else:
            lines += [".text", ".globl %s" % name, ".type %s, %%function" % name, "%s:" % name,
                      "ret" if args.arch == "arm64" else "bx lr"]
    source = os.path.splitext(args.out)[0] + ".S"
    with open(source, "w") as f:
        f.write("\n".join(lines) + "\n")
    subprocess.check_call([args.cc, "-shared", "-nostdlib", "-Wl,-soname,libGTASA.so", source, "-o", args.out])
    print("stub with %d symbols: %s" % (len(symbols), args.out))


def cmd_check(args):
    exported = exported_symbols(args.nm, args.lib)
    missing = [name for name, _ in read_symbols(args.symbols) if name not in exported]
    for name in missing:
        demangled = subprocess.run(["c++filt", name], stdout=subprocess.PIPE).stdout.decode().strip()
        print("missing: %s  (%s)" % (name, demangled))
    print("%d of %d imports missing from %s" % (len(missing), len(read_symbols(args.symbols)), args.lib))
    sys.exit(1 if missing else 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    stub = sub.add_parser("stub")
    stub.add_argument("--symbols", required=True)
    stub.add_argument("--arch", choices=["arm", "arm64"], required=True)
    stub.add_argument("--cc", required=True, help="NDK clang for the target ABI")
    stub.add_argument("--out", required=True)
    stub.set_defaults(func=cmd_stub)

    check = sub.add_parser("check")
    check.add_argument("--symbols", required=True)
    check.add_argument("--lib", required=True, help="the game's libGTASA.so")
    check.add_argument("--nm", default="llvm-nm")
    check.set_defaults(func=cmd_check)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
