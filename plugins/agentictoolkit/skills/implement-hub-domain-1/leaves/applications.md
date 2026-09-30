<!-- leaf: implement-hub-domain-1/applications · source: hub-domain-applications.md -->

# Hub Domain Applications

## Overview

Three Swift files under `packages/apple/AgenticToolkit/Hub/Features/Applications/` form the
client-side contract for the Hub's "Applications" product topic: `ApplicationsDataSource`
(`ApplicationsDataSource.swift`) is the `AnyObject, Sendable` protocol every network call is
delegated to; `ApplicationsModels.swift` holds the `Codable`/`Sendable` wire types (`Application`,
`ApplicationCreate`, `ApplicationUpdate`, `ConsumerKind`, `ApplicationToken`,
`ApplicationTokenCreated`) plus the domain-only, deliberately non-`Codable` grant types
(`CrudPermissions`, `TableGrant`, `SchemaGrant`); and `ApplicationsTopic`
(`ApplicationsTopic.swift`) is the `@MainActor` `EcosystemTopicProvider` that resolves the rail
path into list/detail panes for an application's Settings, Bucket permissions, and Access tokens
sections, using an injected `BucketsDataSource` to label and enumerate the buckets/tables a grant
can target. Every thrown error is normalized to `HubError` before it reaches a caller
(`HubError.wrap`), and every token secret this component ever holds is a transient,
reveal-once-then-drop entry in an in-memory dictionary — the same pattern the sibling
Authentication feature (`agentictoolkit://recipes/auth-client-authentication`) uses for its own
API and storage tokens.

