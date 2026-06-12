---
description: Soft-delete pattern used across all Pulse Energy projects
paths: ["**/*.ts", "**/*.tsx", "**/*.js"]
priority: high
---
# Soft-Delete Pattern

- All Pulse Energy projects use a `deleted` boolean flag instead of hard deletion
- When querying data, always filter by `deleted: false` (or `deleted: { not: true }`) unless explicitly told otherwise
- When "deleting" records, set `deleted: true` — never use Prisma `delete()` or `deleteMany()` on production models
- Always check for the soft-delete filter in existing queries before modifying them
