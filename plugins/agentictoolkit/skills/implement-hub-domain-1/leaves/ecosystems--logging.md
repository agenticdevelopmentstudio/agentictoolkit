<!-- leaf: implement-hub-domain-1/ecosystems--logging · source: hub-domain-ecosystems.md -->

# Hub Domain: Ecosystems

## Logging

No file in either implementation calls a logger, `console.log`,
`console.warn`, `console.error`, or any platform logging API. Every
failure this component detects is surfaced to its caller as a thrown
`HubError` (Apple) or `Error`/`AuthHttpError` (web); any logging of that
failure is the responsibility of the caller or host application, not of
this domain component.
