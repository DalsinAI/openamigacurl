#!/bin/sh
# openamigacurl: curl (libcurl) with AmiSSL, built for AmigaOS 3.x (68020 + FPU) with the
# os32-gcc16 compiler (bebbo's amiga-gcc, GCC 16.2, libnix, libpthread).
# MIT, Copyright (c) 2026 Dalsin Limited. The library keeps its own licence.
#
#   OS32_GCC16   compiler root holding prefix/ and compat/
#                (default ~/AmigaChrome/stoves/os32-gcc16)
#   PREFIX       where include/ and lib/ go (default ./out)
#   TARBALLS     folder holding the upstream tarballs listed in SOURCES
#                (default ./tarballs); the script checks their SHA-256
#   JOBS         parallel jobs for CMake/make builds (default 2)
#
# usage: ./build.sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
S=${OS32_GCC16:-"$HOME/AmigaChrome/stoves/os32-gcc16"}
P=$S/prefix
OUT=${PREFIX:-"$HERE/out"}
TARBALLS=${TARBALLS:-"$HERE/tarballs"}
JOBS=${JOBS:-2}
WORK="$HERE/work"
CC="$P/bin/m68k-amigaos-gcc"
CXX="$P/bin/m68k-amigaos-g++"
AR="$P/bin/m68k-amigaos-ar"
CPU=${OS32_CPU_FLAGS:-"-m68020 -m68881 -mcrt=nix20"}
CFLAGS="-O2 $CPU -D_DEFAULT_SOURCE=1 -D_POSIX_TIMERS=1 -D_POSIX_REALTIME_SIGNALS=1 -fno-common"
mkdir -p "$OUT/include" "$OUT/lib" "$WORK"

# unpack NAME TARBALL SHA256: check the tarball and unpack it into $WORK
unpack() {
    t="$TARBALLS/$2"
    [ -f "$t" ] || { echo "missing $t (see SOURCES)"; exit 2; }
    echo "$3  $t" | sha256sum -c - >/dev/null || { echo "SHA-256 mismatch: $t"; exit 2; }
    rm -rf "$WORK/$1"; mkdir -p "$WORK/$1"
    case "$2" in
        *.zip) (cd "$WORK/$1" && unzip -q "$t") ;;
        *) tar xf "$t" -C "$WORK/$1" ;;
    esac
}

# archive NAME FILE...: compile into $OUT/lib/libNAME.a ($XFLAGS added)
archive() {
    name=$1; shift
    obj="$WORK/obj-$name"
    rm -rf "$obj"; mkdir -p "$obj"
    for f in "$@"; do
        o="$obj/$(echo "$f" | tr '/' '_' | sed 's/\.[a-z]*$//').o"
        case "$f" in
            *.cc|*.cpp) $CXX $CFLAGS ${XFLAGS:-} -c "$f" -o "$o" ;;
            *) $CC $CFLAGS ${XFLAGS:-} -c "$f" -o "$o" ;;
        esac
    done
    rm -f "$OUT/lib/lib$name.a"
    $AR rcs "$OUT/lib/lib$name.a" "$obj"/*.o
    echo "lib$name.a: $(wc -c < "$OUT/lib/lib$name.a") bytes"
}

TOOLCHAIN=${TOOLCHAIN_FILE:?set TOOLCHAIN_FILE to openamigabrowser/toolchain/amigaos3-gcc16.cmake}
AMISSL=${AMISSL_SDK:?set AMISSL_SDK to the Developer folder of the AmiSSL 5 SDK}
# zlib (gzip and deflate answers): openamigaimage's, in DEPS_PREFIX (default PREFIX).
DEPS=${DEPS_PREFIX:-$OUT}
[ -f "$DEPS/lib/libz.a" ] || { echo "missing $DEPS/lib/libz.a (zlib, from openamigaimage)"; exit 2; }
unpack curl curl-8.22.0.tar.xz f7ef3ae8a22e521f289803fe93543eb64c329b58aa73a9e224dfd915a2a5f4f7
# curl's configure checks link programs, and asks for libnet: an empty one will do.
mkdir -p "$WORK/stublibs" && "$AR" rcs "$WORK/stublibs/libnet.a"
mkdir -p "$WORK/curl/build" && cd "$WORK/curl/build"
cmake ../curl-8.22.0 -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS_RELEASE=-O2 \
    -DCMAKE_EXE_LINKER_FLAGS="$CPU -L$WORK/stublibs" -DCMAKE_INSTALL_PREFIX="$OUT" -DAMIGA=ON \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_CURL_EXE=OFF -DBUILD_TESTING=OFF \
    -DBUILD_LIBCURL_DOCS=OFF -DBUILD_MISC_DOCS=OFF -DENABLE_CURL_MANUAL=OFF -DHTTP_ONLY=ON \
    -DCURL_USE_LIBPSL=OFF -DCURL_USE_LIBSSH2=OFF -DUSE_NGHTTP2=OFF -DUSE_LIBIDN2=OFF -DCURL_BROTLI=OFF \
    -DCURL_ZSTD=OFF -DENABLE_THREADED_RESOLVER=OFF -DENABLE_IPV6=OFF -DCURL_DISABLE_LDAP=ON \
    -DCURL_DISABLE_ALTSVC=ON -DHAVE_PIPE=OFF -DUSE_SSLS_EXPORT=ON \
    -DHAVE_FCNTL_O_NONBLOCK=OFF -DHAVE_IOCTL_FIONBIO=OFF -DHAVE_IOCTLSOCKET_CAMEL=ON -DHAVE_IOCTLSOCKET_CAMEL_FIONBIO=ON \
    -DAMISSL_INCLUDE_DIR="$AMISSL/include" -DAMISSL_STUBS_LIBRARY="$AMISSL/lib/AmigaOS3/libamisslstubs.a" \
    -DAMISSL_AUTO_LIBRARY="$AMISSL/lib/AmigaOS3/libamisslauto.a" \
    -DCURL_ZLIB=ON -DZLIB_INCLUDE_DIR="$DEPS/include" -DZLIB_LIBRARY="$DEPS/lib/libz.a"
make -j"$JOBS" libcurl_static
cp lib/libcurl.a "$OUT/lib/"
mkdir -p "$OUT/include/curl" && cp ../curl-8.22.0/include/curl/*.h "$OUT/include/curl/"
