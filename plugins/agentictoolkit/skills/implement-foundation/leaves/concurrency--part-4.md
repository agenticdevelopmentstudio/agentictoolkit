<!-- leaf: implement-foundation/concurrency--part-4 · source: foundation-concurrency.md -->

# BlockingWork, KeyedDebouncer & PendingTeardowns — continued (part 4)

**Rules** (cite as `implement-foundation/concurrency--part-4#<slug>`):

- `decision` MUST — KeyedDebouncer.finishRun calls onFailure?(key, error) unconditionally, before it checks whether an entry for that key …
- `decision-2` MUST — KeyedDebouncer reports failures through an optional onFailure callback, while PendingTeardowns.Teardown provides no …
- `decision-3` SHOULD — KeyedDebouncer.armTimer/beginRun capture [weak self], so a KeyedDebouncer instance that is deallocated while work is …

## Design Decisions

**Decision**: `KeyedDebouncer.finishRun` calls `onFailure?(key, error)` unconditionally, before it checks whether an entry for that key still exists.
**Rationale**: This means a caller who calls `cancel(key:)` while that key's work is in flight, and whose `work` closure subsequently throws (for instance because it observed the cancellation and threw), MUST still receive an `onFailure` callback naming a key that caller already explicitly cancelled — see `failure-callback-invoked-even-if-canceled` above. The code makes no attempt to suppress this: `finishRun`'s existence guard runs strictly after the `onFailure` call. Reporting every thrown error unconditionally is evidently favored over consistency with the cancelled state, since the alternative — checking entry existence first — would require reordering two lines that currently have no comment explaining the choice either way.
**Approved**: pending

**Decision**: `KeyedDebouncer` reports failures through an optional `onFailure` callback, while `PendingTeardowns.Teardown` provides no failure channel at all.
**Rationale**: The two types serve different obligations. `KeyedDebouncer` exists specifically to make a failed write retryable and eventually reportable — its own doc comment describes the exact bug (a full disk silently dropping a save) it was extracted to fix, so a failure that could recur MUST be observable to something that decides whether to keep retrying or surface it to a user. `PendingTeardowns` exists only to guarantee a teardown is *waited for*, not to give it a durable retry lifecycle; its doc comment states plainly that "there is no caller left to hand an error to" once the entry that started the teardown is gone. A `Teardown` that wants failure visibility must log it itself before returning.
**Approved**: pending

**Decision**: `flushAll()` runs every pending key's flush sequentially, one after another, even though `KeyedDebouncer` otherwise allows different keys' timer-triggered runs to execute fully concurrently with each other.
**Rationale**: Per the doc comment on `flushAll`, "the copies this replaces were sequential and their work writes to a shared destination; nothing here needs the parallelism, and serialising keeps a failure attributable." This is a deliberate asymmetry specific to the one call path (`flushAll`) that iterates every key at once, not a change to the general concurrency model described in `cross-key-concurrency` above.
**Approved**: pending

**Decision**: `BlockingWork.run` imposes no timeout, deadline, or cancellation of its own on the closure it dispatches.
**Rationale**: Per the type's doc comment, "this type only decides *where* it runs" — bounding how long the work may take is left entirely to the closure itself, the way `VSIXInstaller`'s `CommandRunner` already enforces its own 124-second budget (a timeout plus two termination graces) independently of `BlockingWork`. Centralizing a timeout in the shared hop would apply one policy to every disparate blocking operation (an archive extraction, a whole-file read, a directory scan) that currently each own their own bound, or none at all where none is needed.
**Approved**: pending

**Decision**: `KeyedDebouncer.armTimer`/`beginRun` capture `[weak self]`, so a `KeyedDebouncer` instance that is deallocated while work is armed or running silently drops that work with no signal to anyone.
**Rationale**: This is the caller's own lifecycle responsibility, not a defect in the type — `PendingTeardowns` exists precisely to solve the analogous problem (detached work outliving the object that started it) for the call sites that need that guarantee, and a caller of `KeyedDebouncer` that needs every scheduled write to complete before its debouncer goes away SHOULD call `flushAll()` first, exactly as a quit path calls `PendingTeardowns.drain()`. See the "Owner deallocation while work is pending" edge case above.
**Approved**: pending
