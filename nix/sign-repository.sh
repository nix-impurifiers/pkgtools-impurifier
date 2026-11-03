#!/bin/sh
# SPDX-License-Identifier: MIT
# Run on a writable copy, using the publisher's existing GPG keyring.
set -eu
cd "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
for package in ./slackware64/impurifiers/*.txz; do
  gpg --batch --yes --armor "$@" --detach-sign "$package"
done
checksums=$(mktemp ./.CHECKSUMS.md5.XXXXXXXX)
trap 'rm -f -- "$checksums"' EXIT HUP INT TERM
find . -type f ! -name CHECKSUMS.md5 ! -name CHECKSUMS.md5.asc ! -name '.CHECKSUMS.md5.*' -print0 \
  | sort -z | xargs -0 md5sum > "$checksums"
mv -- "$checksums" CHECKSUMS.md5
gpg --batch --yes --armor "$@" --detach-sign CHECKSUMS.md5
