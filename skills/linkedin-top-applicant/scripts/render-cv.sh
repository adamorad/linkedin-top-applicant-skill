#!/usr/bin/env bash
# Render one CV HTML file to a one-page A4 PDF with headless Chrome.
# Browser: Chrome or Chromium (override with CV_BROWSER). Brave headless print-to-pdf
# produced no PDF when tested, so it is not auto-selected.
# Usage: render-cv.sh <input.html> <output.pdf> [max_pages]
# Exits non-zero if the PDF is not A4 or exceeds max_pages (default 1).
set -euo pipefail

IN="${1:?usage: render-cv.sh <input.html> <output.pdf> [max_pages]}"
OUT="${2:?usage: render-cv.sh <input.html> <output.pdf> [max_pages]}"
MAX_PAGES="${3:-1}"

[ -f "$IN" ] || { echo "ERROR: input not found: $IN" >&2; exit 1; }

BROWSER="${CV_BROWSER:-}"
if [ -z "$BROWSER" ]; then
  for c in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "$(command -v google-chrome 2>/dev/null || true)" \
    "$(command -v chromium 2>/dev/null || true)"; do
    if [ -n "$c" ] && [ -x "$c" ]; then BROWSER="$c"; break; fi
  done
fi
[ -n "$BROWSER" ] || { echo "ERROR: no Chrome/Chromium found; set CV_BROWSER" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
PROFILE_DIR="$(mktemp -d)"
trap 'rm -rf "$PROFILE_DIR"' EXIT

# Render a copy under a fixed safe name so '#', '?', '%' or spaces in the
# original path cannot break the file:// URL. No other local files are loaded.
# A CSP meta is prepended so script, network and local-file loads are blocked:
# the HTML may contain text derived from untrusted job descriptions.
IN_ABS="$PROFILE_DIR/cv.html"
CSP="<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:\">"
if grep -qi '<head>' "$IN"; then
  # keep the doctype first so the page stays out of quirks mode
  awk -v csp="$CSP" '!d && tolower($0) ~ /<head>/ { sub(/<[Hh][Ee][Aa][Dd]>/, "&" csp); d=1 } { print }' "$IN" > "$IN_ABS"
else
  { printf '%s\n' "$CSP"; cat "$IN"; } > "$IN_ABS"
fi

# Never trust a stale file from an earlier render.
rm -f "$OUT"

# Run under a watchdog and judge success by the PDF, not the exit code.
"$BROWSER" --headless=new --disable-gpu \
  --user-data-dir="$PROFILE_DIR/profile" \
  --no-pdf-header-footer --print-to-pdf="$OUT" \
  "file://$IN_ABS" >/dev/null 2>&1 &
BPID=$!
for _ in $(seq 1 60); do
  kill -0 "$BPID" 2>/dev/null || break
  sleep 0.5
done
kill "$BPID" 2>/dev/null || true
wait "$BPID" 2>/dev/null || true

[ -s "$OUT" ] || { echo "ERROR: browser produced no PDF" >&2; exit 1; }

if command -v pdfinfo >/dev/null 2>&1; then
  INFO="$(pdfinfo "$OUT")"
  PAGES="$(printf '%s\n' "$INFO" | awk '/^Pages:/ {print $2}')"
  SIZE="$(printf '%s\n' "$INFO" | awk -F': *' '/^Page size:/ {print $2}')"
else
  PAGES="$(grep -a -c '/Type */Page[^s]' "$OUT" || true)"
  SIZE="A4 (unchecked, pdfinfo missing)"
fi

case "$SIZE" in
  *A4*) ;;
  *) echo "ERROR: expected A4, got: $SIZE" >&2; exit 1 ;;
esac

if [ "$PAGES" -gt "$MAX_PAGES" ]; then
  echo "ERROR: $OUT is $PAGES pages (max $MAX_PAGES); trim content" >&2
  exit 2
fi

echo "OK: $OUT ($PAGES page, $SIZE)"
