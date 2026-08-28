#!/bin/bash
# Strips every product name out of the built client.
#
# The page title, the mobile app title, the web manifest and the tab icon all
# name CloudCLI or Claude. This front end is reached from a work machine, and a
# browser tab reading `Claude UI` is the thing that gets noticed. Nothing here
# changes behaviour — it renames what a viewer can read.
#
# Applied to the built output rather than to upstream source, so this stays
# packaging rather than a fork.
set -euo pipefail

DIST="${1:-/app/dist}"
NAME="${APP_NAME:-Console}"

test -f "$DIST/index.html"

python3 - "$DIST" "$NAME" <<'PY'
import base64
import json
import pathlib
import re
import sys

dist = pathlib.Path(sys.argv[1])
name = sys.argv[2]

# A neutral mark: no glyph, no letter, nothing to read.
favicon = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">'
    '<rect width="32" height="32" rx="7" fill="#1e2326"/>'
    '<rect x="7" y="10" width="18" height="2.4" rx="1.2" fill="#a7c080"/>'
    '<rect x="7" y="15" width="13" height="2.4" rx="1.2" fill="#7fbbb3"/>'
    '<rect x="7" y="20" width="16" height="2.4" rx="1.2" fill="#d3c6aa"/>'
    '</svg>'
)

index = dist / 'index.html'
html = index.read_text()
html, titles = re.subn(r'<title>.*?</title>', f'<title>{name}</title>', html, count=1)
if titles != 1:
    raise SystemExit('index.html carries no <title>, so the tab would keep theirs')
html = re.sub(
    r'(<meta name="apple-mobile-web-app-title" content=")[^"]*(")',
    rf'\g<1>{name}\g<2>',
    html,
)
data = base64.b64encode(favicon.encode()).decode()
html = re.sub(
    r'<link rel="icon"[^>]*>',
    f'<link rel="icon" type="image/svg+xml" href="data:image/svg+xml;base64,{data}">',
    html,
    count=1,
)
# The second icon link and the apple-touch ones point at files that still carry
# their artwork, so they are dropped rather than repointed.
html = re.sub(r'<link rel="icon" type="image/png"[^>]*>', '', html)
html = re.sub(r'<link rel="apple-touch-icon"[^>]*>', '', html)
index.write_text(html)

manifest = dist / 'manifest.json'
if manifest.is_file():
    m = json.loads(manifest.read_text())
    m['name'] = name
    m['short_name'] = name
    m['description'] = name
    m.pop('icons', None)
    manifest.write_text(json.dumps(m, indent=2))

(dist / 'favicon.svg').write_text(favicon)
for stale in (dist / 'favicon.png', dist / 'icons'):
    if stale.is_dir():
        for f in stale.iterdir():
            f.unlink()
        stale.rmdir()
    elif stale.exists():
        stale.unlink()

print(f'rebranded {dist} as {name}')
PY
