#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${SKILL_DIR}/.env" ]]; then
  # shellcheck disable=SC1090
  source "${SKILL_DIR}/.env"
fi

BASE_URL="${EAGLE_API_BASE_URL:-}"
QUERY=""
LIMIT=20
OFFSET=0
MAX_PREVIEW=5
LATEST=0
PHOTO_ONLY=0

usage() {
  cat <<USAGE
Usage: $0 [--query <keyword>] [--latest N] [--limit N] [--offset N] [--max-preview N] [--photo-only]

Examples:
  $0 --latest 2 --photo-only
  $0 --query "robot" --limit 20 --max-preview 5 --photo-only
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --query|-q)
      QUERY="${2:-}"
      shift 2
      ;;
    --latest)
      LATEST="${2:-0}"
      shift 2
      ;;
    --limit)
      LIMIT="${2:-20}"
      shift 2
      ;;
    --offset)
      OFFSET="${2:-0}"
      shift 2
      ;;
    --max-preview)
      MAX_PREVIEW="${2:-5}"
      shift 2
      ;;
    --photo-only)
      PHOTO_ONLY=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! [[ "$LIMIT" =~ ^[0-9]+$ && "$OFFSET" =~ ^[0-9]+$ && "$MAX_PREVIEW" =~ ^[0-9]+$ && "$LATEST" =~ ^[0-9]+$ ]]; then
  echo "limit/offset/max-preview/latest must be non-negative integers" >&2
  exit 1
fi

if [[ -z "$QUERY" && "$LATEST" -eq 0 ]]; then
  echo "Either --query or --latest must be provided" >&2
  exit 1
fi

probe_base_url() {
  local candidates=()
  if [[ -n "$BASE_URL" ]]; then
    candidates+=("$BASE_URL")
  else
    candidates+=(
      "http://127.0.0.1:41595/api"
      "http://127.0.0.1:41596/api"
      "http://localhost:41595/api"
      "http://localhost:41596/api"
    )
  fi

  local c
  for c in "${candidates[@]}"; do
    if curl -sS --max-time 3 "${c}/item/list?limit=1" >/dev/null 2>&1; then
      BASE_URL="$c"
      return 0
    fi
  done
  return 1
}

if ! probe_base_url; then
  printf '{"query":"%s","error":"EAGLE_API_UNREACHABLE","hint":"start Eagle API or set EAGLE_API_BASE_URL"}\n' "$QUERY"
  exit 2
fi

url_encode() {
  python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$1"
}

search_url="${BASE_URL}/item/list?limit=${LIMIT}&offset=${OFFSET}"
if [[ -n "$QUERY" ]]; then
  search_url+="&keyword=$(url_encode "$QUERY")"
fi

search_json="$(curl -sS --max-time 20 "$search_url")"

BASE_URL_PY="$BASE_URL" SEARCH_JSON="$search_json" QUERY_PY="$QUERY" LATEST_PY="$LATEST" MAX_PREVIEW_PY="$MAX_PREVIEW" PHOTO_ONLY_PY="$PHOTO_ONLY" python3 - <<'PY'
import json
import os
import urllib.parse
import urllib.request

base_url = os.environ.get("BASE_URL_PY", "")
query = os.environ.get("QUERY_PY", "")
raw = os.environ.get("SEARCH_JSON", "")
latest = int(os.environ.get("LATEST_PY", "0"))
max_preview = int(os.environ.get("MAX_PREVIEW_PY", "5"))
photo_only = os.environ.get("PHOTO_ONLY_PY", "0") == "1"
photo_exts = {"jpg", "jpeg", "png", "webp", "heic"}

try:
    payload = json.loads(raw)
except json.JSONDecodeError:
    print(json.dumps({"query": query, "base_url": base_url, "error": "INVALID_SEARCH_RESPONSE"}, ensure_ascii=False))
    raise SystemExit(0)

items = payload.get("data") or []
if not isinstance(items, list):
    print(json.dumps({"query": query, "base_url": base_url, "error": "UNEXPECTED_DATA_SHAPE"}, ensure_ascii=False))
    raise SystemExit(0)

if photo_only:
    items = [x for x in items if str(x.get("ext", "")).lower() in photo_exts]

items.sort(key=lambda x: int(x.get("modificationTime", 0) or 0), reverse=True)

if latest > 0:
    selected = items[:latest]
else:
    selected = items[:max_preview]

resolved = []
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
for item in selected[:max_preview if latest == 0 else latest]:
    item_id = str(item.get("id", ""))
    name = str(item.get("name", ""))
    ext = str(item.get("ext", ""))
    mtime = int(item.get("modificationTime", 0) or 0)
    preview_path = ""
    if item_id:
      thumb_url = f"{base_url}/item/thumbnail?id={urllib.parse.quote(item_id)}"
      try:
          with opener.open(thumb_url, timeout=20) as resp:
              thumb_payload = json.loads(resp.read().decode("utf-8", errors="replace"))
              raw_path = thumb_payload.get("data")
              if isinstance(raw_path, str):
                  preview_path = urllib.parse.unquote(raw_path)
      except Exception:
          preview_path = ""

    resolved.append({
        "id": item_id,
        "name": name,
        "ext": ext,
        "modificationTime": mtime,
        "preview_path": preview_path,
    })

print(json.dumps({
    "query": query,
    "base_url": base_url,
    "search_count": len(items),
    "resolved_count": len(resolved),
    "items": resolved,
}, ensure_ascii=False))
PY
