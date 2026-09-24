# Workspaces & account

Work that matters stops being one person's fairly quickly. Someone else needs to
see the agent's configuration, change a prompt, or keep shipping while you are
away — and the answer cannot be sharing your password. You need a place the work
belongs to rather than a place you own, with people in it who have their own
accounts and their own level of reach.

## What it does

- **Switch workspaces** — your personal workspace and every organization you
  belong to, from one control. Create a new organization from Home.
- **Members** — the roster of people in an organization, and what each one may
  do. An owner can change billing and remove people; a member cannot.
- **Invitations** — invite by email, see who has not accepted yet, and withdraw
  an invitation that was sent in error.
- **Settings** — appearance, account, security, subscription, your public
  profile, and notifications, plus the organization's own name and description.
- **API tokens** — mint, list, and revoke tokens that reach your data. Each one
  can reach the workspace's storage buckets.

## What you use it with

**A workspace plus [members](/hub/workspaces) is what makes a persona
survivable.** A persona configured in a personal workspace is configured by one
person who may leave. Moved into an organization, the same persona has a roster
behind it, and the prompt that runs your product is not hostage to one account.

**Members plus [teams](/hub/teams) is what makes access legible.** Roles say what
someone may do; teams say what they are working on. A ten-person organization
with no teams is ten people who all see everything, which stops being useful long
before it stops being safe.

**A token plus an [application](/hub/products) is what makes your code able to
reach any of this.** A token minted here is scoped, and the thing it is scoped to
is the application inside a product. That is the difference between a credential
your code carries and a credential that would be a problem if it leaked.

**Your account plus a [public profile](/hub/teams) is how you appear elsewhere.**
The profile in Settings is what other Hub users see in a member directory, a
discussion thread, or beside a team you helped build.

## In the demo

*Longtail Labs is the Agentic Developer Hub's documentation demo — a fictional
studio, not a real company.*

Longtail Labs has two people in it, and deliberately not two owners. Casey Rowan
owns the organization; Priya Anand is a member:

![The Longtail Labs member roster — Casey as owner, Priya as member](https://agenticdeveloperhub.com/screenshots/members.png)

That difference is the whole reason the roster exists. Priya can edit personas,
write to storage, and ship; Priya cannot change the subscription or remove Casey.

A third invitation is outstanding. Tomas Ferreira was invited and has not
accepted, which is what a pending row looks like — not an error, just a person
who has not clicked the link yet:

![The invitations screen showing Tomas Ferreira, pending](https://agenticdeveloperhub.com/screenshots/invitations.png)

The organization's own settings carry its name, description, and the line
identifying it as this documentation's demo:

![Longtail Labs workspace settings](https://agenticdeveloperhub.com/screenshots/settings.png)

## Where to go next

- [Teams](/hub/teams) — grouping the people on this roster, and the personas that
  stand among them.
- [Products](/hub/products) — the boundary that tokens are scoped to.
- [APIs & agents](/hub/apis) — what a token can actually reach.
