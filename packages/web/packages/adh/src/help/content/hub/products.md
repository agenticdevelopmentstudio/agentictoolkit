# Products

The thing you are building has its own users, its own data, and its own
credentials — and none of that should be reachable by the next thing you build.
You also need somewhere to put the parts of a shipped product that are not code:
who has signed up, who is paying, which features are switched on for whom, and
the configuration you would otherwise redeploy to change.

## What it does

A product is an **ecosystem**: a boundary with its own settings, its own project,
and its own data. Inside one you manage:

- **Applications** — one per thing that talks to the Hub. Each carries API tokens
  scoped to this product and nothing else, and its own login registration: the
  client id your app signs *its* customers in through the Hub with. OAuth you do
  not have to build.
- **Users** — your product's customers: invitations, access requests, and pending
  members. These are not Hub users.
- **Email signup** — a waitlist or launch-notification capture, with the list
  behind it.
- **Billing** — offers your customers subscribe to, and who is on each one.
- **Feature flags** — runtime on/off toggles your app reads, targetable at a
  subset of customers.
- **Server bags** — key→JSON configuration your app reads at runtime, per
  ecosystem.
- **Gamification** — the character-sheet system: levels, badges, seasons, and
  leaderboards for your personas and your users.
- **Storage**, **integrations**, and **dashboards**, all scoped here.

## What you use it with

**A product plus an [application](/hub/products) plus a token is what your code
uses to get in.** The chain matters in that order: the token belongs to the
application, the application belongs to the product, and the product is what
bounds what the token can reach. A leaked token is a bad day, not a catastrophe,
because of the last link.

**A product plus a [project](/hub/plan) is what points an application at
something.** The project names the persona, the stores, and the status group that
ship together. Without it, an application is a credential with nothing on the
other end.

**Client auth plus [members](/hub/workspaces) is the distinction to get right.**
Members are people in *your workspace* — colleagues. Client auth serves people in
*your product* — customers. They sign in through different flows, appear in
different lists, and a customer never gains reach into your workspace.

**Feature flags plus billing is how a rollout usually actually looks.** A flag
targeted at an offer means paying customers get the new thing first. Either
feature alone gives you a switch or a subscriber list; together they give you a
release plan.

**Gamification plus a [persona](/hub/personas) is what turns a profile into a
character sheet.** Levels and badges attach to the persona you already
published, so the public profile gains a progression without you building one.

## In the demo

*Longtail Labs is the Agentic Developer Hub's documentation demo — a fictional
studio, not a real company.*

The studio ships two products, at deliberately different stages — Dognamr is
live, Shelterly is in early access with a handful of invited shelters:

![Dognamr and Shelterly side by side, their stages visibly different](https://agenticdeveloperhub.com/screenshots/products-list.png)

Opening Dognamr shows what a product actually contains — its applications, its
customers, and its flags on one screen:

![The Dognamr product, showing its applications, customers, and flags](https://agenticdeveloperhub.com/screenshots/product-dognamr.png)

Two applications reach it, and they are different kinds of thing. **Dognamr Web**
is the customer-facing site; **Dognamr CLI** is Casey's own tool. Both are
applications, and neither can read Shelterly:

![The Dognamr applications — Dognamr Web and Dognamr CLI, their consumer kinds differing](https://agenticdeveloperhub.com/screenshots/applications.png)

Dognamr's visitors sign in through the product's own login registration. These
are Casey's customers, not Hub users — the distinction most readers get wrong the
first time:

![Dognamr's client auth settings](https://agenticdeveloperhub.com/screenshots/auth.png)

Shelterly is not open yet, so its front page captures interest instead of
accounts:

![Dognamr's email signup capture, with signups against it](https://agenticdeveloperhub.com/screenshots/email-signup.png)

Dognamr Plus is the paid tier, with customers on it:

![The Dognamr Plus offer with paying customers against it](https://agenticdeveloperhub.com/screenshots/billing.png)

Casey's newest feature — uploading a photo to guess the breed — rolls out to
those subscribers first. That is the flag and the offer working together:

![A feature flag rolling out to Dognamr Plus subscribers first](https://agenticdeveloperhub.com/screenshots/feature-flags.png)

Everything else Dognamr needs at runtime and does not want to redeploy for lives
in its server bag, which differs from Shelterly's:

![Per-ecosystem server bag configuration for Dognamr and Shelterly](https://agenticdeveloperhub.com/screenshots/server-bags.png)

And Dognamr's visitors earn badges for naming dogs, which puts a leaderboard on a
product that is otherwise a text box:

![The Dognamr badge set and leaderboard](https://agenticdeveloperhub.com/screenshots/gamification.png)

## Where to go next

- [Storage & data](/hub/storage) — where a product's data actually sits.
- [Plan](/hub/plan) — the project an application points at.
- [Monitoring](/hub/monitoring) — watching a shipped product from one page.
- [APIs & agents](/hub/apis) — the token, and what it reaches.
