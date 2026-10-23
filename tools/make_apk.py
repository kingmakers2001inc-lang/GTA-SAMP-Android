#!/usr/bin/env python3
"""Turns your own GTA: San Andreas APK into a multiplayer APK.

It adds libSAMP.so next to libGTASA.so, makes the game load it right after
libGTASA.so, optionally bakes in a server address, then rebuilds and signs
the APK. The game itself is not part of this repository and is not
distributed: you need your own copy.

Requirements: Java 8+, apktool, and zipalign + apksigner from the Android
SDK build-tools.

Example:
  python3 tools/make_apk.py --apk gta_sa.apk --host 203.0.113.5 --port 7777
"""

import argparse
import hashlib
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ABIS = ("arm64-v8a", "armeabi-v7a")
ELF_CLASS = {"armeabi-v7a": 1, "arm64-v8a": 2}

# Game builds the client has been reverse engineered against, by ABI
KNOWN_GAME_BUILDS = {
    "armeabi-v7a": {"59e7198de1916d5f7d22037233f385983099fd53cfab07c707ca25b9d7a834d7": "early 32-bit build (libs/libGTASA.so)"},
    "arm64-v8a": {},
}

# Matches the defaults block in src/CNetGame.cpp
DEFAULTS_MAGIC = b"SAMP_DEFAULTS_1\0"
DEFAULTS_FIELDS = [("host", 64), ("port", 8), ("name", 25)]

LOAD_GTASA = re.compile(
    r'^(?P<indent>\s*)const-string(?:/jumbo)? (?P<reg>[vp]\d+), "GTASA"\s*\n'
    r'(?P<blank>(?:\s*\n|\s*\.line \d+\s*\n)*)'
    r'(?P=indent)invoke-static \{(?P=reg)\}, Ljava/lang/System;->loadLibrary\(Ljava/lang/String;\)V\s*\n',
    re.MULTILINE,
)


def fail(message):
    sys.exit("error: " + message)


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def run(cmd, quiet=False):
    print("+ " + " ".join(cmd))
    result = subprocess.run(cmd, stdout=subprocess.PIPE if quiet else None, stderr=subprocess.STDOUT if quiet else None)
    if result.returncode != 0:
        if quiet and result.stdout:
            sys.stdout.write(result.stdout.decode(errors="replace"))
        fail("command failed: " + cmd[0])


def find_tool(name, explicit, search_dirs=()):
    if explicit:
        if not os.path.exists(explicit):
            fail("%s not found at %s" % (name, explicit))
        return explicit
    for directory in search_dirs:
        for candidate in (name, name + ".bat", name + ".exe"):
            path = os.path.join(directory, candidate)
            if os.path.exists(path):
                return path
    found = shutil.which(name)
    if not found:
        fail("%s not found. Install it or pass its path (see --help)." % name)
    return found


def apktool_command(args):
    if args.apktool_jar:
        return ["java", "-jar", args.apktool_jar]
    return [find_tool("apktool", args.apktool)]


def build_tools_dirs(args):
    dirs = []
    if args.build_tools:
        dirs.append(args.build_tools)
    for env in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        sdk = os.environ.get(env)
        bt = os.path.join(sdk, "build-tools") if sdk else None
        if bt and os.path.isdir(bt):
            dirs += [os.path.join(bt, v) for v in sorted(os.listdir(bt), reverse=True)]
    return dirs


