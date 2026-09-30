<!-- leaf: implement-status-web-hooks/use-activity-history · source: status-web-hooks-use-activity-history.md -->

# useActivityHistory

## Overview

`useActivityHistory` is a React hook that manages the fetching and merging of historical activity rows beyond the live window, with built-in shed-row absorption and automatic pagination budget. It is used to expand a bounded live feed (capped at MAX_ACTIVITY_ROWS and floored 24h back) backward in time through a server-side cursor, re-ordering merged results by (at, id) comparator, and holding caught rows that age out of the live window during paging. The hook is enabled conditionally by an age-out filter and exposes methods to load older rows and reset the auto-fetch budget.

