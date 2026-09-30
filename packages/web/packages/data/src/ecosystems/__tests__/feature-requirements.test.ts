import { describe, it, expect } from 'vitest'
import type { CatalogFeature } from '../ecosystem-features'
import {
  listedCatalog,
  listedFeatureKey,
  requiredClosure,
  neededBy,
  neededByMessage,
} from '../feature-requirements'

const feature = (
  key: string,
  label: string,
  requiresFeatures?: string[],
  includedWith?: string,
): CatalogFeature =>
  ({
    key,
    label,
    description: `${label} does things.`,
    subscriptionTier: 'Free',
    ...(requiresFeatures ? { requiresFeatures } : {}),
    ...(includedWith ? { includedWith } : {}),
  }) as CatalogFeature

// signin-apps -> users -> user-authentication: a chain, not a flat list, so a closure
// helper that only reads its own key's `requiresFeatures` would miss the transitive hop.
const CHAIN = [
  feature('user-authentication', 'User Authentication'),
  feature('users', 'Users', ['user-authentication']),
  feature('signin-apps', 'Client Auth', ['users']),
]

describe('requiredClosure', () => {
  it('is transitive: a requires b, b requires c => closure(a) includes c', () => {
    expect(requiredClosure('signin-apps', CHAIN)).toEqual(
      expect.arrayContaining(['users', 'user-authentication']),
    )
  })

  it('is empty for a feature that requires nothing', () => {
    expect(requiredClosure('user-authentication', CHAIN)).toEqual([])
  })

  it('does not loop forever on a cycle', () => {
    const cyclic = [feature('a', 'A', ['b']), feature('b', 'B', ['a'])]
    expect(requiredClosure('a', cyclic)).toEqual(expect.arrayContaining(['b']))
  })
})

describe('neededBy', () => {
  it('only counts features currently ON', () => {
    // signin-apps requires users, but signin-apps is OFF: users is needed by nothing.
    expect(neededBy('users', CHAIN, () => false)).toEqual([])
  })

  it('counts a feature that is on and directly requires the key', () => {
    const isOn = (k: string) => k === 'signin-apps'
    const blockers = neededBy('users', CHAIN, isOn)
    expect(blockers.map((f) => f.key)).toEqual(['signin-apps'])
  })

  it('is transitive: an ON feature two hops away still counts', () => {
    // signin-apps (on) requires users requires user-authentication: removing
    // user-authentication is blocked by signin-apps even though signin-apps
    // never lists it directly.
    const isOn = (k: string) => k === 'signin-apps'
    const blockers = neededBy('user-authentication', CHAIN, isOn)
    expect(blockers.map((f) => f.key)).toEqual(['signin-apps'])
  })

  it('ignores an ON feature whose requirement is unrelated to the key', () => {
    const isOn = (k: string) => k === 'user-authentication'
    expect(neededBy('users', CHAIN, isOn)).toEqual([])
  })
})

describe('neededByMessage', () => {
  it('names the blocking labels verbatim', () => {
    expect(neededByMessage(['Client Auth'])).toBe('this feature is needed by Client Auth features')
  })

  it('joins more than one label with a comma', () => {
    expect(neededByMessage(['Client Auth', 'Billing'])).toBe(
      'this feature is needed by Client Auth, Billing features',
    )
  })
})

// The backend's shape (Mike, 2026-09-29): User Authentication and Email Signup come with Users,
// Client Auth with Applications, Storage Access Tokens with Storage.
const INCLUDED = [
  feature('users', 'Users', ['feature-flags']),
  feature('user-authentication', 'User Authentication', ['users'], 'users'),
  feature('email-signup', 'Email Signup', ['users'], 'users'),
  feature('applications', 'Applications'),
  feature('signin-apps', 'Client Auth', ['users', 'user-authentication', 'server-bags'], 'applications'),
  feature('storage', 'Storage'),
  feature('storage-access-tokens', 'Storage Access Tokens', ['storage'], 'storage'),
  feature('feature-flags', 'Feature Flags'),
  feature('server-bags', 'Server Bags'),
]

describe('listedFeatureKey', () => {
  it('is the key itself for a listed feature', () => {
    expect(listedFeatureKey('users', INCLUDED)).toBe('users')
  })

  it('is the feature it comes with for an included one', () => {
    expect(listedFeatureKey('signin-apps', INCLUDED)).toBe('applications')
    expect(listedFeatureKey('user-authentication', INCLUDED)).toBe('users')
  })

  it('does not loop forever on an includedWith cycle', () => {
    const cyclic = [feature('a', 'A', undefined, 'b'), feature('b', 'B', undefined, 'a')]
    expect(['a', 'b']).toContain(listedFeatureKey('a', cyclic))
  })
})

describe('listedCatalog', () => {
  it('lists no feature that comes with another', () => {
    expect(listedCatalog(INCLUDED).map((f) => f.key)).toEqual([
      'users',
      'applications',
      'storage',
      'feature-flags',
      'server-bags',
    ])
  })

  it("gives the parent what its included features require, named by the listed key", () => {
    const apps = listedCatalog(INCLUDED).find((f) => f.key === 'applications')
    expect([...(apps?.requiresFeatures ?? [])].sort()).toEqual(['server-bags', 'users'])
  })

  it('never makes a feature require itself', () => {
    const users = listedCatalog(INCLUDED).find((f) => f.key === 'users')
    expect(users?.requiresFeatures).toEqual(['feature-flags'])
    const storage = listedCatalog(INCLUDED).find((f) => f.key === 'storage')
    expect(storage?.requiresFeatures ?? []).toEqual([])
  })

  it("so Users cannot go while Applications is on", () => {
    const listed = listedCatalog(INCLUDED)
    expect(neededBy('users', listed, (k) => k === 'applications').map((f) => f.key)).toEqual([
      'applications',
    ])
  })
})
