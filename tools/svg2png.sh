#!/usr/bin/env bash
# uso: tools/svg2png.sh entrada.svg saida.png [largura_px]   (renderiza com Chrome headless)
set -euo pipefail
in="$(realpath "$1")"; out="$(realpath -m "$2")"; w="${3:-1400}"
read vw vh < <(python3 - "$in" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
m=re.search(r'viewBox="\s*[-\d.]+\s+[-\d.]+\s+([\d.]+)\s+([\d.]+)"',s)
print(m.group(1),m.group(2))
PY
)
h=$(python3 -c "print(round($w*$vh/$vw))")
tmp=$(mktemp -d); cat > "$tmp/p.html" <<HTML
<html><body style="margin:0;background:#fff"><img src="file://$in" style="width:${w}px;height:${h}px;display:block"></body></html>
HTML
google-chrome --headless=new --no-sandbox --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --user-data-dir="$tmp/prof" --window-size="${w},${h}" --screenshot="$out" "file://$tmp/p.html" >/dev/null 2>&1
rm -rf "$tmp"; echo "ok $out ${w}x${h}"
