---
name: eagle-query-fetch-images
description: Query and retrieve images from an existing Eagle library through local Eagle API, including latest image lookup, keyword search, preview path resolution, and path-safe file retrieval. Use when users ask to find images in Eagle, fetch recent photos (e.g. "最近保存的2张照片"), or return image paths/previews from Eagle without importing new items.
---

# Eagle Query Fetch Images

## Overview

Use this skill to read from Eagle libraries when the current MCP workflow is write-focused.
Run a deterministic chain: search/list, select latest items, resolve preview paths, and return image results.

## Workflow

1. Confirm read-only scope and expected count.
2. Resolve Eagle API base URL from `.env` or probe local ports.
3. Query items via `GET /api/item/list`.
4. Sort by `modificationTime` and select top N.
5. Resolve preview paths with `GET /api/item/thumbnail?id=<id>`.
6. Return concise result list with `id`, `name`, `ext`, and `preview_path`.

## Quick Commands

Get latest 2 photos:

```bash
scripts/eagle-query-and-fetch.sh --latest 2 --photo-only
```

Search by keyword and return top previews:

```bash
scripts/eagle-query-and-fetch.sh --query "robot" --limit 20 --max-preview 5 --photo-only
```

## Rules

- Default to read-only actions.
- Prefer photo formats (`jpg`, `jpeg`, `png`, `webp`, `heic`) when `--photo-only` is set.
- Do not guess Eagle internal file layout.
- Use plugin bridge for original file path if required; use thumbnail path for preview retrieval.

## Output Contract

Return JSON fields:

- `query`
- `base_url`
- `search_count`
- `resolved_count`
- `items[]`: `id`, `name`, `ext`, `modificationTime`, `preview_path`

## References

- Read `references/eagle-api-retrieval.md` for retrieval design and tool contract.
- Use `scripts/eagle-query-and-fetch.sh` for deterministic execution.
