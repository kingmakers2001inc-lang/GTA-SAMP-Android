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
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ABI = "armeabi-v7a"

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
    parser.add_argument("--lib", default=os.path.join(ROOT, "libSAMP.so"), help="libSAMP.so to add (default: ./libSAMP.so)")
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
    if not os.path.exists(args.lib):
        fail("%s not found. Build it first with ./build.sh or build.bat" % args.lib)
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

        gtasa = os.path.join(decoded, "lib", ABI, "libGTASA.so")
        if not os.path.exists(gtasa):
            fail("the APK has no lib/%s/libGTASA.so" % ABI)
        expected = sha256(os.path.join(ROOT, "libs", "libGTASA.so"))
        if sha256(gtasa) != expected:
            message = ("this APK's libGTASA.so is a different build from libs/libGTASA.so, which the "
                       "client was built and reverse engineered against. It will probably crash.")
            if not args.force:
                fail(message + " Use the matching game version, or --force to try anyway.")
            print("warning: " + message)

        lib = os.path.join(decoded, "lib", ABI, "libSAMP.so")
        shutil.copyfile(args.lib, lib)
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
