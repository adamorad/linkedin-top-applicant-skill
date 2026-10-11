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
# parser-differential payloads must all fail the allowlist lint
L="$HERE/../skills/linkedin-top-applicant/scripts/lint-cv-html.py"
while IFS= read -r payload; do
  printf '<!DOCTYPE html><html><head><meta charset="utf-8"><title>t</title></head><body><p>%s</p></body></html>' "$payload" > "$OUT/p.html"
  if python3 -I "$L" "$OUT/p.html" 2>/dev/null; then echo "FAIL: lint accepted: $payload"; exit 1; fi
done <<'PAYLOADS'
<ScRiPt>alert(1)</ScRiPt>
<img src=x onerror=alert(1)>
<svg/onload=alert(1)>
<a href="file:///etc/passwd">x</a>
<p onclick="x">hi</p>
<![CDATA[<script>x</script>]]>
<!--[if IE]><script>x</script><![endif]-->
<iframe src=file:///etc/passwd></iframe>
a < b
PAYLOADS
echo "PASS"
