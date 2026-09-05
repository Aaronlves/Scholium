# Current Apple HIG Refresh — 2026-09-04

## Inventory

- Crawled 172 current canonical and collection records from Apple's HIG DocC source.
- Compared with the 2026-06-09 audited inventory: 172 slugs remain, no slugs were added, and four former same-source aliases now return HTTP 404.
- The removed aliases are `spatial-interactions`, `components/layout-and-organization/tab-views`, `components/presentation/page-controls`, and `components/system-experiences/complications`. Their canonical topics remain available as `nearby-interactions`, `tab-views`, `page-controls`, and `complications`; no distilled topic was removed.
- All 172 raw response hashes differ from the earlier inventory. Hash changes were therefore treated only as review signals, not as proof of semantic changes.
- Current rendered page changelogs contain no entry later than 2026-06-09.

## Current-source review

The HIG root currently highlights `menus`, `scroll-views`, `search-fields`, `sidebars`, `siri`, and `snippets` as new or updated. Those six pages and `design-principles` were compared with their distilled references.

- `menus`: added the current rule to use menu-item icons sparingly and purposefully for common actions, key features, clear locations or operations, connected devices, and user-created content.
- `search-fields`: removed a duplicated inline-search rule and restored the source-backed rule to place a top inline search field above its list and consider pinning it while scrolling.
- `scroll-views`, `sidebars`, `siri`, `snippets`, and `design-principles`: no distilled change required in this pass.

## Disposition boundary

- 7 records are marked `verified-current-source-review`.
- 150 records are marked `baseline-audit-carried-forward`: their prior full audit remains useful and no later page changelog was found, but this status does not claim a new full source-to-distillation comparison.
- 15 root or category pages remain `collection-only`.

This refresh deliberately avoids promoting changelog triage into full current-source verification.
