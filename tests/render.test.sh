#!/usr/bin/env bash
# Checks render-cv.sh: size/page limits, unsafe paths, script blocking, stale output.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
R="$HERE/../skills/linkedin-top-applicant/scripts/render-cv.sh"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT

"$R" "$HERE/fixtures/one-page.html" "$OUT/ok.pdf"
pdfinfo "$OUT/ok.pdf" | grep -q '^Title: *Jane Example | 01-Acme-Data-Lead' || { echo "FAIL: PDF title"; exit 1; }

if "$R" "$HERE/fixtures/overflow.html" "$OUT/long.pdf"; then
  echo "FAIL: overflow CV was accepted"; exit 1
fi

# path with space and '#', and an inline <script> that must not run
"$R" "$HERE/fixtures/dir with #space/../one-page.html" "$OUT/out dir #1/s.pdf"
if "$R" "$HERE/fixtures/dir with #space/script.html" "$OUT/s2.pdf" 2>/dev/null; then
  echo "FAIL: inline script accepted"; exit 1
fi

# a stale PDF must never be mistaken for a fresh render
echo stale > "$OUT/stale.pdf"
if CV_BROWSER=/usr/bin/false "$R" "$HERE/fixtures/one-page.html" "$OUT/stale.pdf"; then
  echo "FAIL: stale PDF accepted"; exit 1
fi
# navigating HTML must be rejected before any browser launch
if "$R" "$HERE/fixtures/refresh.html" "$OUT/r.pdf" 2>/dev/null; then
  echo "FAIL: meta refresh accepted"; exit 1
fi
[ ! -e "$OUT/r.pdf" ] || { echo "FAIL: PDF created for rejected HTML"; exit 1; }
echo "PASS"
