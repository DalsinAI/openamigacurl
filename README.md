# openamigacurl

curl (libcurl) with OpenTLS and HTTP/2 for AmigaOS 3.x on 68k, built as static
link libraries for GCC programs. HTTP and HTTPS only. Part of the [OpenAmiga](https://github.com/DalsinAI/openamiga)
ports, made for [OpenBrowser](https://github.com/DalsinAI/openamigabrowser),
the WebKit browser for AmigaOS 3.2.

**Status, 20 October 2026:** TLS 1.3, with its sessions resumed, through OpenTLS 1.3 (openamigatls #14, not merged yet; it needs `OT_SessionHasTicket()`, at #14's aaf3319). HTTP/2 through nghttp2, and a slimmer curl: only HTTP, HTTPS and what OpenBrowser uses (below). Since 19 October, HTTPS goes through
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
| nghttp2 (HTTP/2) | 1.70.0 | MIT (upstream/COPYING.nghttp2, [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)) | https://nghttp2.org/ |

The exact files and their SHA-256 sums are in [SOURCES](SOURCES); `build.sh`
checks each sum before it unpacks a tarball, and no upstream source is
committed here. All credit for the libraries goes to their authors; see
`upstream/` and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for their
notices.

## What the Amiga port changes

- **An OpenTLS backend** (`patches/0001-vtls-opentls-backend.patch`): `lib/vtls/opentls.c`, a TLS backend for curl on `opentls.library` 1.2 or newer, and the CMake option `CURL_USE_OPENTLS` that turns it on. The TLS records go through curl's own connection filters by OpenTLS's I/O hook, so proxies and non-blocking sockets work as with any other backend. Otherwise curl's own AmigaOS support (`-DAMIGA=ON`): no threaded resolver (each AmigaOS task needs its own bsdsocket base) and no IPv6.
- **HTTP/2** through nghttp2 1.70.0 (`USE_NGHTTP2`, CMake's `--with-nghttp2`): `build.sh` builds nghttp2's library only (`lib/`, no programs or tools) with the same compiler and flags as curl, into `libnghttp2.a`. nghttp2 is portable C: every number on the wire goes through `nghttp2_put_uint16be`/`32be` and `nghttp2_get_uint16`/`32` (`memcpy` and `htonl`/`ntohl`, which OpenNDK's `<netinet/in.h>` makes no-ops on the big-endian 68k), and it builds for the 68k with no warning under `-Wall -Wextra -Wconversion -Wcast-align`. The OpenTLS backend offers ALPN `h2,http/1.1` and hands the server's choice to curl (`Curl_alpn_set_negotiated`), so HTTPS servers that speak HTTP/2 get it, several transfers to one server share one connection, and servers that do not fall back to HTTP/1.1. Plain `http://` stays HTTP/1.1 (no h2c upgrade unless asked for).
- **Slim: only what OpenBrowser uses.** Only HTTP and HTTPS are built (`HTTP_ONLY` and each other protocol turned off by name: FTP, FILE, LDAP, LDAPS, RTSP, DICT, TELNET, TFTP, POP3, IMAP, SMTP, GOPHER, MQTT, IPFS, and curl's WebSocket API), and with them none of the features OpenBrowser's engine leaves to itself or never asks for: cookies, HSTS, Alt-Svc, DoH, MIME and form posts, `.netrc`, AWS signatures, bearer, Kerberos, Negotiate and NTLM authentication, the header API, option introspection, `--libcurl`, the progress meter, DNS shuffling, local-address binding and date parsing. Kept, because the engine (WebKit's curl network layer with OpenBrowser's patches) uses them:
  - HTTP proxies with Basic and Digest authentication (`CURLOPT_PROXY`, `CURLOPT_NOPROXY`, `CURLOPT_PROXYAUTH`, `CURLOPT_PROXYHEADER`, user name and password), and Basic and Digest for servers (`CURLOPT_HTTPAUTH`);
  - the share handle for DNS and TLS sessions, the multi handle with its connection limits, `curl_multi_poll` and `curl_multi_wakeup` (curl's wake-up socket pair);
  - gzip and deflate answers (`CURLOPT_ACCEPT_ENCODING`, zlib);
  - `CURLOPT_CONNECT_ONLY` with `curl_easy_send`/`curl_easy_recv`, which WebKit's own WebSocket code runs on (it does not use curl's WebSocket API);
  - `CURLOPT_RESOLVE`, `CURLOPT_DNS_CACHE_TIMEOUT`, the timeouts, the debug callback and verbose messages (the engine's network log), `curl_easy_pause`, and every `CURLINFO` the engine reads.
  - Not needed from curl: `file:` and `data:` addresses (the engine opens files and decodes `data:` itself; its `CURLOPT_PROTOCOLS_STR` "file,http,https" is refused because `file` is not built, as it already was, which leaves curl with what it has: HTTP and HTTPS), cookies (OpenBrowser's own cookie jar; the engine turns curl's off with `CURLOPT_COOKIEFILE` NULL, and sharing `CURL_LOCK_DATA_COOKIE` just answers "not built in"), and Alt-Svc (only of use with HTTP/3). OpenBrowser Lite does not use curl.
- **What the backend does:** TLS 1.0 to 1.3 (TLS 1.3 with `opentls.library` 1.3; 1.2 and older libraries stop at TLS 1.2), ALPN, SNI, certificate chains checked against `S:OpenTLS/ca-bundle.pem` and `ENVARC:OpenTLS/certs/`, host names and IP addresses. `CURLOPT_CAINFO` and `CURLOPT_CAINFO_BLOB` replace that store, as with other backends; `CURLOPT_SSL_VERIFYPEER` and `CURLOPT_SSL_VERIFYHOST` turn checks off (the host name only together with the chain: VERIFYHOST on with VERIFYPEER off is refused), and with VERIFYPEER off no trust store is needed. The trust store is read once and shared by connections with the same settings (reading it costs seconds on a 68040). TLS sessions are resumed: the first full handshake with a server leaves its session in curl's session cache, and later connections to that server resume it, skipping the key exchange and the certificate check, which are most of a handshake's time on a 68040. A session is only offered to a connection with the same host, port, verify settings, trust store and TLS versions, so a session made with `-k` never lets a checked connection through unchecked; `CURLOPT_SSL_SESSIONID_CACHE` 0 turns it off, and a resumption that fails takes the session out of the cache.
- **TLS 1.3 sessions.** A TLS 1.3 session is the server's ticket, which the server sends after the handshake and OpenTLS reads in `OT_Read()`; a session taken before it comes resumes nothing. So the backend caches a TLS 1.2 session when the handshake ends, as before, and keeps a TLS 1.3 connection's session to itself until its ticket has come: after each read, until then, `OT_SessionHasTicket()` (`opentls.library` 1.3) says whether it has, and the session goes to the cache once it has. A connection that never gets a ticket (one that reads nothing, or a server that sends none) caches nothing, so it never pushes a server's good session out of the cache. A resumed TLS 1.3 connection caches the new ticket it gets. It costs one session copy per connection and one short call per read until the ticket is seen. With a library older than 1.3, which has no TLS 1.3, sessions are cached as before.
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

Link with: `-lcurl -lnghttp2 -lz -lpthread -latomic -lm`. At run time the Amiga needs
`opentls.library` 1.2 or newer in `LIBS:` and its CA bundle in
`S:OpenTLS/ca-bundle.pem`.

## Sizes

68040 build (`tests/amiga/ci-build.sh`, OpenAmigaGCC 16.2.0-open3), in bytes:

| | `libcurl.a` | `libnghttp2.a` | `curltest`, linked |
| --- | ---: | ---: | ---: |
| before (HTTP and HTTPS, the other features on) | 598,588 | | 564,536 |
| slim, no HTTP/2 | 499,980 | | 470,776 |
| slim, with HTTP/2 (this build) | 555,348 | 150,076 | 650,744 |

The slim settings take 98,608 bytes off `libcurl.a` (16%) and 93,760 off a
linked program; HTTP/2 (nghttp2 and curl's HTTP/2 code) then adds 179,968 to
it, so a program linked with curl is 86,208 bytes bigger than before.

## OpenBrowser: the engine must ask for HTTP/2 too

curl only speaks HTTP/2 to a server when the program asks for it. WebKit's
curl network layer does: `CurlHandle::enableHttp()` (`CurlContext.cpp`) asks
for `CURL_HTTP_VERSION_NONE`, which is curl's default, `CURL_HTTP_VERSION_2TLS`
(HTTP/2 over TLS, HTTP/1.1 otherwise), with `CURLOPT_PIPEWAIT` set, as soon as
`curl_version_info()` reports `CURL_VERSION_HTTP2`, which this build does. Its
multi handle leaves `CURLMOPT_PIPELINING` at curl's default,
`CURLPIPE_MULTIPLEX`. So OpenBrowser gets HTTP/2 from this build without a
change to the engine; the engine could say `CURL_HTTP_VERSION_2TLS` and
`CURLPIPE_MULTIPLEX` explicitly so that a later curl default does not change
it.

## Tested

### TLS 1.3 and its sessions, on Linux (20 October 2026)

`tests/host/host-test.sh` builds OpenTLS from openamigatls #14 (branch
`team2/tls13-20261020`; CI checks out that branch until #14 merges, then
openamigatls main again) and adds TLS 1.3-only servers: `tls_server.py` with
OpenSSL's two tickets per handshake, the same with no tickets, and
`h2_server.c` over TLS 1.3, with and without tickets. It checks that a TLS 1.3
server gets TLS 1.3 and a server with both does too, an 8 MB upload and a 20 MB
download over TLS 1.3, and that `--tls-max 1.2` against a TLS 1.3-only server
and `--tlsv1.3` against a TLS 1.2-only one are refused. Sessions over TLS 1.3:
the second and third connections resume (all TLS 1.3), also in parallel after
the first; a connection still open has cached its session once its ticket
came; verification turned on or off, another CA file, `--no-sessionid`,
another host name or a TLS 1.2 limit gets a full handshake, and a `-k` session
does not skip the host name check; a server that sends no ticket gets full
handshakes and nothing in the session cache. HTTP/2
over TLS 1.3: a 20 MB download, an 8 MB upload, four transfers multiplexed on
one connection, and the second and third connections resume and are HTTP/2
over TLS 1.3 again (not after verify off; no resumption with no tickets). TLS
1.3 resumption, over HTTP/1.1 and HTTP/2, is also checked with one socket call
in 2, 3 or 7 answering "would block". The TLS 1.2 tests run as before against
servers held to TLS 1.2. CI runs all of it plainly and with AddressSanitizer
and UBSan.

### HTTP/2, on Linux (20 October 2026)

`tests/host/host-test.sh` also builds nghttp2's library from the same tarball,
links curl with it, and runs `tests/host/h2_server.c`, a small HTTP/2 server
on that library and the host's OpenSSL that speaks only h2, chosen by ALPN,
over TLS 1.2. It checks that curl offers `h2,http/1.1` and the server takes
h2; a 20 MB download and an 8 MB upload over HTTP/2, byte for byte; HTTP/2 by
default, without `--http2`; six parallel transfers (`curl -Z`) on one
connection, one stream each ("Multiplexed connection found", one connect,
one server connection); five transfers one after another on one connection;
the fall back to HTTP/1.1 against a server that answers ALPN with http/1.1
only and one that ignores ALPN; session resumption over HTTP/2 (each later
connection resumes, and is HTTP/2 again; not after verify off; sessions kept
apart per server); and HTTP/2 uploads, downloads and four multiplexed
transfers with one socket call in 2, 3 or 7 answering "would block". CI runs
it plainly and with AddressSanitizer and UBSan. The 68040 build in CI builds
nghttp2 and checks that curl has HTTP/2, only HTTP and HTTPS, and that
`curltest` links nghttp2.

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

- Only HTTP and HTTPS are built. HTTP/2 is HTTPS only (by ALPN); no HTTP/3.
- TLS 1.3 needs `opentls.library` 1.3 (openamigatls #14). No 0-RTT data.

## Licence

AmigaChrome Team's Amiga changes (the build script, patches, configuration
headers and tests) are MIT, Copyright (c) 2026 AmigaChrome Team: see
[LICENSE](LICENSE). curl and nghttp2 keep their own licences, in
[upstream/](upstream/) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md);
a patch to their source stays under that licence.

## Contributors

This port is maintained by [SacredTrees](https://github.com/SacredTrees) with The AmigaChrome Team, copyright AmigaChrome Team. Everyone whose work it includes is credited in [`CONTRIBUTORS.md`](CONTRIBUTORS.md).
