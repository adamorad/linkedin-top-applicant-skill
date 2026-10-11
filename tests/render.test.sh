#!/usr/bin/env bash
# Checks render-cv.sh: a short CV renders to 1 A4 page, an overflowing CV is rejected.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
R="$HERE/../skills/linkedin-top-applicant/scripts/render-cv.sh"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT

"$R" "$HERE/fixtures/one-page.html" "$OUT/ok.pdf"
pdfinfo "$OUT/ok.pdf" | grep -q '^Title: *Jane Example | 01-Acme-Data-Lead' || { echo "FAIL: PDF title"; exit 1; }

if "$R" "$HERE/fixtures/overflow.html" "$OUT/long.pdf"; then
  echo "FAIL: overflow CV was accepted"; exit 1
fi
echo "PASS"
