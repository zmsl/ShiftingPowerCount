#!/usr/bin/env bash
# Checks a packager zip: ShiftingPowerCount/ at the root with its TOC and code, no dev paths, TOC version stamped.
set -euo pipefail
zip=${1:?usage: check_package.sh <zip>}
list=$(unzip -Z1 "$zip")
fail=0
need() { grep -qx "$1" <<<"$list" || { echo "missing: $1"; fail=1; }; }
for f in ShiftingPowerCount.toc ShiftingPowerCount.lua; do need "ShiftingPowerCount/$f"; done
for bad in '/spec/' '/docs/' '/tests/' '/tools/' '/scripts/' '/\.github/' 'Makefile$' 'mise\.toml$' '\.luacheckrc$' '/\.'; do
    if grep -qE "$bad" <<<"$list"; then echo "unexpected: $(grep -E "$bad" <<<"$list" | head -3)"; fail=1; fi
done
ver=$(basename "$zip" .zip); ver=${ver#ShiftingPowerCount-}
ver=${ver%-forever} # the packager tags the Forever build onto the zip name
v=$(unzip -p "$zip" ShiftingPowerCount/ShiftingPowerCount.toc | tr -d '\r' | sed -n 's/^## Version: //p')
[ "$v" = "$ver" ] || { echo "TOC Version '$v' != zip version '$ver'"; fail=1; }
[ $fail -eq 0 ] && echo "package ok: $zip"
exit $fail
