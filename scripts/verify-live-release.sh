#!/usr/bin/env bash
set -euo pipefail

FEED_URL="${SHOUTOUT_FEED_URL:-https://shoutout.sh/appcast.xml}"
DOWNLOAD_URL="${SHOUTOUT_VERIFY_DOWNLOAD_URL:-https://shoutout.sh/download?source=verify}"
PYTHON_BIN="${PYTHON_BIN:-${PYTHON:-python3}}"

for tool in curl "$PYTHON_BIN"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

appcast_path="$temp_dir/appcast.xml"
asset_headers_path="$temp_dir/asset-headers.txt"

curl --fail --silent --show-error --retry 3 --retry-all-errors "$FEED_URL" -o "$appcast_path"

read -r version build enclosure_url expected_length < <(
  "$PYTHON_BIN" - "$appcast_path" <<'PY'
import sys
import xml.etree.ElementTree as ET

sparkle = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
item = ET.parse(sys.argv[1]).getroot().find("./channel/item")
if item is None:
    raise SystemExit("Appcast has no release item")

enclosure = item.find("enclosure")
if enclosure is None:
    raise SystemExit("Appcast release has no enclosure")

version = item.findtext(f"{sparkle}shortVersionString", "").strip()
build = item.findtext(f"{sparkle}version", "").strip()
url = enclosure.attrib.get("url", "").strip()
length = enclosure.attrib.get("length", "").strip()

if not version or not build or not url.startswith("https://") or not length.isdigit():
    raise SystemExit("Appcast release metadata is incomplete")

print(version, build, url, length)
PY
)

effective_download_url="$(
  curl --fail --silent --show-error --head --location --retry 3 --retry-all-errors \
    --output /dev/null --write-out '%{url_effective}' "$DOWNLOAD_URL"
)"
if [[ "$effective_download_url" != "$enclosure_url" ]]; then
  echo "Download redirect mismatch" >&2
  echo "  appcast: $enclosure_url" >&2
  echo "  download: $effective_download_url" >&2
  exit 1
fi

curl --fail --silent --show-error --head --location --retry 3 --retry-all-errors \
  "$enclosure_url" -o "$asset_headers_path"

actual_length="$(
  awk 'tolower($1) == "content-length:" { gsub("\\r", "", $2); value = $2 } END { print value }' \
    "$asset_headers_path"
)"
content_type="$(
  awk 'tolower($1) == "content-type:" { gsub("\\r", "", $2); value = $2 } END { print value }' \
    "$asset_headers_path"
)"

if [[ "$actual_length" != "$expected_length" ]]; then
  echo "Release asset length mismatch: appcast=$expected_length live=${actual_length:-missing}" >&2
  exit 1
fi

case "$content_type" in
  application/x-apple-diskimage|application/octet-stream) ;;
  *)
    echo "Unexpected release content type: ${content_type:-missing}" >&2
    exit 1
    ;;
esac

echo "ok - live ShoutOut $version build $build is downloadable ($actual_length bytes)"
