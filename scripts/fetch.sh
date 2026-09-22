#!/bin/bash
# fetch.sh -- the install-media payload, for a build machine without makepkg.
#
# Reads the source list and the checksums from the PKGBUILD at the top of
# this repository and downloads into $SRCDEST, or into that directory when
# SRCDEST is unset. Re-runnable: a file already present and correct is kept.
# On an Arch-family machine `makepkg -o` does the same from the same list.
#
#     scripts/fetch.sh
#     SRCDEST=/some/where scripts/fetch.sh
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
dest=${SRCDEST:-$top}
# shellcheck source=../PKGBUILD
. "$top/PKGBUILD"
command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "sha256sum is required" >&2; exit 1; }

cd "$dest"
for i in "${!source[@]}"; do
    s=${source[$i]}
    if [[ $s == *::* ]]; then name=${s%%::*}; url=${s#*::}; else url=$s; name=${url##*/}; fi
    sum=${sha256sums[$i]}
    if [[ -s $name ]] && [[ $sum == SKIP || $(sha256sum "$name" | cut -d' ' -f1) == "$sum" ]]; then
        echo "have    $name"; continue
    fi
    echo "fetch   $name"
    curl -fsSL --retry 3 -o "$name" "$url"
    if [[ $sum != SKIP ]]; then
        echo "$sum  $name" | sha256sum -c --quiet || { echo "checksum mismatch: $name (see doc/, addendum 7.2)" >&2; exit 1; }
    fi
done
echo "== all sources present and verified in $dest"
