#!/usr/bin/env bash
# Builds libSAMP.so with a current Android NDK (Linux/macOS).
# Usage: NDK=/path/to/android-ndk [ABI=armeabi-v7a|arm64-v8a] ./build.sh
# Output: out/<ABI>/libSAMP.so
set -euo pipefail

: "${NDK:?Set NDK to your Android NDK directory}"
ABI="${ABI:-armeabi-v7a}"
HOST_TAG=$(ls "$NDK/toolchains/llvm/prebuilt" | head -n1)
TOOLS="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"
STRIP="$TOOLS/llvm-strip"

case "$ABI" in
	armeabi-v7a)
		CXX="$TOOLS/armv7a-linux-androideabi21-clang++"
		CC="$TOOLS/armv7a-linux-androideabi21-clang"
		ARCH_FLAGS=(-mthumb)
		HOOKFILES=$(sed -n 's/^HOOKFILES = //p' Makefile | tr ' ' '\n' | sed 's|^|inlinehook/|')
		;;
	arm64-v8a)
		CXX="$TOOLS/aarch64-linux-android21-clang++"
		CC="$TOOLS/aarch64-linux-android21-clang"
		ARCH_FLAGS=()
		HOOKFILES=inlinehook/arm64/And64InlineHook.cpp
		;;
	*)
		echo "Unknown ABI $ABI (use armeabi-v7a or arm64-v8a)" >&2
		exit 1
		;;
esac

cd "$(dirname "$0")"
OBJDIR="obj-ndk/$ABI"
OUTDIR="out/$ABI"
mkdir -p "$OBJDIR" "$OUTDIR"

CXXFLAGS=(-std=c++11 -fPIC -O2 -g -w -Wno-c++11-narrowing "${ARCH_FLAGS[@]}"
	-ffunction-sections -fdata-sections -frtti -fexceptions
	-DHOST_ENDIAN_IS_LITTLE -DLITTLE_ENDIAN -DRAKSAMP_CLIENT -DNETCODE_OPENCONNLULZ=6969 -DNDEBUG
	-Irw_include -Isa_include -Iraknet -Ittmath -Iinlinehook)

# Same sources as the Makefile
SRCFILES=$(sed -n 's/^SRCFILES +\?= //p' Makefile | tr ' ' '\n' | grep '\.cpp$' | sed 's|^|src/|')
RNFILES=$(sed -n '/^RNFILES/,/samp_netencr/p' Makefile | tr -d '\\' | sed 's/RNFILES =//' | tr ' \t' '\n\n' | grep '\.cpp$' | sed 's|^|raknet/|')

OBJS=()
for f in $SRCFILES $RNFILES $HOOKFILES; do
	o="$OBJDIR/${f//\//_}.o"
	if [ ! -f "$o" ] || [ "$f" -nt "$o" ] || [ -n "$(find src sa_include raknet inlinehook -name '*.h*' -newer "$o" -print -quit)" ]; then
		echo "compile $f"
		case "$f" in
			*.c) "$CC" -fPIC -O2 -g -w "${ARCH_FLAGS[@]}" -DINLINEHOOK_NO_FREEZE -Iinlinehook -c "$f" -o "$o" ;;
			*) "$CXX" "${CXXFLAGS[@]}" -c "$f" -o "$o" ;;
		esac
	fi
	OBJS+=("$o")
done

# libs/<ABI>/libGTASA.so if you have the game library for this ABI, else the 32-bit one in
# libs/ for armeabi-v7a. arm64 builds without one link against a generated stand-in.
GAME_LIBDIR=libs
[ -f "libs/$ABI/libGTASA.so" ] && GAME_LIBDIR="libs/$ABI"
if [ "$ABI" != armeabi-v7a ] && [ "$GAME_LIBDIR" = libs ]; then
	echo "collecting engine imports"
	"$CXX" -shared -Wl,-z,defs -Wl,--no-demangle -Wl,--error-limit=0 "${OBJS[@]}" -static-libstdc++ -llog \
		-o "$OBJDIR/probe.so" 2> "$OBJDIR/probe.log" || true
	sed -n 's/.*undefined symbol: \([^ ]*\).*/\1/p' "$OBJDIR/probe.log" | sort -u > "$OBJDIR/imports.raw"
	# Data symbols are the ones the 32-bit game library defines as objects
	"$TOOLS/llvm-nm" -D --defined-only libs/libGTASA.so | awk '$2 ~ /^[BDRbdr]$/ {print $3}' | sort -u > "$OBJDIR/objects.txt"
	awk 'NR == FNR {obj[$1] = 1; next} {print $1 (($1 in obj) ? " object" : "")}' "$OBJDIR/objects.txt" "$OBJDIR/imports.raw" \
		> "$OBJDIR/engine_imports.txt"
	mkdir -p "$OBJDIR/stub"
	python3 tools/engine_stub.py stub --symbols "$OBJDIR/engine_imports.txt" --arch arm64 --cc "$CC" \
		--out "$OBJDIR/stub/libGTASA.so" > /dev/null
	GAME_LIBDIR="$OBJDIR/stub"
	echo "linking against a stand-in libGTASA.so ($(wc -l < "$OBJDIR/engine_imports.txt") imports in $OBJDIR/engine_imports.txt)"
fi

echo "linking $OUTDIR/libSAMP.so"
"$CXX" -shared -static-libstdc++ -Wl,--gc-sections -Wl,-z,defs -L"$GAME_LIBDIR" "${OBJS[@]}" -llog -lGTASA -o "$OUTDIR/libSAMP.so"
"$STRIP" --strip-all "$OUTDIR/libSAMP.so"
echo "Build done: $OUTDIR/libSAMP.so"
