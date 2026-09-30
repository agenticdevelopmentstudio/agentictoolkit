<!-- leaf: implement-hub-domain-2/teams--logging · source: hub-domain-teams.md -->

# Hub Domain: Teams

## Logging

No file in this domain calls a logger, `console.log`, `console.warn`,
`console.error`, or any platform logging API. Every failure this component
detects is either resolved to a documented fallback (`teamsApi.get`'s
`null`) or surfaced to the caller as a thrown `Error`; logging that failure
is the responsibility of the caller or host application, not of this
domain component.
