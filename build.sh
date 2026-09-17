#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CACHE="$ROOT/.cache"
DIST="$ROOT/dist"
DLC_DIR="$CACHE/domain-list-community"
GEOIP_DIR="$CACHE/geoip"
CUSTOM="$CACHE/geosite-data"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Нужна команда: $1" >&2
    exit 1
  }
}

need git
need go
need curl

mkdir -p "$CACHE" "$DIST"

clone_or_update() {
  local url="$1"
  local dir="$2"
  if [ ! -d "$dir/.git" ]; then
    git clone --depth 1 --branch master "$url" "$dir"
  else
    git -C "$dir" fetch --depth 1 origin master
    git -C "$dir" reset --hard origin/master
  fi
}

echo "==> domain-list-community"
clone_or_update "https://github.com/v2fly/domain-list-community.git" "$DLC_DIR"

echo "==> geoip compiler"
clone_or_update "https://github.com/v2fly/geoip.git" "$GEOIP_DIR"

rm -rf "$CUSTOM"
mkdir -p "$CUSTOM"

copy_with_deps() {
  local file="$1"
  if [ -f "$DLC_DIR/data/$file" ] && [ ! -f "$CUSTOM/$file" ]; then
    echo "    $file"
    cp "$DLC_DIR/data/$file" "$CUSTOM/"
    local dep
    while read -r dep; do
      [ -n "$dep" ] || continue
      copy_with_deps "$dep"
    done < <(grep -Eo "^include:[a-zA-Z0-9_-]+" "$DLC_DIR/data/$file" | cut -d':' -f2 || true)
  elif [ ! -f "$DLC_DIR/data/$file" ]; then
    echo "Нет категории в domain-list-community: $file" >&2
    exit 1
  fi
}

strip_line() {
  local line="${1%%#*}"
  # trim
  line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  printf '%s' "$line"
}

has_rules() {
  local path="$1"
  [ -f "$path" ] || return 1
  grep -vE '^\s*(#|$)' "$path" >/dev/null
}

echo "==> категории"
while IFS= read -r raw || [ -n "$raw" ]; do
  line="$(strip_line "$raw")"
  [ -z "$line" ] && continue
  copy_with_deps "$line"
done < "$ROOT/categories.txt"

echo "==> extra/"
if [ -d "$ROOT/extra" ]; then
  for f in "$ROOT/extra"/*; do
    [ -f "$f" ] || continue
    cp "$f" "$CUSTOM/$(basename "$f")"
  done
fi

if [ -f "$CUSTOM/category-ru" ] && [ -f "$ROOT/fold-into-category-ru.txt" ]; then
  echo "==> вшиваю теги в category-ru"
  while IFS= read -r raw || [ -n "$raw" ]; do
    tag="$(strip_line "$raw")"
    [ -z "$tag" ] && continue
    if has_rules "$CUSTOM/$tag"; then
      echo "include:$tag" >> "$CUSTOM/category-ru"
      echo "    include:$tag"
    fi
  done < "$ROOT/fold-into-category-ru.txt"
fi

echo "==> geosite.dat"
(
  cd "$DLC_DIR"
  go run . --datapath "$CUSTOM" --outputdir "$DIST" --outputname geosite.dat
)

echo "==> geoip.dat"
mkdir -p "$GEOIP_DIR/custom-ips"
curl -fsSL "https://raw.githubusercontent.com/v2fly/geoip/release/text/ru.txt" -o "$GEOIP_DIR/custom-ips/ru.txt"
curl -fsSL "https://raw.githubusercontent.com/v2fly/geoip/release/text/private.txt" -o "$GEOIP_DIR/custom-ips/private.txt"

cat > "$GEOIP_DIR/custom-config.json" <<'EOF'
{
  "input": [
    { "type": "text", "action": "add", "args": { "name": "ru", "uri": "custom-ips/ru.txt" } },
    { "type": "text", "action": "add", "args": { "name": "private", "uri": "custom-ips/private.txt" } }
  ],
  "output": [
    { "type": "v2rayGeoIPDat", "action": "output", "args": { "outputName": "geoip.dat", "outputDir": "output" } }
  ]
}
EOF

(
  cd "$GEOIP_DIR"
  go run . -c custom-config.json
)

cp "$GEOIP_DIR/output/dat/geoip.dat" "$DIST/geoip.dat" 2>/dev/null || cp "$GEOIP_DIR/output/geoip.dat" "$DIST/geoip.dat" 2>/dev/null || cp "$GEOIP_DIR/geoip.dat" "$DIST/geoip.dat"

echo
echo "Готово:"
ls -lh "$DIST"/geosite.dat "$DIST"/geoip.dat
