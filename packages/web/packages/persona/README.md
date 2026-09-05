# @agentic-toolkit/persona

The single crossing point to `@agenticdevelopertoolkit/*`.

`agenticdevelopertoolkit` is a **separate product** that ships four web packages
(`avatar`, `chat`, `themes`, `viewport`). This package re-publishes the three of
them that consumers outside the persona itself need, so that **no consumer ever
names that scope directly**.

## Why the indirection exists

adh holds `agenticdevelopertoolkit` twice on disk — its own submodule, and the
one nested inside this repo:

```
frontend/src/external/agenticdevelopertoolkit                 ← adh's submodule
frontend/src/external/agentictoolkit
    └── external/agenticdevelopertoolkit                      ← this repo's
```

A bare specifier in a shipped `dist` resolves from the **importing file's real
path**, not from the consuming site. So a site that declares
`@agenticdevelopertoolkit/chat` itself resolves adh's copy, while anything it
reaches through this repo resolves the nested copy — and nothing dedupes across
two different directories. The site bundles both.

Equal submodule pins keep that merely wasteful (identical commits, identical
code). It turns into a real bug the moment the pins drift or a value crosses the
seam: `themes/src/colorMode.tsx` builds its React context at module scope, so a
provider on one copy and a consumer on the other never meet and `useColorMode`
throws — naming React in the stack trace rather than the boundary that caused it.

Importing from here removes the second path entirely. **One copy by
construction, not by two paths happening to coincide.**

## Usage

```ts
import { InlineChat, type ChatBackend } from '@agentic-toolkit/persona/chat'
import { ThemeStyle, themeIds } from '@agentic-toolkit/persona/themes'
import { ViewportShell } from '@agentic-toolkit/persona/viewport'
```

```css
@import '@agentic-toolkit/persona/css/chat/base.css';
@import '@agentic-toolkit/persona/css/chat/modes/inline.css';
```

The entries are separate on purpose: a consumer that only wants viewport
primitives does not pull chat and themes into its graph.

## A substitution that looks right and is not

- **`@agenticdevelopertoolkit/themes`** has an id set **disjoint** from the persona
  toolkit's (`old-school-terminal` exists only there). Swapping silently changes
  which themes exist and breaks every `theme` prop's type contract.

## Relationship to `@agentic-toolkit/bitbag`

bitbag is *a persona* — his voice, avatar rig and chat surface. It legitimately
names the persona scope because it renders it. This package is *infrastructure*:
the boundary itself. Consumers that want persona vocabulary without wanting
bitbag import from here, which is why `ViewportShell` lives behind this package
and not behind a re-export on a specific persona.

`<adh-tools>/sites/scripts/verify_persona_deps.py` enforces the rule from the
consuming side.
