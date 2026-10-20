# openamigacurl

curl (libcurl) with OpenTLS for AmigaOS 3.x on 68k, built as static link libraries for
GCC programs. Part of the [OpenAmiga](https://github.com/DalsinAI/openamiga)
ports, made for [OpenBrowser](https://github.com/DalsinAI/openamigabrowser),
the WebKit browser for AmigaOS 3.2.

**Status, 19 October 2026:** HTTPS goes through
[OpenTLS](https://github.com/DalsinAI/openamigatls) (`opentls.library`), the
Team's own TLS, in place of AmiSSL. The OpenTLS backend passes its host tests
(below), and the 68040 build runs in CI; a run of `curltest` on an
instance is still to do.

This repository holds the Amiga build, not curl itself: a build script,
curl's OpenTLS backend as a patch, tests and the upstream licences.

## Upstream

| Library | Version | Licence | Home |
| --- | --- | --- | --- |
| curl | 8.22.0 | curl licence, MIT-style (upstream/COPYING) | https://curl.se/ |

The exact files and their SHA-256 sums are in [SOURCES](SOURCES). All credit
for the library goes to its authors; see `upstream/` for their notices.

## What the Amiga port changes

- **An OpenTLS backend** (`patches/0001-vtls-opentls-backend.patch`): `lib/vtls/opentls.c`, a TLS backend for curl on `opentls.library` 1.2 or newer, and the CMake option `CURL_USE_OPENTLS` that turns it on. The TLS records go through curl's own connection filters by OpenTLS's I/O hook, so proxies and non-blocking sockets work as with any other backend. Otherwise curl's own AmigaOS support (`-DAMIGA=ON`): HTTP and HTTPS only, no threaded resolver (each AmigaOS task needs its own bsdsocket base) and no IPv6.
- **What the backend does:** TLS 1.0 to 1.2 (OpenTLS has no 1.3 yet; a server that wants only 1.3 is refused with a clear error), ALPN, SNI, certificate chains checked against `S:OpenTLS/ca-bundle.pem` and `ENVARC:OpenTLS/certs/`, host names and IP addresses. `CURLOPT_CAINFO` and `CURLOPT_CAINFO_BLOB` replace that store, as with other backends; `CURLOPT_SSL_VERIFYPEER` and `CURLOPT_SSL_VERIFYHOST` turn checks off (the host name only together with the chain: VERIFYHOST on with VERIFYPEER off is refused), and with VERIFYPEER off no trust store is needed. The trust store is read once and shared by connections with the same settings (reading it costs seconds on a 68040). TLS sessions are resumed: the first full handshake with a server leaves its session in curl's session cache, and later connections to that server resume it, skipping the key exchange and the certificate check, which are most of a handshake's time on a 68040. A session is only offered to a connection with the same host, port, verify settings, trust store and TLS versions, so a session made with `-k` never lets a checked connection through unchecked; `CURLOPT_SSL_SESSIONID_CACHE` 0 turns it off.
- **Not yet:** client certificates, `CURLOPT_PINNEDPUBLICKEY` (OpenTLS pins whole certificates, curl pins keys), cipher lists, OCSP stapling and certificate details (`CURLOPT_CERTINFO`). Asking for one gives an error, never a silent downgrade.
- **Sockets are not file descriptors.** curl's configure finds libnix's `fcntl()`, `ioctl()` and `pipe()` and would use them on bsdsocket sockets, which fails (every transfer then stops with "Out of memory" while curl makes its wake-up socket pair). The script tells curl to use `IoctlSocket(FIONBIO)` and no `pipe()`, so the wake-up pair is a loopback TCP pair through bsdsocket.library.
- **Your program opens the network.** Each task that calls curl opens `bsdsocket.library` itself, sets the global `SocketBase` and points bsdsocket's errno at the C library's (`SocketBaseTags(SBTM_SETVAL(SBTC_ERRNOPTR(sizeof(errno))), &errno, ...)`); AmiSSL used to do that last part through `AmiSSL_ErrNoPtr`. curl opens `opentls.library` itself, under a base of its own, so a program that uses OpenTLS directly keeps its own `OpenTLSBase`. `tests/curltest.c` shows how.
- **Stack:** an OpenTLS handshake needs 16 KB of the calling task's stack, and curl calls it from deep in its own code; give the task 64 KB.

## Building

You need the os32-gcc16 compiler (OpenAmigaGCC 16.2.0-open2 with libnix
and libpthread; see DalsinAI/openamigabrowser `stove/`), the upstream
tarballs from [SOURCES](SOURCES) in `tarballs/`, and an
[openamigatls](https://github.com/DalsinAI/openamigatls) checkout beside this
one for `opentls.library`'s headers (or set `OPENTLS_INCLUDE` to its
`include/`). Then:

```
./build.sh
```

The libraries and headers land in `out/` (set `PREFIX` to change that). The
script prints which other settings it needs, if any. Needs a 68040
with FPU (hard float, `-m68040 -m68881`), libnix (`-mcrt=nix20`).

Link with: `-lcurl -lz -lpthread -latomic -lm`. At run time the Amiga needs
`opentls.library` 1.2 or newer in `LIBS:` and its CA bundle in
`S:OpenTLS/ca-bundle.pem`.

## Tested

### OpenTLS backend, on Linux (19 October 2026)

`tests/host/host-test.sh` builds curl with `patches/` against OpenTLS's host
build (openamigatls e7c0e2d) and runs it against a local HTTPS server; CI runs
it on every push, once plainly and once with AddressSanitizer and UBSan. It
checks an 8 MB upload and a 20 MB download byte for byte, a server that closes
without close_notify, connection reuse, changing CA files, a wrong host name
(refused, and allowed with `-k`), an empty trust store, a server that wants
TLS 1.3 only, and the same uploads and downloads with one socket call in 2, 3
or 7 answering "would block" and the rest cut short. Since 20 October it also
checks session resumption: the second and later connections to a server
resume (also in parallel, and with sockets that would block), and a connection
with verification turned on or off, another CA file, another host name or
`--no-sessionid` does a full handshake; a session made with `-k` for a host
name the certificate does not match is not used to skip the check. Through a
TLS proxy it also fetched GitHub pages and curl's own 2.9 MB release with the
right SHA-256.

The 68040 build runs in CI too (`tests/amiga/ci-build.sh`): libcurl and
`curltest` with OpenAmigaGCC 16.2.0-open3 and OpenNDK, whose bsdsocket headers
are OpenSocket's own (openamigasdk #18), with no vendor header anywhere. curl's
own CMake toolchain file is `cmake/amigaos3-gcc16.cmake`. `curltest` is still
to be run on an instance.

### AmiSSL build, on the bench (before this change)

`tests/curltest.c`, run on AmigaOS 3.2.3 on AmigaChrome's AC090 emulation (68040 with FPU, 256 MB), Instance-24, 4 October 2026, as `curltest http://example.com/ https://example.com/ https://login.live.com/`:

```
CURL libcurl/8.22.0 OpenSSL/3.6.2 zlib/1.3.1
http://example.com/ rc=0 (No error) http=200 bytes=577 type=text/html; charset=utf-8 final=http://example.com/
  starts: <!doctype html><html lang=en><head><meta charset=utf-8><link
https://example.com/ rc=0 (No error) http=200 bytes=577 type=text/html; charset=utf-8 final=https://example.com/
  starts: <!doctype html><html lang=en><head><meta charset=utf-8><link
https://login.live.com/ rc=0 (No error) http=200 bytes=32675 type=text/html; charset=utf-8 final=https://login.live.com/
  starts: <!-- Copyright (C) Microsoft Corporation. All rights reserve
CURL_DONE
```

The bench ran OpenSocket's bsdsocket.library 4.2 and AmiSSL 5. HTTPS certificates were checked against AmiSSL's own store.

It has not yet been run on real Amiga hardware.

## Known issues

- Only HTTP and HTTPS are built; no HTTP/2.
- No TLS 1.3 until OpenTLS has it.

## Licence

AmigaChrome Team's Amiga changes (the build script, patches, configuration
headers and tests) are MIT, Copyright (c) 2026 AmigaChrome Team: see
[LICENSE](LICENSE). curl keeps its own licence, in
[upstream/](upstream/); a patch to its source stays under that licence.

## Contributors

This port is maintained by [SacredTrees](https://github.com/SacredTrees) with The AmigaChrome Team, copyright AmigaChrome Team. Everyone whose work it includes is credited in [`CONTRIBUTORS.md`](CONTRIBUTORS.md).
