# Eagle API Retrieval

## Goal

Retrieve existing images from Eagle by search or latest-first selection.

## Chain

1. `GET /api/item/list`
2. Sort by `modificationTime` descending
3. `GET /api/item/thumbnail?id=<item_id>` for each selected item

## Notes

- Use thumbnail path for fast image handoff.
- Keep read-only by default.
- If Eagle API is unreachable, return actionable error and stop.

## Minimal Tool Mapping

- `search_items(query, limit, offset, photo_only)`
- `get_latest_images(count, photo_only)`
- `get_item_preview_path(id)`
