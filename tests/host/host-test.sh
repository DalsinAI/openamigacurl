#!/bin/sh
# openamigacurl host test: curl with patches/ applied and OpenTLS's host
# build, on Linux, against a local HTTPS server. It checks the OpenTLS
# backend's own code (lib/vtls/opentls.c); the Amiga build is build.sh's.
# MIT, Copyright (c) 2026 AmigaChrome Team.
#
#   OPENTLS_SRC  an openamigatls checkout (default ../openamigatls)
#   TARBALLS     folder holding the upstream tarballs listed in SOURCES
#                (default ./tarballs); the script checks their SHA-256
#   SANITIZE     1: build with AddressSanitizer and UBSan
#   JOBS         parallel jobs (default 4)
#
# usage: tests/host/host-test.sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OT=$(CDPATH= cd -- "${OPENTLS_SRC:-$HERE/../openamigatls}" && pwd)
TARBALLS=${TARBALLS:-"$HERE/tarballs"}
JOBS=${JOBS:-4}
W="$HERE/work/host"
SAN=""
[ "${SANITIZE:-0}" = 1 ] && SAN="-fsanitize=address,undefined -fno-omit-frame-pointer"

t="$TARBALLS/curl-8.22.0.tar.xz"
[ -f "$t" ] || { echo "missing $t (see SOURCES)"; exit 2; }
echo "f7ef3ae8a22e521f289803fe93543eb64c329b58aa73a9e224dfd915a2a5f4f7  $t" | sha256sum -c - >/dev/null \
    || { echo "SHA-256 mismatch: $t"; exit 2; }
rm -rf "$W"; mkdir -p "$W"
tar xf "$t" -C "$W"
for p in "$HERE"/patches/*.patch; do patch -s -d "$W/curl-8.22.0" -p1 < "$p"; done

cmake -S "$OT" -B "$W/opentls" -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="$SAN" >/dev/null
cmake --build "$W/opentls" -j"$JOBS" --target opentls bearssl opencrypto >/dev/null
cmake -S "$W/curl-8.22.0" -B "$W/curl" -DCMAKE_BUILD_TYPE=Debug -DCMAKE_C_FLAGS="$SAN" \
    -DCMAKE_EXE_LINKER_FLAGS="$SAN" -DPICKY_COMPILER=ON \
    -DCURL_USE_OPENSSL=OFF -DCURL_USE_OPENTLS=ON \
    -DOPENTLS_INCLUDE_DIR="$OT/host/include;$OT/include" \
    -DOPENTLS_LIBRARY="$W/opentls/libopentls.a;$W/opentls/libbearssl.a;$W/opentls/libopencrypto.a" \
    -DCURL_CA_BUNDLE=none -DCURL_CA_PATH=none -DBUILD_SHARED_LIBS=OFF \
    -DCURL_USE_LIBPSL=OFF -DUSE_NGHTTP2=OFF -DUSE_LIBIDN2=OFF -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF \
    -DCURL_USE_LIBSSH2=OFF -DENABLE_CURL_MANUAL=OFF -DBUILD_LIBCURL_DOCS=OFF -DBUILD_MISC_DOCS=OFF >/dev/null
cmake --build "$W/curl" -j"$JOBS" --target curl > "$W/build.log" 2>&1 || { tail -30 "$W/build.log"; exit 1; }
if grep -E 'opentls\.c.*(warning|error)' "$W/build.log"; then exit 1; fi
CURL="$W/curl/src/curl"
cc -shared -fPIC -O2 -o "$W/eagain.so" "$HERE/tests/host/eagain.c" -ldl
"$CURL" -V | head -1

cd "$W"
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 2 -subj /CN=localhost \
    -addext subjectAltName=DNS:localhost,IP:127.0.0.1 2>/dev/null
cp cert.pem cert2.pem
python3 "$HERE/tests/host/tls_server.py" 18443 cert.pem key.pem & S1=$!
python3 "$HERE/tests/host/tls_server.py" 18444 cert.pem key.pem tls13 & S2=$!
trap 'kill $S1 $S2 2>/dev/null' EXIT INT TERM
sleep 1
head -c 8000000 /dev/urandom > up.bin
WANT="$(sha256sum up.bin | cut -c1-64) 8000000"

FAIL=0
c() { "$CURL" --noproxy '*' -sS --cacert "$W/cert.pem" "$@"; }
check() {   # check NAME EXPECTED ACTUAL
    if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: wanted [$2], got [$3]"; FAIL=1; fi
}
check "POST 8 MB"                "$WANT" "$(c --data-binary @up.bin https://localhost:18443/post)"
check "POST to an IP address"    "$WANT" "$(c --data-binary @up.bin https://127.0.0.1:18443/post)"
check "GET 20 MB"                "200 20000000" "$(c -o /dev/null -w '%{http_code} %{size_download}' https://localhost:18443/20000000)"
check "close without close_notify" "200 1000000" "$(c -o /dev/null -H 'X-Close: 1' -w '%{http_code} %{size_download}' https://localhost:18443/1000000)"
check "keep-alive reuse"         "200 1 200 0" "$(c -o /dev/null -o /dev/null -w '%{http_code} %{num_connects} ' https://localhost:18443/10 https://localhost:18443/20 | sed 's/ $//')"
check "CA file changes"          "200_200_200_200_" "$(c -o /dev/null -w '%{http_code}_' https://localhost:18443/1 --next -o /dev/null -w '%{http_code}_' --cacert cert2.pem https://localhost:18443/2 --next -o /dev/null -w '%{http_code}_' --cacert cert.pem -H 'Connection: close' https://localhost:18443/3 --next -o /dev/null -w '%{http_code}_' -k https://localhost:18443/4)"
r=0; c -o /dev/null --resolve other:18443:127.0.0.1 https://other:18443/1 2>/dev/null || r=$?
check "wrong host name refused"  60 "$r"
r=0; c -o /dev/null -k --resolve other:18443:127.0.0.1 https://other:18443/1 || r=$?
check "wrong host name with -k"  0 "$r"
r=0; c -o /dev/null --cacert /dev/null https://localhost:18443/1 2>/dev/null || r=$?
check "no trusted certificates"  77 "$r"
r=0; c -o /dev/null https://localhost:18444/1 2>/dev/null || r=$?
check "TLS 1.3-only server"      35 "$r"
# Sessions: each line is one curl run, one connection per URL; hs lists
# whether each handshake was full or resumed the session cached for that peer.
hs() { sed -n -e 's/.*handshake done, session resumed.*/resumed/p' \
              -e 's/.*handshake done, full handshake.*/full/p' | tr '\n' ' ' | sed 's/ $//'; }