def elf_dynamic_symbols(path):
    """Returns (elf class, exported names, unversioned undefined names) from .dynsym."""
    data = open(path, "rb").read()
    if data[:4] != b"\x7fELF":
        fail(path + " is not an ELF library")
    is64 = data[4] == 2
    if is64:
        shoff, = struct.unpack_from("<Q", data, 0x28)
        shentsize, shnum = struct.unpack_from("<HH", data, 0x3A)
    else:
        shoff, = struct.unpack_from("<I", data, 0x20)
        shentsize, shnum = struct.unpack_from("<HH", data, 0x2E)

    sections = []
    for i in range(shnum):
        base = shoff + i * shentsize
        if is64:
            _, stype, _, _, offset, size, link, _, _, entsize = struct.unpack_from("<IIQQQQIIQQ", data, base)
        else:
            _, stype, _, _, offset, size, link, _, _, entsize = struct.unpack_from("<IIIIIIIIII", data, base)
        sections.append((stype, offset, size, link, entsize))

    dynsym = next((sec for sec in sections if sec[0] == 11), None)  # SHT_DYNSYM
    versym = next((sec for sec in sections if sec[0] == 0x6FFFFFFF), None)  # SHT_GNU_versym
    if not dynsym:
        fail(path + " has no dynamic symbols")
    _, offset, size, link, entsize = dynsym
    strtab = sections[link][1]

    exported, imported = set(), set()
    for i in range(1, size // entsize):
        base = offset + i * entsize
        if is64:
            name_off, info, _, shndx = struct.unpack_from("<IBBH", data, base)
        else:
            name_off, _, _, info, _, shndx = struct.unpack_from("<IIIBBH", data, base)
        end = data.index(b"\0", strtab + name_off)
        name = data[strtab + name_off:end].decode()
        bind = info >> 4
        if not name:
            continue
        if shndx != 0:
            exported.add(name)
        elif bind == 1:  # global undefined: system libraries version theirs, the game doesn't
            version = struct.unpack_from("<H", data, versym[1] + i * 2)[0] if versym else 0
            if version <= 1:
                imported.add(name)
    return (2 if is64 else 1), exported, imported


def check_imports(lib, gtasa, abi):
    lib_class, _, imports = elf_dynamic_symbols(lib)
    game_class, exports, _ = elf_dynamic_symbols(gtasa)
    if lib_class != ELF_CLASS[abi] or game_class != ELF_CLASS[abi]:
        fail("%s is %d-bit but the game's %s library is %d-bit; build libSAMP.so with ABI=%s"
             % (lib, 32 * lib_class, abi, 32 * game_class, abi))
    # liblog's NDK stubs are unversioned too
    missing = sorted(name for name in imports - exports if not name.startswith("__android_log_"))
    for name in missing:
        demangled = subprocess.run(["c++filt", name], stdout=subprocess.PIPE).stdout.decode().strip() if shutil.which("c++filt") else name
        print("  missing in game: " + demangled)
    return missing


def patch_defaults(lib_path, values):
    data = bytearray(open(lib_path, "rb").read())
    offset = data.find(DEFAULTS_MAGIC)
    if offset < 0:
        fail("libSAMP.so has no defaults block; rebuild it from this checkout")
    offset += len(DEFAULTS_MAGIC)
    for field, size in DEFAULTS_FIELDS:
        value = values.get(field)
        if value is not None:
            encoded = value.encode()
            if len(encoded) >= size:
                fail("%s is too long (max %d characters)" % (field, size - 1))
            data[offset:offset + size] = encoded + b"\0" * (size - len(encoded))
        offset += size
    open(lib_path, "wb").write(data)


def patch_smali(decoded):
    patched = []
    for directory, _, files in os.walk(decoded):
        if not os.path.basename(directory).startswith("smali") and "/smali" not in directory.replace("\\", "/"):
            continue
        for file in files:
            if not file.endswith(".smali"):
                continue
            path = os.path.join(directory, file)
            text = open(path, encoding="utf-8").read()
            if '"GTASA"' not in text:
                continue
            if '"SAMP"' in text:
                patched.append(path)
                continue

            def add_samp(match):
                indent, reg = match.group("indent"), match.group("reg")
                return (match.group(0)
                        + '\n%sconst-string %s, "SAMP"\n\n' % (indent, reg)
                        + "%sinvoke-static {%s}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V\n" % (indent, reg))

            new_text, count = LOAD_GTASA.subn(add_samp, text)
            if count:
                open(path, "w", encoding="utf-8").write(new_text)
                patched.append(path)
    if not patched:
        fail('no System.loadLibrary("GTASA") call found in the APK code; is this a GTA: San Andreas APK?')
    for path in patched:
        print("patched " + os.path.relpath(path, decoded))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apk", required=True, help="your GTA: San Andreas APK")
    parser.add_argument("--out", default="GTA-SAMP.apk", help="output APK (default: GTA-SAMP.apk)")
    parser.add_argument("--lib", help="libSAMP.so to add (default: out/<abi>/libSAMP.so for each ABI the game has)")
    parser.add_argument("--host", help="server address baked into the client")
    parser.add_argument("--port", help="server port baked into the client")
    parser.add_argument("--name", help="default player name (Firstname_Lastname)")
    parser.add_argument("--keystore", help="keystore to sign with (default: a generated debug keystore)")
    parser.add_argument("--keystore-pass", default="android", help="keystore password (default: android)")
    parser.add_argument("--key-alias", default="samp", help="key alias (default: samp)")
    parser.add_argument("--apktool", help="path to the apktool launcher")
    parser.add_argument("--apktool-jar", help="path to apktool.jar (run with java -jar)")
    parser.add_argument("--build-tools", help="Android SDK build-tools directory with zipalign and apksigner")
    parser.add_argument("--force", action="store_true", help="continue even if libGTASA.so is a different build")
    args = parser.parse_args()

    if not os.path.exists(args.apk):
        fail("APK not found: " + args.apk)
    if args.port and not args.port.isdigit():
        fail("--port must be a number")

    apktool = apktool_command(args)
    zipalign = find_tool("zipalign", None, build_tools_dirs(args))
    apksigner = find_tool("apksigner", None, build_tools_dirs(args))

    work = tempfile.mkdtemp(prefix="gta-samp-")
    decoded = os.path.join(work, "decoded")
    try:
        # Code only: resources stay byte-for-byte as they are
        run(apktool + ["d", "--no-res", "-f", "-o", decoded, args.apk], quiet=True)

        abis = [abi for abi in ABIS if os.path.exists(os.path.join(decoded, "lib", abi, "libGTASA.so"))]
        if not abis:
            fail("the APK has no lib/<abi>/libGTASA.so. If you copied base.apk from a Play Store install, "
                 "the game library is in a split APK (split_config.*.apk), which isn't supported yet.")
        if args.lib and len(abis) > 1:
            fail("the game has several ABIs (%s); drop --lib to use out/<abi>/libSAMP.so for each" % ", ".join(abis))

        for abi in abis:
            gtasa = os.path.join(decoded, "lib", abi, "libGTASA.so")
            source = args.lib or os.path.join(ROOT, "out", abi, "libSAMP.so")
            if not os.path.exists(source):
                fail("%s not found. Build it with ABI=%s ./build.sh" % (source, abi))

            digest = sha256(gtasa)
            build = KNOWN_GAME_BUILDS[abi].get(digest)
            print("%s: game library %s (%s)" % (abi, digest[:16], build or "unknown build"))
            missing = check_imports(source, gtasa, abi)
            if missing:
                fail("the game's libGTASA.so lacks %d function(s) the client uses, so it would not even start. "
                     "This game version needs porting work." % len(missing))
            if not build:
                message = ("the client hasn't been verified against this game build: it links, but engine "
                           "layouts may differ and it can crash.")
                if not args.force:
                    fail(message + " Use --force to build a test APK anyway.")
                print("warning: " + message)

            lib = os.path.join(decoded, "lib", abi, "libSAMP.so")
            shutil.copyfile(source, lib)
            patch_defaults(lib, {"host": args.host, "port": args.port, "name": args.name})

        patch_smali(decoded)

        unsigned = os.path.join(work, "unsigned.apk")
        aligned = os.path.join(work, "aligned.apk")
        run(apktool + ["b", "-o", unsigned, decoded], quiet=True)
        run([zipalign, "-f", "-p", "4", unsigned, aligned])

        keystore = args.keystore
        if not keystore:
            keystore = os.path.join(ROOT, "samp-debug.keystore")
            if not os.path.exists(keystore):
                run(["keytool", "-genkeypair", "-keystore", keystore, "-storepass", args.keystore_pass,
                     "-keypass", args.keystore_pass, "-alias", args.key_alias, "-keyalg", "RSA", "-keysize", "2048",
                     "-validity", "10000", "-dname", "CN=GTA SAMP Android"], quiet=True)
        run([apksigner, "sign", "--ks", keystore, "--ks-pass", "pass:" + args.keystore_pass,
             "--ks-key-alias", args.key_alias, "--out", args.out, aligned])
        run([apksigner, "verify", args.out])
    finally:
        shutil.rmtree(work, ignore_errors=True)

    print("\nDone: " + os.path.abspath(args.out))
    print("Uninstall the original game first: the new APK has a different signature.")


if __name__ == "__main__":
    main()
