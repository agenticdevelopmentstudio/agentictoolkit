<!-- leaf: implement-hub-domain-2/profile · source: hub-domain-profile.md -->

# Hub Domain Profile

## Overview

`profile.ts` and `usage.ts`, re-exported together by `index.ts`, are the public surface of a
principal's profile domain: social links and addresses (owner-polymorphic rows a personal
account or an organization can each hold), the per-row privacy grant that decides who may see
them, and the caller's metered usage summary. `index.ts`'s own comment frames this as "one entry
for four endpoints because they answer about one subject and are read together." `wire.ts` holds
the wire shapes (`SocialLink`/`SocialLinkWrite`, `Address`/`AddressWrite`, `PrivacyGrant`,
`UsageRow`/`UsageLimits`) and is measured against the backend's generated types by
`data-profile-wire.test-d.ts` in a sibling package. It is a headless **logic** module — no visual
surface — so this recipe marks Appearance, States, and Accessibility not applicable and carries
the runtime contract entirely in Behavioral Requirements, per the non-UI component guidance this
recipe was authored under.