U=https://localhost:18443
O="--noproxy localhost,127.0.0.1,other --cacert $W/cert.pem -o /dev/null -H Connection:close"
N="--next $O"
r() { x=0; o=$("$CURL" -sS -v $O "$@" 2>&1) || x=$?; echo "$(echo "$o" | hs)$([ $x = 0 ] || echo " exit $x")"; }
check "session: later connections resume"   "full resumed resumed" "$(r $U/1 $N $U/2 $N $U/3)"
check "session: parallel, after the first"  "full resumed resumed resumed" "$(r $U/1 $N -Z $U/2 $U/3 $U/4)"
check "session: not after verify off"       "full full" "$(r $U/1 $N -k $U/2)"
check "session: not after verify on"        "full full resumed" "$(r -k $U/1 $N $U/2 $N $U/3)"
check "session: not with another CA file"   "full full resumed" "$(r $U/1 $N --cacert cert2.pem $U/2 $N $U/3)"
check "session: not with --no-sessionid"    "full full resumed" "$(r $U/1 $N --no-sessionid $U/2 $N $U/3)"
check "session: not for another host"       "full full" "$(r $U/1 $N -k --resolve other:18443:127.0.0.1 https://other:18443/2)"
check "session: a -k session skips no check" "full exit 60" \
    "$(r -k --resolve other:18443:127.0.0.1 https://other:18443/1 $N --resolve other:18443:127.0.0.1 https://other:18443/2)"

for e in 2 3 7; do
    ASAN_LIB=""
    [ -n "$SAN" ] && ASAN_LIB="$(cc -print-file-name=libasan.so):"
    check "POST, 1 in $e socket calls stalls" "$WANT" \
        "$(EAGAIN_EVERY=$e LD_PRELOAD="$ASAN_LIB$W/eagain.so" "$CURL" --noproxy '*' -sS --cacert cert.pem --data-binary @up.bin https://localhost:18443/post)"
    check "GET, 1 in $e socket calls stalls" "200 3000000" \
        "$(EAGAIN_EVERY=$e LD_PRELOAD="$ASAN_LIB$W/eagain.so" "$CURL" --noproxy '*' -sS --cacert cert.pem -o /dev/null -w '%{http_code} %{size_download}' https://localhost:18443/3000000)"
    check "resumed, 1 in $e socket calls stalls" "full resumed" \
        "$(EAGAIN_EVERY=$e LD_PRELOAD="$ASAN_LIB$W/eagain.so" "$CURL" -sS -v $O $U/300000 $N $U/300000 2>&1 | hs)"
done
[ "$FAIL" = 0 ] && echo "all passed"
exit "$FAIL"
