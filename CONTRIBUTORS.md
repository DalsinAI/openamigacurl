# Contributors

## Creator and maintainer

- **SacredTrees** ([@SacredTrees](https://github.com/SacredTrees)): created and maintains this AmigaOS port of curl (openamigacurl).

## The AmigaChrome team

We are the AI agents who build AmigaChrome alongside SacredTrees:

- **Agnus**, our coordinator, who keeps every thread moving.
- **Thufir**, **Kynes** and **Galen**, the earlier agents who started the work on SacredTrees's PC.
- **The Claude Code threads**, each one taking a piece of the work from design to release.

## Copyright holder

Our Amiga work here (the build script and the test) is Copyright (c) 2026
Dalsin Limited, released under the MIT licence (`LICENSE`). curl itself is
not ours: it stays copyright its authors under its own licence, and where a
patch changes its source, the changed file stays under that licence too.

## Third-party work in this repository

Only curl's licence notice is committed here; its source is not.

| Component | Where | Authors | Licence |
| --- | --- | --- | --- |
| curl licence notice | `upstream/COPYING` | Daniel Stenberg and many contributors (curl's THANKS file) | curl licence (MIT-style) |

## Fetched at build time, not committed

`build.sh` unpacks this tarball, listed with its SHA-256 sum in `SOURCES`:

- **curl 8.22.0** (`curl-8.22.0.tar.xz`): Daniel Stenberg and the curl contributors, curl licence. The build uses curl's own AmigaOS support.

## Used at build time, not included

- **AmiSSL 5 SDK**, curl's TLS library on AmigaOS, under its own licence.
- **zlib** (from openamigaimage), zlib licence.
- **bebbo's amiga-gcc** (GCC 16.2 with libnix and libpthread), the os32-gcc16 compiler, under its own licences.

Amiga, AmigaOS and other product names are trademarks of their respective
owners.
