#!/usr/bin/env bash
# End-to-end netcode test: the client's real networking code (CNetGame, RPC, RakNet,
# chat/dialog/keyboard UI) against open.mp's own server RakNet and packet serializers.
# Runs on a Linux host, no game or phone needed. Usage: tests/netcode/run.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORK="${WORK:-${TMPDIR:-/tmp}/samp-netcode-test}"
OMP_COMMIT=72bf89ce4c8164f7f7b8271ffc7323bc45ea005f
mkdir -p "$WORK"

# --- open.mp sources (only the parts the legacy network needs) -----------------
OMP="$WORK/open.mp"
if [ ! -d "$OMP/.git" ]; then
	git init -q "$OMP"
	git -C "$OMP" remote add origin https://github.com/openmultiplayer/open.mp
	git -C "$OMP" fetch -q --depth 1 origin "$OMP_COMMIT"
	git -C "$OMP" checkout -q FETCH_HEAD
	git -C "$OMP" submodule update -q --init --depth 1 lib/RakNet SDK Shared/Network
	git -C "$OMP/SDK" submodule update -q --init --depth 1
fi

# Test-only: stub the few open.mp core calls RakNet makes (logging, an encryption
# config flag that defaults to off for 0.3.7 clients), so no full server core is needed
python3 - "$OMP/lib/RakNet" <<'PY'
import glob, re, sys, os
os.chdir(sys.argv[1])
p = 'SAMPRakNet.hpp'
s = open(p).read()
if 'TestLog' not in s:
	s = s.replace('static bool* isEnabled = core_->getConfig().getBool("network.use_omp_encryption");\n\t\treturn isEnabled ? *isEnabled : false;', 'return false;')
	s = s.replace('#include <shared_mutex>', '#include <shared_mutex>\n#include <cstdio>\n#include <cstdarg>\ninline void TestLog(const char* f, ...) { va_list a; va_start(a, f); vprintf(f, a); va_end(a); printf("\\n"); }')
	open(p, 'w').write(s)
for p in glob.glob('*.cpp') + glob.glob('Source/*.cpp'):
	s = open(p).read()
	n = re.sub(r'(SAMPRakNet::GetCore\(\)|core_)->logLn\(\s*LogLevel::\w+,', 'TestLog(', s)
	n = re.sub(r'(SAMPRakNet::GetCore\(\)|core_)->(logLn|printLn)\(', 'TestLog(', n)
	if n != s:
		open(p, 'w').write(n)
PY

# --- server ----------------------------------------------------------------------
L="$OMP/SDK/lib"
SRV_FLAGS=(-std=c++17 -O1 -w -D__stdcall= -DRAKNET_LEGACY -DPACKETS_PER_TICK=3 -DGLM_FORCE_QUAT_DATA_WXYZ -DNOMINMAX
	-Dnssv_CONFIG_SELECT_STRING_VIEW=nssv_STRING_VIEW_NONSTD -Dspan_CONFIG_SELECT_SPAN=span_SPAN_NONSTD -DTTMATH_NOASM
	"-DGLM_COUNTOF(x)=(sizeof(x)/sizeof((x)[0]))"
	-I"$OMP" -I"$OMP/SDK/include" -I"$OMP/lib/RakNet" -I"$OMP/lib/RakNet/Include" -I"$OMP/lib/RakNet/Include/raknet"
	-I"$L/glm" -I"$L/robin-hood-hashing/src/include" -I"$L/span-lite/include" -I"$L/string-view-lite/include"
	-I"$OMP/Shared" -I"$OMP/Shared/Network" -I"$WORK/inc")
mkdir -p "$WORK/inc/ttmath" "$WORK/srv" "$WORK/cli"
cp "$ROOT"/ttmath/*.h "$WORK/inc/ttmath/"

SRV_SRCS=$(sed -n '/set(RAKNET_SOURCES/,/)/p' "$OMP/lib/RakNet/CMakeLists.txt" | grep '\.cpp' | sed "s|^\s*|$OMP/lib/RakNet/|")
for f in $SRV_SRCS "$OMP"/Shared/Network/bitstream.cpp "$OMP"/Shared/Network/Encoding/*.cpp; do
	o="$WORK/srv/$(basename "$f").o"
	[ -f "$o" ] || g++ "${SRV_FLAGS[@]}" -c "$f" -o "$o"
done
echo "building test server"
g++ "${SRV_FLAGS[@]}" "$HERE/omp_server.cpp" "$WORK"/srv/*.o -lpthread -o "$WORK/omp_server"

# --- client (always rebuilt from this checkout) ----------------------------------
cd "$ROOT"
CLI_FLAGS=(-std=c++11 -O1 -g -w -fpermissive -Wno-narrowing -DHOST_ENDIAN_IS_LITTLE -DLITTLE_ENDIAN -DRAKSAMP_CLIENT
	-DNETCODE_OPENCONNLULZ=6969 -DTTMATH_NOASM -Isrc -Irw_include -Isa_include -Iraknet -Ittmath)
RNFILES=$(sed -n '/^RNFILES/,/samp_netencr/p' Makefile | tr -d '\\' | sed 's/RNFILES =//' | tr ' \t' '\n\n' | grep '\.cpp$' | sed 's|^|raknet/|')
rm -f "$WORK"/cli/*.o
echo "building client harness"
for f in $RNFILES src/CNetGame.cpp src/RPC.cpp src/CPlayerPool.cpp src/CChat.cpp src/CDialog.cpp src/CKeyboard.cpp; do
	g++ "${CLI_FLAGS[@]}" -c "$f" -o "$WORK/cli/$(echo "$f" | tr / _).o"
done
g++ "${CLI_FLAGS[@]}" "$HERE/client_harness.cpp" "$WORK"/cli/*.o -lpthread -o "$WORK/client_harness"

# --- run ---------------------------------------------------------------------------
"$WORK/omp_server" > "$WORK/server.log" 2>&1 &
SERVER_PID=$!
sleep 1
timeout 20 "$WORK/client_harness" > "$WORK/client.log" 2>&1 || true
wait $SERVER_PID && RESULT=0 || RESULT=1

grep -v "Packet received" "$WORK/client.log"
cat "$WORK/server.log"
exit $RESULT
