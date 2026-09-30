<!-- leaf: implement-hub-domain-1/messaging · source: hub-domain-messaging.md -->

# Hub Domain Messaging

## Overview

Two Swift files under `packages/apple/AgenticToolkit/Hub/Features/Messaging/` form the
client-side contract for the Hub's "Messaging" product topic: `MessagingModels.swift` holds
the `Codable`/`Sendable` wire types (`MessagingChannel`, `MessagingStatus`, `MessagingTemplate`,
`MessagingLogEntry`, `MessagingLogPage`, `MessagingSend`, `MessagingSendResult`) plus the
`MessagingDataSource` protocol every network call is delegated to; and `MessagingTopic`
(`MessagingTopic.swift`) is the `@MainActor` `EcosystemTopicProvider` that resolves the rail
path into a "Send a message" compose form and a "Message log" list/detail pair, using the
injected data source for provider-connectivity status, template listing, log paging, and the
send call itself. Every thrown error from `templates()`, `log(...)`, and `send(...)` is
normalized to `HubError` before it reaches a caller (`HubError.wrap`); a `status(...)` failure is
the one exception, deliberately swallowed to a degraded-but-usable banner rather than propagated.

