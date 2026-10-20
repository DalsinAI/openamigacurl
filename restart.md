# Restart: openamigacurl

_Written 6 October 2026 at about 23:55 UTC, while all work is paused on @SacredTrees's word (23:28 UTC). Read this first when work resumes; the newest capsule and the live PR list win if they disagree._

## 20 October 2026: TLS 1.3 sessions

With OpenTLS 1.3 (openamigatls #14) curl speaks TLS 1.3, and the backend caches a TLS 1.3 session only once the connection has read data (the server's ticket comes after the handshake), checks it again at close_notify, and leaves a connection that reads nothing out of the cache. CI builds OpenTLS from openamigatls branch `team2/tls13-20261020`; set both checkouts in ci.yml back to openamigatls main's merge commit once #14 merges. Stacked on the HTTP/2 PR.

## 20 October 2026: slim, and HTTP/2

curl is built with HTTP and HTTPS only and without the features OpenBrowser's engine does not use (README lists what stays and why), and with HTTP/2 through nghttp2 1.70.0 (pinned in SOURCES, fetched at build time; THIRD_PARTY_NOTICES.md). The host test runs HTTP/2 against `tests/host/h2_server.c`: downloads, uploads, multiplexing, fallback to HTTP/1.1 and resumption. Stacked on the TLS resumption PR.

## 20 October 2026: TLS sessions resumed

The OpenTLS backend resumes TLS sessions through curl's own session cache (one OTSession per peer key, kept as the peer's object), so every connection after the first to a server skips the key exchange and the certificate check. The host test checks it, including that a changed verify setting, CA file or host name gets a full handshake.

## 19 October 2026: AmiSSL out, OpenTLS in

On @SacredTrees's decision of 19 October (OpenTLS everywhere), curl's HTTPS now goes through opentls.library: `patches/0001-vtls-opentls-backend.patch` adds `lib/vtls/opentls.c` and `CURL_USE_OPENTLS`, and build.sh uses it. `tests/host/host-test.sh` (CI) passes on Linux, plain and under ASan/UBSan. The 68040 build runs in CI (`tests/amiga/ci-build.sh`) against OpenNDK's open bsdsocket headers (openamigasocket #24, openamigasdk #18; move the openamigasdk pin in ci.yml once #18 merges). Next: `curltest` on an instance, then OpenBrowser's `scripts/build-webcore.sh` off AmiSSL. Team 2 owns this repo's TLS work.

## What this repo is

curl and libcurl built for AmigaOS 3.x (m68k) as static link libraries. Part of the Open family and an OpenBrowser dependency. Upstream source is fetched and pinned at build time, never committed.

## Where it stands

Stable: it builds and OpenBrowser links it. Only the CONTRIBUTORS.md pass landed today.

## Merged lately

- #1 (85265f7, 2026-10-06): Credit who made openamigacurl: CONTRIBUTORS.md

## Open pull requests

- None.

## Next step

1. None queued. Bump the pinned upstream only with a reviewed version and sha256.

## Waiting on @SacredTrees

- Nothing.

## Who owns it

JSC thread (OpenBrowser).

## Capsules

Restart capsules for this repo's workstreams, in amigachrome's `capjumps/` shelf:

- [`20261006_AmigaChrome_OpenBrowser_JSC_Restart_Capsule.zip`](https://github.com/DalsinAI/amigachrome/tree/main/capjumps)

Team rules that still hold: commits as SacredTrees with no co-author lines; third-party code only on "yes with review" (licence checked, commit and sha256 pinned, fetched at build, never committed); deploys with deploy_dev.py only, on a typed line.
