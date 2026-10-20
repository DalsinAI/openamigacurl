# Third-party notices

Nothing below is committed here but the licence texts (`upstream/`): each
library is fetched as its release tarball at build time, checked against the
SHA-256 sum in [SOURCES](SOURCES), and unpacked under `work/`.

## curl 8.22.0

The library this repository builds. curl licence (MIT-style), Copyright (c)
Daniel Stenberg and many contributors; the full text is in `upstream/COPYING`.

- Source: https://curl.se/download/curl-8.22.0.tar.xz, SHA-256
  `f7ef3ae8a22e521f289803fe93543eb64c329b58aa73a9e224dfd915a2a5f4f7`.
- Changed: `patches/0001-vtls-opentls-backend.patch` adds the OpenTLS backend;
  the changed files stay under curl's licence.

## nghttp2 1.70.0

curl's HTTP/2. MIT licence, Copyright (c) 2012, 2014, 2015, 2016 Tatsuhiro
Tsujikawa and the nghttp2 contributors; the full text is in
`upstream/COPYING.nghttp2` and below.

- Source: https://github.com/nghttp2/nghttp2/releases/download/v1.70.0/nghttp2-1.70.0.tar.xz
  (the v1.70.0 release on GitHub, signed 29 July 2026), 2,018,996 bytes, SHA-256
  `e05cb1388eaca3830aded4ccf20044b6e1ac1a61411dcca11b0437c4285c8bc2`.
  Checked on 20 October 2026: the release's own signature
  (`nghttp2-1.70.0.tar.xz.asc`) is good, from Tatsuhiro Tsujikawa's key
  (primary `F4F3B91474D1EB29889BD0EF7E8403D5D673C366`, signing subkey
  `516B622918D15C478AB1EA3A5339A2BE82E07DEC`), and the tarball's `lib/` is
  the `v1.70.0` git tag's, file for file (plus the generated `nghttp2ver.h`).
- Used: `lib/` only, the library. Not used: the programs (`nghttp`,
  `nghttpd`, `nghttpx`, `h2load`), tools, examples, documentation and
  tests. `build.sh` compiles `lib/*.c` into `libnghttp2.a` for the 68040;
  `tests/host/host-test.sh` builds the same `lib/` for Linux, for curl and for
  its test server (`tests/host/h2_server.c`, ours).
- Changed: nothing. The build sets nghttp2's own macros (`NGHTTP2_STATICLIB`,
  `BUILDING_NGHTTP2`, `HAVE_NETINET_IN_H`, `NDEBUG`).

```
The MIT License

Copyright (c) 2012, 2014, 2015, 2016 Tatsuhiro Tsujikawa
Copyright (c) 2012, 2014, 2015, 2016 nghttp2 contributors

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
