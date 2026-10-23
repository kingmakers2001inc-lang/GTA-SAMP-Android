#!/usr/bin/env bash
# Builds libSAMP.so with a current Android NDK (Linux/macOS).
# Usage: NDK=/path/to/android-ndk ./build.sh
set -euo pipefail

: "${NDK:?Set NDK to your Android NDK directory}"
HOST_TAG=$(ls "$NDK/toolchains/llvm/prebuilt" | head -n1)
TOOLS="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"
CXX="$TOOLS/armv7a-linux-androideabi21-clang++"
CC="$TOOLS/armv7a-linux-androideabi21-clang"
STRIP="$TOOLS/llvm-strip"

cd "$(dirname "$0")"
OBJDIR=obj-ndk
mkdir -p "$OBJDIR"

CXXFLAGS=(-std=c++11 -fPIC -mthumb -O2 -g -w -Wno-c++11-narrowing
	-ffunction-sections -fdata-sections -frtti -fexceptions
	-DHOST_ENDIAN_IS_LITTLE -DLITTLE_ENDIAN -DRAKSAMP_CLIENT -DNETCODE_OPENCONNLULZ=6969 -DNDEBUG
	-Irw_include -Isa_include -Iraknet -Ittmath -Iinlinehook)

# Same sources as the Makefile
SRCFILES=$(sed -n 's/^SRCFILES +\?= //p' Makefile | tr ' ' '\n' | grep '\.cpp$' | sed 's|^|src/|')
RNFILES=$(sed -n '/^RNFILES/,/samp_netencr/p' Makefile | tr -d '\\' | sed 's/RNFILES =//' | tr ' \t' '\n\n' | grep '\.cpp$' | sed 's|^|raknet/|')

OBJS=()
for f in $SRCFILES $RNFILES; do
	o="$OBJDIR/${f//\//_}.o"
	if [ ! -f "$o" ] || [ "$f" -nt "$o" ] || [ -n "$(find src sa_include raknet -name '*.h' -newer "$o" -print -quit)" ]; then
		echo "compile $f"
		"$CXX" "${CXXFLAGS[@]}" -c "$f" -o "$o"
	fi
	OBJS+=("$o")
done

HOOKFILES=$(sed -n 's/^HOOKFILES = //p' Makefile | tr ' ' '\n' | sed 's|^|inlinehook/|')
for f in $HOOKFILES; do
	o="$OBJDIR/${f//\//_}.o"
	if [ ! -f "$o" ] || [ "$f" -nt "$o" ]; then
		echo "compile $f"
		"$CC" -fPIC -mthumb -O2 -g -w -DINLINEHOOK_NO_FREEZE -Iinlinehook -c "$f" -o "$o"
	fi
	OBJS+=("$o")
done

echo "linking libSAMP.so"
"$CXX" -shared -static-libstdc++ -Wl,--gc-sections -Wl,-z,defs -Llibs "${OBJS[@]}" -llog -lGTASA -o libSAMP.so
"$STRIP" --strip-all libSAMP.so
echo "Build done: libSAMP.so"
