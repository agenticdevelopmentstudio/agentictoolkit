// Type-level verification of the contract helpers — validated by `tsc --noEmit`
// (`pnpm test`). Every entry in `Checks` must be exactly `true` (via Expect<…>),
// and each `@ts-expect-error` line fails to compile if the error it expects does
// NOT occur (an unused @ts-expect-error is itself a tsc error). So a regression in
// a guard — RequestBody resolving to `never`/`any`, a server-managed column
// leaking into a create body, a wrong nullability — turns this file red. This is
// how the type guards are proven to catch what they claim to.
import type { RequestBody, SuccessBody } from './index'

// ── assertion utilities ──────────────────────────────────────────────────────
type Expect<T extends true> = T
type Equal<A, B> =
  (<T>() => T extends A ? 1 : 2) extends (<T>() => T extends B ? 1 : 2) ? true : false
type Extends<A, B> = A extends B ? true : false
type HasKey<T, K extends PropertyKey> = K extends keyof T ? true : false
type IsNever<T> = [T] extends [never] ? true : false
type IsAny<T> = 0 extends 1 & T ? true : false

type Customers = SuccessBody<'/customer/customers', 'get'>
// Customer create body — exercises the same server-managed-column stripping that
// the old /system/feature-flags tests covered (id/createdAt/updatedAt absent from body).
type CustomerCreate = RequestBody<'/customer/customers', 'post'>

// Exported so the assertions are referenced (never dead-stripped); any `false`
// element fails its `Expect<… extends true>` and breaks the build.
export type Checks = [
  // ── SuccessBody (response side) ──
  Expect<Extends<Customers, unknown[]>>, //                 a list resolves to an array
  Expect<Equal<Customers[number]['id'], string>>,
  // nullability is preserved (the property that caught the admin email/userEmail bug):
  Expect<Equal<Customers[number]['email'], string | null>>,
  Expect<HasKey<SuccessBody<'/customer/customers', 'post', 201>, 'id'>>, // status-keyed
  Expect<Equal<IsNever<Customers>, false>>,
  Expect<Equal<IsAny<Customers>, false>>,

  // ── RequestBody (request side) ──
  Expect<HasKey<CustomerCreate, 'email'>>, //               writable columns present
  Expect<HasKey<CustomerCreate, 'displayName'>>,
  Expect<Equal<HasKey<CustomerCreate, 'id'>, false>>, //    server-managed columns stripped
  Expect<Equal<HasKey<CustomerCreate, 'createdAt'>, false>>,
  Expect<Equal<HasKey<CustomerCreate, 'updatedAt'>, false>>,
  Expect<Equal<IsNever<CustomerCreate>, false>>,
  Expect<Equal<IsAny<CustomerCreate>, false>>,
]

// a valid create payload compiles:
const okCustomer: CustomerCreate = { email: 'test@example.com', slug: 'test' }
void okCustomer

// @ts-expect-error — `bogus` is not a writable column; the guard must reject it.
const badCustomer: CustomerCreate = { email: 'x@x.com', slug: 'x', bogus: 1 }
void badCustomer

// a partial update (PUT) accepts a subset of the writable columns:
const patch: Partial<RequestBody<'/customer/customers/{id}', 'put'>> = { email: 'new@example.com' }
void patch
