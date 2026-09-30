<!-- leaf: implement-hub-domain-2/projects--logging · source: hub-domain-projects.md -->

# Hub Domain: Projects

## Logging

No file in this domain calls a logger, `console.log`, `console.warn`,
`console.error`, or any platform logging API. Every failure this component
detects (a thrown 404 mapped to `null`, an unrecognized `authorKind` mapped
to `"customer"`, a network error) is either resolved to a documented
fallback value or surfaced to the caller as a thrown `Error`; any logging of
that failure is the responsibility of the caller or host application, not
of this domain component.
