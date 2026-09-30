<!-- leaf: implement-hub-domain-1/customers · source: hub-domain-customers.md -->

# Hub Domain: Customers

## Overview

The Customers domain is the Hub's management of an ecosystem's end users
(rows of `/customer/customers`). It is three cooperating pieces:

- **`CustomersDataSource`** (`CustomersDataSource.swift`) — the protocol
  through which the Customers topic reaches the server: list/get/create/
  update/delete, a single flat CRUD surface with no nested child resource.
- **The data shapes** (`CustomersModels.swift`) — `Customer` and
  `CustomerInput`, the `Codable` payloads the data source sends and
  receives.
- **`CustomersTopic`** (`CustomersTopic.swift`) — the `EcosystemTopicProvider`
  that renders this domain into the Hub's rail/detail (HTDV) navigation: a
  users list and the create/edit/delete form for a single user.
  `CustomersTopic` builds on the HTDV navigation and Forms types
  (`HTDVLevel`, `HTDVItem`, `HTDVChild`, `HTDVDetail`, `FormSpec`,
  `FormAction`, `FormDeleteAction`, and the rest) documented in the related
  HTDV Engine recipe; those types are not redescribed here.

`FormSheet`, `FormDetails`, `RailPath`, `HubError`, `HubText`,
`EcosystemTopicProvider`, `EcosystemRail`, and `Ecosystem` are Hub-wide
helpers `CustomersTopic` is built on but that are not among this recipe's
three given sources; they are described here only to the extent needed to
state what `CustomersTopic` itself does with them.

The rail label for this topic is "Users" (`entry.label`, and the list
level's own `title`), and its two user-facing action verbs are "New user"
and "Delete user" — but the type and protocol names throughout the three
given sources are `Customer`/`CustomerInput`/`CustomersDataSource`. This
recipe follows the source exactly: "customer" is used for the type- and
field-level vocabulary, and "user" only where the source's own string
literals themselves say "user."

