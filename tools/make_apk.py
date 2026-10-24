#!/usr/bin/env python3
"""Turns your own GTA: San Andreas APK into a multiplayer APK.

It adds libSAMP.so next to the game library (libGTASA.so, or libGame.so in
2.11), makes the game load it right after that library, optionally bakes in a
server address, then rebuilds and signs the APK. The game itself is not part of this repository and is not
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
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ABIS = ("arm64-v8a", "armeabi-v7a")
ELF_CLASS = {"armeabi-v7a": 1, "arm64-v8a": 2}

# Game builds the client has been reverse engineered against, by ABI
KNOWN_GAME_BUILDS = {
    "armeabi-v7a": {"59e7198de1916d5f7d22037233f385983099fd53cfab07c707ca25b9d7a834d7": "early 32-bit build (libs/libGTASA.so)"},
    "arm64-v8a": {"4c6a7445e30b27afdda781302e4db9bac89c28fc1181b68b1eef16f84d6a282e": "2.11.311 (Google Play)"},
}

# The engine library: libGTASA.so up to 2.10, libGame.so from 2.11
GAME_LIBS = ("libGTASA.so", "libGame.so")

# Matches the defaults block in src/CNetGame.cpp
DEFAULTS_MAGIC = b"SAMP_DEFAULTS_1\0"
DEFAULTS_FIELDS = [("host", 64), ("port", 8), ("name", 25)]

LOAD_GAME = re.compile(
    r'^(?P<indent>\s*)const-string(?:/jumbo)? (?P<reg>[vp]\d+), "(?:GTASA|Game)"\s*\n'
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
            if '"GTASA"' not in text and '"Game"' not in text:
                continue
            if '"SAMP"' in text:
                patched.append(path)
                continue

            def add_samp(match):
                indent, reg = match.group("indent"), match.group("reg")
                return (match.group(0)
                        + '\n%sconst-string %s, "SAMP"\n\n' % (indent, reg)
                        + "%sinvoke-static {%s}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V\n" % (indent, reg))

            new_text, count = LOAD_GAME.subn(add_samp, text)
            if count:
                open(path, "w", encoding="utf-8").write(new_text)
                patched.append(path)
    if not patched:
        fail('no System.loadLibrary("GTASA") or ("Game") call found in the APK code; is this a GTA: San Andreas APK?')
    for path in patched:
        print("patched " + os.path.relpath(path, decoded))


BUNDLE_EXTENSIONS = (".apks", ".xapk", ".apkm")
SIGNATURE_FILE = re.compile(r"^META-INF/([^/]+\.(SF|RSA|DSA|EC)|MANIFEST\.MF)$")


def unpack_inputs(args, work):
    """Returns (base apk, split apks) from --apk/--split or an exported bundle."""
    if args.apk.lower().endswith(BUNDLE_EXTENSIONS):
        folder = os.path.join(work, "bundle")
        with zipfile.ZipFile(args.apk) as bundle:
            names = [n for n in bundle.namelist() if n.lower().endswith(".apk") and "/" not in n.strip("/")]
            bundle.extractall(folder, names)
        apks = [os.path.join(folder, n) for n in names]
    else:
        apks = [args.apk] + (args.split or [])
    for apk in apks:
        if not os.path.exists(apk):
            fail("APK not found: " + apk)

    bases = []
    for apk in apks:
        with zipfile.ZipFile(apk) as z:
            if "classes.dex" in z.namelist():
                bases.append(apk)
    if len(bases) != 1:
        fail("expected exactly one base APK with the game code, found %d" % len(bases))
    return bases[0], [apk for apk in apks if apk != bases[0]]


def game_libraries(apk):
    """(ABI, engine library name) pairs found inside this APK."""
    with zipfile.ZipFile(apk) as z:
        names = set(z.namelist())
    return [(abi, lib) for abi in ABIS for lib in GAME_LIBS if "lib/%s/%s" % (abi, lib) in names]


def prepare_client_lib(args, abi, gtasa, out_path):
    """Checks the game library and writes the configured libSAMP.so for this ABI."""
    source = args.lib or os.path.join(ROOT, "out", abi, "libSAMP.so")
    if not os.path.exists(source):
        fail("%s not found. Build it with ABI=%s ./build.sh" % (source, abi))

    digest = sha256(gtasa)
    build = KNOWN_GAME_BUILDS[abi].get(digest)
    print("%s: game library %s (%s)" % (abi, digest[:16], build or "unknown build"))
    missing = check_imports(source, gtasa, abi)
    if missing:
        fail("the game's engine library lacks %d function(s) the client uses, so it would not even start. "
             "This game version needs porting work." % len(missing))
    if not build:
        message = ("the client hasn't been verified against this game build: it links, but engine "
                   "layouts may differ and it can crash.")
        if not args.force:
            fail(message + " Use --force to build a test APK anyway.")
        print("warning: " + message)

    shutil.copyfile(source, out_path)
    patch_defaults(out_path, {"host": args.host, "port": args.port, "name": args.name})


def rewrite_split(split, out, extra_libs):
    """Copies a split without its old signature, adding libraries stored uncompressed."""
    with zipfile.ZipFile(split) as src, zipfile.ZipFile(out, "w", allowZip64=True) as dst:
        for info in src.infolist():
            if SIGNATURE_FILE.match(info.filename):
                continue
            # Streamed, so the 1.4 GB data split of 2.11 doesn't have to fit in memory
            with src.open(info) as fin, dst.open(info, "w", force_zip64=info.file_size > 0x7FFFFFFF) as fout:
                shutil.copyfileobj(fin, fout, 1 << 20)
        for name, path in extra_libs:
            # Modern installs map libraries straight from the APK, so they must not be compressed
            dst.write(path, name, compress_type=zipfile.ZIP_STORED)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apk", required=True,
                        help="your GTA: San Andreas APK, base.apk, or an exported bundle (.apks/.xapk/.apkm)")
    parser.add_argument("--split", action="append", help="a split APK of the same install (repeat for each)")
    parser.add_argument("--out", help="output file (default: GTA-SAMP.apk, or GTA-SAMP.apks for split installs)")
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
    parser.add_argument("--force", action="store_true", help="continue even if the game library is a different build")
    args = parser.parse_args()

    if args.port and not args.port.isdigit():
        fail("--port must be a number")

    apktool = apktool_command(args)
    zipalign = find_tool("zipalign", None, build_tools_dirs(args))
    apksigner = find_tool("apksigner", None, build_tools_dirs(args))

    work = tempfile.mkdtemp(prefix="gta-samp-")
    try:
        base, splits = unpack_inputs(args, work)
        out = args.out or ("GTA-SAMP.apks" if splits else "GTA-SAMP.apk")

        holders = [(apk, abi, name) for apk in [base] + splits for abi, name in game_libraries(apk)]
        if not holders:
            fail("no lib/<abi>/libGTASA.so or libGame.so in the APK%s. Pass every split of the install with --split, "
                 "or export the whole app as a bundle." % ("s" if splits else ""))
        if args.lib and len(holders) > 1:
            fail("the game has several ABIs; drop --lib to use out/<abi>/libSAMP.so for each")

        # Client library per ABI, next to the game library it was checked against
        client_libs = {}
        for apk, abi, name in holders:
            gtasa = os.path.join(work, "game-" + abi, name)
            os.makedirs(os.path.dirname(gtasa))
            with zipfile.ZipFile(apk) as z, open(gtasa, "wb") as f:
                f.write(z.read("lib/%s/%s" % (abi, name)))
            client_libs[(apk, abi)] = os.path.join(os.path.dirname(gtasa), "libSAMP.so")
            prepare_client_lib(args, abi, gtasa, client_libs[(apk, abi)])

        keystore = args.keystore
        if not keystore:
            keystore = os.path.join(ROOT, "samp-debug.keystore")
            if not os.path.exists(keystore):
                run(["keytool", "-genkeypair", "-keystore", keystore, "-storepass", args.keystore_pass,
                     "-keypass", args.keystore_pass, "-alias", args.key_alias, "-keyalg", "RSA", "-keysize", "2048",
                     "-validity", "10000", "-dname", "CN=GTA SAMP Android"], quiet=True)

        def finish(unsigned, signed):
            aligned = unsigned + ".aligned"
            # -p page-aligns uncompressed .so files so they can be mapped in place
            run([zipalign, "-f", "-p", "4", unsigned, aligned])
            os.remove(unsigned)
            run([apksigner, "sign", "--ks", keystore, "--ks-pass", "pass:" + args.keystore_pass,
                 "--ks-key-alias", args.key_alias, "--out", signed, aligned])
            os.remove(aligned)
            run([apksigner, "verify", signed])

        # Base: code only decode, so resources stay byte-for-byte as they are
        decoded = os.path.join(work, "decoded")
        run(apktool + ["d", "--no-res", "-f", "-o", decoded, base], quiet=True)
        for (apk, abi), lib in client_libs.items():
            if apk == base:
                shutil.copyfile(lib, os.path.join(decoded, "lib", abi, "libSAMP.so"))
        patch_smali(decoded)
        base_out = os.path.join(work, "signed", "base.apk")
        os.makedirs(os.path.dirname(base_out))
        run(apktool + ["b", "-o", os.path.join(work, "base-unsigned.apk"), decoded], quiet=True)
        finish(os.path.join(work, "base-unsigned.apk"), base_out)
        shutil.rmtree(decoded)

        if not splits:
            shutil.copyfile(base_out, out)
        else:
            # Splits: every one is re-signed with the same key, the library holders also get libSAMP.so.
            # Each goes into the bundle as soon as it's signed and temporary copies are deleted on the
            # way, so a phone only needs a few times the size of the biggest split free (2.11: 1.4 GB).
            with zipfile.ZipFile(out, "w", allowZip64=True) as bundle:
                bundle.write(base_out, "base.apk", compress_type=zipfile.ZIP_STORED)
                os.remove(base_out)
                for split in splits:
                    extra = [("lib/%s/libSAMP.so" % abi, lib) for (apk, abi), lib in client_libs.items() if apk == split]
                    unsigned = os.path.join(work, "split-" + os.path.basename(split))
                    rewrite_split(split, unsigned, extra)
                    if split.startswith(work):
                        os.remove(split)
                    split_out = os.path.join(work, "signed", os.path.basename(split))
                    finish(unsigned, split_out)
                    bundle.write(split_out, os.path.basename(split), compress_type=zipfile.ZIP_STORED)
                    os.remove(split_out)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    print("\nDone: " + os.path.abspath(out))
    print("Uninstall the original game first: the new APK has a different signature.")
    if splits:
        print("This is a split install: open the .apks with SAI (Split APKs Installer) to install it.")


if __name__ == "__main__":
    main()
