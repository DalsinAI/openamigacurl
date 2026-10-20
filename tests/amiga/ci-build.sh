#!/bin/sh
# openamigacurl in the cloud: libcurl (with nghttp2) and curltest for the 68040 with the
# OpenAmigaGCC release toolchain and OpenNDK, no vendor headers anywhere.
# MIT, Copyright (c) 2026 AmigaChrome Team.
#
#   TOOLCHAIN_DIR  an unpacked openamigagcc-*-x86_64-linux folder
#   OPENNDK        an OpenNDK folder holding the bsdsocket headers
#   OPENTLS_SRC    an openamigatls checkout (default ../openamigatls)
#   TARBALLS       holds curl-8.22.0.tar.xz, nghttp2-1.70.0.tar.xz and
#                  zlib-1.3.1.tar.xz (default ./tarballs); build.sh checks
#                  each one's SHA-256 against SOURCES' sums
#
# usage: tests/amiga/ci-build.sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TC=$(CDPATH= cd -- "${TOOLCHAIN_DIR:?set TOOLCHAIN_DIR}" && pwd)
NDK=$(CDPATH= cd -- "${OPENNDK:?set OPENNDK}" && pwd)
OT=$(CDPATH= cd -- "${OPENTLS_SRC:-$HERE/../openamigatls}" && pwd)
TARBALLS=${TARBALLS:-"$HERE/tarballs"}
W="$HERE/work/ci"
mkdir -p "$W/stove" "$W/deps/lib" "$W/deps/include"
ln -sfn "$TC" "$W/stove/prefix"
CC="$TC/bin/m68k-amigaos-gcc"
CPU="-m68040 -m68881 -mcrt=nix20"

# zlib, which build.sh otherwise takes from openamigaimage
t="$TARBALLS/zlib-1.3.1.tar.xz"
echo "38ef96b8dfe510d42707d9c781877914792541133e1870841463bfa73f883e32  $t" | sha256sum -c - >/dev/null \
    || { echo "SHA-256 mismatch or missing: $t"; exit 2; }
tar xf "$t" -C "$W"
mkdir -p "$W/zobj"
for f in adler32 crc32 deflate infback inffast inflate inftrees trees zutil compress uncompr gzclose gzlib gzread gzwrite; do
    $CC -O2 $CPU -DHAVE_UNISTD_H -c "$W/zlib-1.3.1/$f.c" -o "$W/zobj/$f.o"
done
"$TC/bin/m68k-amigaos-ar" rcs "$W/deps/lib/libz.a" "$W/zobj"/*.o
cp "$W/zlib-1.3.1/zlib.h" "$W/zlib-1.3.1/zconf.h" "$W/deps/include/"

OS32_GCC16="$W/stove" NDK_INCLUDE="$NDK/Include_H" OPENTLS_INCLUDE="$OT/include" \
    DEPS_PREFIX="$W/deps" PREFIX="$W/out" TARBALLS="$TARBALLS" JOBS=${JOBS:-4} \
    "$HERE/build.sh" > "$W/build.log" 2>&1 || { tail -40 "$W/build.log"; exit 1; }
# the OpenTLS backend and the network headers build with no warning
if grep -E '(opentls\.c|Include_H/).*(warning|error)' "$W/build.log"; then exit 1; fi
tail -1 "$W/build.log"
# HTTP/2 is in: curl's configure found nghttp2, and curltest links it
grep -q 'Features:.*HTTP2' "$W/build.log" || { echo "curl was configured without HTTP/2"; exit 1; }
grep -q 'Protocols: http https$' "$W/build.log" || { echo "curl has protocols besides HTTP and HTTPS"; exit 1; }
"$TC/bin/m68k-amigaos-nm" "$W/out/curltest" | grep -q 'nghttp2_session_client_new' || { echo "curltest has no nghttp2"; exit 1; }
"$TC/bin/m68k-amigaos-objdump" -f "$W/out/curltest" | grep -q 'amiga' || { echo "curltest is not an Amiga executable"; exit 1; }
echo "68040 build ok: $W/out/lib/libcurl.a, $W/out/lib/libnghttp2.a, $W/out/curltest"
