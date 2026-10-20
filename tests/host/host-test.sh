#!/bin/sh
# openamigacurl host test: curl with patches/ applied, OpenTLS's host build
# and nghttp2, on Linux, against local HTTPS servers (HTTP/1.1, and HTTP/2
# through tests/host/h2_server.c). It checks the OpenTLS backend's own code
# (lib/vtls/opentls.c) and HTTP/2 over it; the Amiga build is build.sh's.
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
n="$TARBALLS/nghttp2-1.70.0.tar.xz"
[ -f "$n" ] || { echo "missing $n (see SOURCES)"; exit 2; }
echo "e05cb1388eaca3830aded4ccf20044b6e1ac1a61411dcca11b0437c4285c8bc2  $n" | sha256sum -c - >/dev/null \
    || { echo "SHA-256 mismatch: $n"; exit 2; }
rm -rf "$W"; mkdir -p "$W"
tar xf "$t" -C "$W"
tar xf "$n" -C "$W"
for p in "$HERE"/patches/*.patch; do patch -s -d "$W/curl-8.22.0" -p1 < "$p"; done

cmake -S "$OT" -B "$W/opentls" -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="$SAN" >/dev/null
cmake --build "$W/opentls" -j"$JOBS" --target opentls bearssl opencrypto >/dev/null
# nghttp2: the library only, as in the Amiga build
cmake -S "$W/nghttp2-1.70.0" -B "$W/nghttp2" -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="$SAN" \
    -DENABLE_LIB_ONLY=ON -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_TESTING=OFF -DENABLE_DOC=OFF >/dev/null
cmake --build "$W/nghttp2" -j"$JOBS" >/dev/null
NGI="$W/nghttp2-1.70.0/lib/includes"
NGL="$W/nghttp2/lib/libnghttp2.a"
cmake -S "$W/curl-8.22.0" -B "$W/curl" -DCMAKE_BUILD_TYPE=Debug -DCMAKE_C_FLAGS="$SAN" \
    -DCMAKE_EXE_LINKER_FLAGS="$SAN" -DPICKY_COMPILER=ON \
    -DCURL_USE_OPENSSL=OFF -DCURL_USE_OPENTLS=ON \
    -DOPENTLS_INCLUDE_DIR="$OT/host/include;$OT/include" \
    -DOPENTLS_LIBRARY="$W/opentls/libopentls.a;$W/opentls/libbearssl.a;$W/opentls/libopencrypto.a" \
    -DCURL_CA_BUNDLE=none -DCURL_CA_PATH=none -DBUILD_SHARED_LIBS=OFF \
    -DUSE_NGHTTP2=ON -DNGHTTP2_USE_STATIC_LIBS=ON -DNGHTTP2_INCLUDE_DIR="$NGI" -DNGHTTP2_LIBRARY="$NGL" \
    -DCURL_USE_LIBPSL=OFF -DUSE_LIBIDN2=OFF -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF \
    -DCURL_USE_LIBSSH2=OFF -DENABLE_CURL_MANUAL=OFF -DBUILD_LIBCURL_DOCS=OFF -DBUILD_MISC_DOCS=OFF >/dev/null
cmake --build "$W/curl" -j"$JOBS" --target curl > "$W/build.log" 2>&1 || { tail -30 "$W/build.log"; exit 1; }
if grep -E 'opentls\.c.*(warning|error)' "$W/build.log"; then exit 1; fi
CURL="$W/curl/src/curl"
cc -shared -fPIC -O2 -o "$W/eagain.so" "$HERE/tests/host/eagain.c" -ldl
cc -O2 $SAN -DNGHTTP2_STATICLIB -I"$NGI" -o "$W/h2_server" "$HERE/tests/host/h2_server.c" "$NGL" -lssl -lcrypto -lpthread
"$CURL" -V | head -1
"$CURL" -V | grep -q 'HTTP2' || { echo "curl was built without HTTP/2"; exit 1; }

cd "$W"
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 2 -subj /CN=localhost \
    -addext subjectAltName=DNS:localhost,IP:127.0.0.1 2>/dev/null
cp cert.pem cert2.pem
python3 "$HERE/tests/host/tls_server.py" 18443 cert.pem key.pem & S1=$!
python3 "$HERE/tests/host/tls_server.py" 18444 cert.pem key.pem tls13 & S2=$!
python3 "$HERE/tests/host/tls_server.py" 18445 cert.pem key.pem http11 & S3=$!
"$W/h2_server" 18446 cert.pem key.pem & S4=$!
trap 'kill $S1 $S2 $S3 $S4 2>/dev/null' EXIT INT TERM
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

# HTTP/2: h2_server.c speaks only h2 over TLS 1.2, picked by ALPN.
H=https://localhost:18446
check "h2: curl offers h2 and http/1.1" "ALPN: curl offers h2,http/1.1" \
    "$(c -v -o /dev/null $H/1 2>&1 | grep -o 'ALPN: curl offers .*' | tr -d '\r')"
check "h2: server accepted h2"   "ALPN: server accepted h2" \
    "$(c -v -o /dev/null $H/1 2>&1 | grep -o 'ALPN: server accepted .*' | tr -d '\r')"
check "h2: GET 20 MB"            "2 200 20000000" "$(c -o /dev/null -w '%{http_version} %{http_code} %{size_download}' $H/20000000)"
check "h2: POST 8 MB"            "$WANT" "$(c --data-binary @up.bin $H/post)"
check "h2: by default, no --http2" "2" "$(c -o /dev/null -w '%{http_version}' $H/10)"
# Parallel transfers multiplexed on one connection: x-conn names the
# server's connection, num_connects counts curl's new connections.
m=$(c -Z --http2 -v -w '%header{x-conn}_%{num_connects}_%{http_version}\n' -o /dev/null -o /dev/null -o /dev/null \
    -o /dev/null -o /dev/null -o /dev/null $H/100000 $H/200000 $H/300000 $H/400000 $H/500000 $H/600000 2>"$W/mux.log")
check "h2: 6 parallel transfers on one connection" "1" "$(echo "$m" | cut -d_ -f1 | sort -u | wc -l | tr -d ' ')"
check "h2: 6 parallel transfers, 1 connect"        "1" "$(echo "$m" | cut -d_ -f2 | awk '{n += $1} END {print n}')"
check "h2: 6 parallel transfers, all HTTP/2"      "2 2 2 2 2 2" "$(echo "$m" | cut -d_ -f3 | tr '\n' ' ' | sed 's/ $//')"
check "h2: curl says it multiplexed" "yes" "$(grep -q 'Multiplexed connection found' "$W/mux.log" && echo yes || echo no)"
check "h2: 1 connect for 5 sequential GETs" "1" \
    "$(c -w '%{num_connects}\n' -o /dev/null -o /dev/null -o /dev/null -o /dev/null -o /dev/null $H/1 $H/2 $H/3 $H/4 $H/5 | awk '{n += $1} END {print n}')"
# Fall back to HTTP/1.1: a server that answers ALPN with http/1.1 only, and
# one that ignores ALPN (tls_server.py); --http2 asks for h2 too.
check "h2: falls back to http/1.1 (ALPN http/1.1)" "1.1 200 1000" \
    "$(c --http2 -o /dev/null -w '%{http_version} %{http_code} %{size_download}' https://localhost:18445/1000)"
check "h2: falls back to http/1.1 (no ALPN)"       "1.1 200 1000" \
    "$(c --http2 -o /dev/null -w '%{http_version} %{http_code} %{size_download}' https://localhost:18443/1000)"
check "h2: fallback POST 8 MB"   "$WANT" "$(c --http2 --data-binary @up.bin https://localhost:18445/post)"
# Sessions over h2: x-close makes the server end each connection after its
# answer, so every URL needs a new connection and a handshake.
O2="--noproxy localhost,127.0.0.1,other --cacert $W/cert.pem -o /dev/null -H x-close:1"
r2() { x=0; o=$("$CURL" -sS -v $O2 "$@" 2>&1) || x=$?; echo "$(echo "$o" | hs)$([ $x = 0 ] || echo " exit $x")"; }
N2="--next $O2"
check "h2 session: later connections resume" "full resumed resumed" "$(r2 $H/1 $N2 $H/2 $N2 $H/3)"
check "h2 session: resumed connection is h2" "2" \
    "$("$CURL" -sS $O2 -w '%{http_version}' $H/1 $N2 -w '%{http_version}' $H/2 | tail -c 1)"
check "h2 session: not after verify off"     "full full" "$(r2 $H/1 $N2 -k $H/2)"
check "h2 session: h1 server, then h2 server" "full full resumed" "$(r $U/1 $N2 $H/2 $N2 $H/3)"

for e in 2 3 7; do
    ASAN_LIB=""
    [ -n "$SAN" ] && ASAN_LIB="$(cc -print-file-name=libasan.so):"
    check "POST, 1 in $e socket calls stalls" "$WANT" \
        "$(EAGAIN_EVERY=$e LD_PRELOAD="$ASAN_LIB$W/eagain.so" "$CURL" --noproxy '*' -sS --cacert cert.pem --data-binary @up.bin https://localhost:18443/post)"
    check "GET, 1 in $e socket calls stalls" "200 3000000" \
        "$(EAGAIN_EVERY=$e LD_PRELOAD="$ASAN_LIB$W/eagain.so" "$CURL" --noproxy '*' -sS --cacert cert.pem -o /dev/null -w '%{http_code} %{size_download}' https://localhost:18443/3000000)"
    check "resumed, 1 in $e socket calls stalls" "full resumed" \
        "$(EAGAIN_EVERY=$e LD_PRELOAD="$ASAN_LIB$W/eagain.so" "$CURL" -sS -v $O $U/300000 $N $U/300000 2>&1 | hs)"
    check "h2: POST, 1 in $e socket calls stalls" "$WANT" \
        "$(EAGAIN_EVERY=$e LD_PRELOAD="$ASAN_LIB$W/eagain.so" "$CURL" --noproxy '*' -sS --cacert cert.pem --data-binary @up.bin $H/post)"
    check "h2: GET, 1 in $e socket calls stalls" "2 200 3000000" \
        "$(EAGAIN_EVERY=$e LD_PRELOAD="$ASAN_LIB$W/eagain.so" "$CURL" --noproxy '*' -sS --cacert cert.pem -o /dev/null -w '%{http_version} %{http_code} %{size_download}' $H/3000000)"
    check "h2: 4 parallel on 1 connection, 1 in $e socket calls stalls" "4" \
        "$(EAGAIN_EVERY=$e LD_PRELOAD="$ASAN_LIB$W/eagain.so" "$CURL" --noproxy '*' -sS --cacert cert.pem -Z -w '%header{x-conn}\n' -o /dev/null -o /dev/null -o /dev/null -o /dev/null $H/400000 $H/400000 $H/400000 $H/400000 | sort | uniq -c | awk '{printf "%s ", $1}' | sed 's/ $//')"
done
[ "$FAIL" = 0 ] && echo "all passed"
exit "$FAIL"
