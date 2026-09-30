<!-- leaf: implement-status-server-monitor-2/worker-client--logging · source: status-server-monitor-worker-client.md -->

# Status Server Monitor Worker Client

## Logging

This file makes no logging call of its own — no `console.log`, no `console.error`, and no structured logger. Every failure it produces surfaces exclusively as a rejected `Promise` to its caller (see Behavioral Requirements and Localization); it is the caller's responsibility to log or alert on that rejection.

| Event | Level | Message |
|-------|-------|---------|
| n/a | n/a | This file emits no log output at any level. |
