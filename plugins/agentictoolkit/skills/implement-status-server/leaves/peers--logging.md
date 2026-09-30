<!-- leaf: implement-status-server/peers--logging · source: status-server-peers.md -->

# Status Server Peers

## Logging

None of the three files calls `console.*` or any logger; `fetchPeers` and `fleet.ts` communicate every outcome — success, HTTP failure, thrown error, or missing snapshot — through their return values and the `peer_snapshots` rows they write, never through a log line.
