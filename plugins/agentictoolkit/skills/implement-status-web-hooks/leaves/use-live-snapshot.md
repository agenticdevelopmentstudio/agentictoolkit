<!-- leaf: implement-status-web-hooks/use-live-snapshot · source: status-web-hooks-use-live-snapshot.md -->

# useLiveSnapshot

## Overview

`useLiveSnapshot` (`packages/web/packages/status-web/src/hooks/use-live-snapshot.ts`) is the status dashboard's transport for the latest `LiveSnapshot` — "what did the last probe cycle see" (services, deployments, `lastCycleAt`, `probeIntervalMs`, `monitorVersion`, `configDegraded`). It is mounted by several views at once (the header pill, `OverviewTab`, `Dashboard`, `BoardShell`, the stale banners, `usePortfolioIndicator`), so its state lives in one store per `StatusApiClient`, not per component.

The primary feed is one ref-counted `EventSource` on `/live/stream`, over which the backend pushes a `snapshot` frame on every cycle and webhook plus a `schedule` frame with the next cycle time. The fallback is a React Query poll of `GET /live` every 60 s, gated off while the stream is connected. The hook also exposes a manual full check (`refresh`, `POST /live/check`) whose spinner holds until the user's own result lands, and a cheap reachability re-read (`reconnect`).

Per the module's header comment it "does NOT fold frames into a durable model any more"; the board (`useBoard`) answers "what is wrong" and piggybacks on this feed through `subscribeLiveFrames` rather than opening a second connection.

