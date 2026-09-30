<!-- leaf: implement-status-web-hooks/use-deploy-projects--edge-cases · source: status-web-hooks-use-deploy-projects.md -->

# useDeployProjects

**Rules** (cite as `implement-status-web-hooks/use-deploy-projects--edge-cases#<slug>`):

- `non-ok-status` MUST — Any status outside 200–299 (including 401, 404, 502) MUST reject with the status-only message; the response body is not …
- `malformed-json-body-on-ok-response` MUST — r.json() rejects with the platform's SyntaxError, which MUST propagate unchanged as the helper's rejection (and as the …
- `well-formed-json-of-the-wrong-shape` MUST — The body MUST be returned as-is with no validation (see response-cast-unvalidated); a missing projects array reaches …
- `missing-verifiedplatforms` MUST — The field is optional; consumers MUST treat every wiring as live (verified-platforms-absent).
- `empty-projects-array` MUST — MUST resolve normally with an empty list.
- `network-failure-or-unreachable-server` MUST — The rejection from api.fetch (for example a TypeError) MUST propagate unchanged; no retry happens inside the helper, …
- `timeout` MUST — The module sets no timeout; a hanging request MUST stay pending until the platform or the host's fetch gives up.
- `cancellation` MUST — The query function does not forward React Query's abort signal to api.fetch; a cancelled query's request MUST keep …
- `several-queryclients-in-one-page` MUST — The latch is module-scoped, so the first successful fetch in any client MUST disarm it for all.

## Edge Cases

- **Non-ok status**: Any status outside 200–299 (including 401, 404, 502) MUST reject with the status-only message; the response body is not read, so any server error detail is dropped from the message.
- **Malformed JSON body on ok response**: `r.json()` rejects with the platform's `SyntaxError`, which MUST propagate unchanged as the helper's rejection (and as the hook's query error); for the hook the latch stays armed.
- **Well-formed JSON of the wrong shape**: The body MUST be returned as-is with no validation (see response-cast-unvalidated); a missing `projects` array reaches callers undefined.
- **Missing `verifiedPlatforms`**: The field is optional; consumers MUST treat every wiring as live (verified-platforms-absent).
- **Empty `projects` array**: MUST resolve normally with an empty list.
- **Network failure or unreachable server**: The rejection from `api.fetch` (for example a `TypeError`) MUST propagate unchanged; no retry happens inside the helper, and the hook defers retries to the `QueryClient`.
- **Timeout**: The module sets no timeout; a hanging request MUST stay pending until the platform or the host's fetch gives up.
- **Cancellation**: The query function does not forward React Query's abort signal to `api.fetch`; a cancelled query's request MUST keep running, and if it succeeds it still disarms the latch.
- **Arm during an in-flight fetch**: The arm is lost when that fetch succeeds; see the open question on latch-arm-during-flight.
- **Several QueryClients in one page**: The latch is module-scoped, so the first successful fetch in any client MUST disarm it for all.
- **Server-side rendering**: The module is `"use client"`; its latch is initialized per client realm on load.
- **Offline**: No offline handling exists; requests fail as network failures.
