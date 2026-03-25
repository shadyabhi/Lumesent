#!/bin/bash
# Generate a Sparkle appcast XML file.
# Usage: generate-appcast.sh <output-file> <channel-title> <appcast-link> <item-title> <version> <dmg-url> <sparkle-sig> <pub-date>
set -euo pipefail

OUTPUT="$1"
CHANNEL_TITLE="$2"
APPCAST_LINK="$3"
ITEM_TITLE="$4"
VERSION="$5"
DMG_URL="$6"
SPARKLE_SIG="$7"
PUB_DATE="$8"

cat > "$OUTPUT" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>${CHANNEL_TITLE}</title>
    <link>${APPCAST_LINK}</link>
    <item>
      <title>${ITEM_TITLE}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure
        url="${DMG_URL}"
        ${SPARKLE_SIG}
        type="application/octet-stream" />
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    </item>
  </channel>
</rss>
EOF

echo "Generated $OUTPUT"
