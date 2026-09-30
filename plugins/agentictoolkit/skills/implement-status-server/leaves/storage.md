<!-- leaf: implement-status-server/storage · source: status-server-storage.md -->

# Status Server Storage Boundary

## Overview

The storage boundary defines plain-domain-type interfaces through which every consumer (routes, monitor, board, MCP tools, peers, telemetry) reads and writes. The boundary accepts only domain types (no query builders, driver clients, or schema aliases); its libSQL/SQLite implementation is the sole adapter permitted to speak to the driver. Storage composes 13 specialized stores (Config, Auth, Token, Health, Deploy, Issues, Observations, Maintenance, Board, History, Device, Peer, Telemetry) into one object threaded through `createApp`.

