<!-- leaf: implement-status-server-monitor-2/provider-deploy--logging · source: status-server-monitor-provider-deploy.md -->

# Status Server Monitor Provider Deploy

## Logging

Subsystem: `status-server` | Category: `provider-deploy`

| Event | Level | Message |
|-------|-------|---------|
| Invalid `Date` reaches `isoOf` (a legacy row's `createdAt`, or a `confirmedAt`/`createdAt` fallback that resolves to an Invalid Date) | error | `` [provider-deploy] ${id} carries an invalid createdAt — serializing as epoch `` |
