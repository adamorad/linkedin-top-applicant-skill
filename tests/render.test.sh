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
# parser-differential payloads must all be rejected, with no output written
L="$HERE/../skills/linkedin-top-applicant/scripts/lint-cv-html.py"
n=0
while IFS= read -r payload; do
  n=$((n+1)); rm -f "$OUT/clean.html"
  printf '<!DOCTYPE html><html><head><meta charset="utf-8"><title>t</title></head><body><p>%s</p></body></html>' "$payload" > "$OUT/p.html"
  if python3 -I "$L" "$OUT/p.html" "$OUT/clean.html" 2>/dev/null; then echo "FAIL: accepted: $payload"; exit 1; fi
  [ ! -e "$OUT/clean.html" ] || { echo "FAIL: output written for: $payload"; exit 1; }
done <<'PAYLOADS'
<ScRiPt>alert(1)</ScRiPt>
<img src=x onerror=alert(1)>
<svg/onload=alert(1)>
<a href="file:///etc/passwd">x</a>
<p onclick="x">hi</p>
<![CDATA[<script>x</script>]]>
<iframe src=file:///etc/passwd></iframe>
<p class="a" class="b" style="x">y</p>
<span class="x&quot; onmouseover=&quot;y">z</span>
<title><img src=x onerror=1></title>
a < b
PAYLOADS

# comments that mention <head> must not be able to displace the CSP
printf '<!DOCTYPE html><html><head><!-- <head> --><meta charset="utf-8"><title>t</title><style>p{color:red}</style></head><body><p>ok &amp; fine</p></body></html>' > "$OUT/c.html"
python3 -I "$L" "$OUT/c.html" "$OUT/c.out.html"
grep -q '^<!DOCTYPE html>' "$OUT/c.out.html" || { echo "FAIL: doctype"; exit 1; }
head -c 200 "$OUT/c.out.html" | grep -q '<html><head><meta http-equiv="Content-Security-Policy"' || { echo "FAIL: CSP not first in head"; exit 1; }
grep -q '&amp; fine' "$OUT/c.out.html" || { echo "FAIL: entity lost"; exit 1; }
! grep -q -- '<!--' "$OUT/c.out.html" || { echo "FAIL: comment survived"; exit 1; }

# comments (including conditional ones) are dropped, so nothing from them survives
printf '<!DOCTYPE html><html><head><meta charset="utf-8"><title>t</title></head><body><p>a</p><!--[if IE]><script>x</script><![endif]--></body></html>' > "$OUT/cc.html"
python3 -I "$L" "$OUT/cc.html" "$OUT/cc.out.html"
! grep -qi 'script' "$OUT/cc.out.html" || { echo "FAIL: comment content survived"; exit 1; }

# the shipped template must pass
python3 -I "$L" "$HERE/../skills/linkedin-top-applicant/templates/cv.html" "$OUT/t.html"
echo "PASS ($n payloads rejected)"
