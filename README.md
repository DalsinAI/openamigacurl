# openamigacurl

curl (libcurl) with AmiSSL for AmigaOS 3.x on 68k, built as static link libraries for
GCC programs. Part of the [OpenAmiga](https://github.com/DalsinAI/openamiga)
ports, made for [OpenBrowser](https://github.com/DalsinAI/openamigabrowser),
the WebKit browser for AmigaOS 3.2.

**Status:** Working: builds, and fetches pages over HTTP and HTTPS (AmiSSL) on the bench.

This repository holds the Amiga build, not curl itself: a build script,
a smoke test and the upstream licences.

## Upstream

| Library | Version | Licence | Home |
| --- | --- | --- | --- |
| curl | 8.22.0 | curl licence, MIT-style (upstream/COPYING) | https://curl.se/ |

The exact files and their SHA-256 sums are in [SOURCES](SOURCES). All credit
for the library goes to its authors; see `upstream/` for their notices.

## What the Amiga port changes

- No source changes. curl's own AmigaOS support (`-DAMIGA=ON`) with AmiSSL 5 as its OpenSSL. HTTP and HTTPS only, no threaded resolver (each AmigaOS task needs its own bsdsocket base) and no IPv6.
- **Sockets are not file descriptors.** curl's configure finds libnix's `fcntl()`, `ioctl()` and `pipe()` and would use them on bsdsocket sockets, which fails (every transfer then stops with "Out of memory" while curl makes its wake-up socket pair). The script tells curl to use `IoctlSocket(FIONBIO)` and no `pipe()`, so the wake-up pair is a loopback TCP pair through bsdsocket.library.
- **Your program opens the network.** Each task that calls curl opens `bsdsocket.library` and AmiSSL (`OpenAmiSSLTags`) itself, sets the global `SocketBase`, `AmiSSLBase` and `AmiSSLExtBase`, and links `libamisslstubs.a`. `tests/curltest.c` shows how.

## Building

You need the os32-gcc16 compiler (bebbo's amiga-gcc on GCC 16.2 with libnix
and libpthread; see DalsinAI/openamigabrowser `stove/`) and the upstream
tarballs from [SOURCES](SOURCES) in `tarballs/`. Then:

```
./build.sh
```

The libraries and headers land in `out/` (set `PREFIX` to change that). The
script prints which other settings it needs, if any. Target: 68020 or better
with an FPU (`-m68020 -m68881`), libnix (`-mcrt=nix20`).

Link with: `-lcurl -lz libamisslstubs.a -lpthread -latomic -lm`

## Tested

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

## Licence

Dalsin Limited's Amiga changes (the build script, patches, configuration
headers and tests) are MIT, Copyright (c) 2026 Dalsin Limited: see
[LICENSE](LICENSE). curl keeps its own licence, in
[upstream/](upstream/); a patch to its source stays under that licence.
