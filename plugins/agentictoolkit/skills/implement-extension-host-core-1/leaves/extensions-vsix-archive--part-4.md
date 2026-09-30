<!-- leaf: implement-extension-host-core-1/extensions-vsix-archive--part-4 · source: extension-host-core-extensions-vsix-archive.md -->

# VSIXArchive — continued (part 4)

## Design Decisions

**Decision**: Shell out to `/usr/bin/ditto -x -k` rather than a Swift or
third-party zip library for extraction.
**Rationale**: It is the platform's own unarchiver — the same one a Finder
double-click runs — and it already refuses the two ways a hostile archive
escapes its destination (a traversing relative or absolute entry name, and a
symlink written through), checked here against a purpose-built archive
rather than assumed. A pure-Swift unzip would have had to re-earn both, and
getting either subtly wrong is a directory traversal in a path that takes
third-party archives off the internet (doc comment).
**Approved**: pending

**Decision**: Bound `expand` on two independent axes — a wall-clock
`timeout` and a decompressed-size `byteCeiling` — rather than one.
**Rationale**: A zip bomb is a compression ratio, not a duration: the
canonical ones write tens of gigabytes as fast as the disk accepts them and
then exit cleanly well inside a two-minute timeout, which is why the timeout
alone was previously (incorrectly) described as covering this case. The
ceiling and the timeout each catch an archive the other does not — one that
never finishes, and one that finishes by filling the disk (doc comment on
`expansionTimeout`; doc comment on `expansionByteCeiling`).
**Approved**: pending

**Decision**: Set `expansionByteCeiling` to 2 GiB, several times the size of
the largest real extension known to bundle a per-platform language-server
binary, rather than a tighter number closer to typical extension size.
**Rationale**: Deflate reaches roughly 1000:1 compression on adversarial
input, so the 512 MB `OpenVSXClient` artifact download cap alone is license
to decompress to half a terabyte; 2 GiB is comfortably above any honest
extension while remaining small enough that reaching it leaves room on the
volume to report the failure (doc comment).
**Approved**: pending

**Decision**: Name a fully verified result `.registryAttested` rather than
`.verified`, and treat a signature/key pair from the registry as proving the
bytes were not altered in transit — never as proving who published them.
**Rationale**: `publicKeyPEM` arrives from `OpenVSXExtensionDetail
.publicKeyURL`, a string in the same JSON response that named the archive
and its digest; a registry serving altered bytes signs them with a key of
its own, publishes that key at that URL, and every check in `verify` passes.
There is no anchor to compare the key against — Open VSX publishes no
publisher key out of band, and this host has pinned none — so the settings
panel line this result feeds has to say "the registry published," not "the
publisher signed" (doc comment).
**Approved**: pending

**Decision**: Throw on a signature or key published alone, rather than
treating the pair as absent.
**Rationale**: Most of Open VSX is unsigned, so refusing every unsigned
extension would refuse the catalog — but one half of the pair present is a
different situation from neither being present: something *was* published,
and reporting that as an unsigned extension states the opposite of what
happened. The thrown `signatureIncomplete(missing:)` names which half is
missing, which is the fact a report against the registry needs (doc comment).
**Approved**: pending

**Decision**: Check the digest before the signature, and always compute
`sha256Hex(of:)` regardless of whether a digest to compare it against was
published.
**Rationale**: A digest mismatch is reported as a digest failure even when a
signature would otherwise verify, because a truncated or substituted
download is a different situation from a signing problem and should send
whoever reads the error looking at their network, not the publisher's key
(test `digestIsCheckedFirst`). The hash is still computed when no digest was
published because an install record needs it to recognize these exact bytes
later, but its presence must not be read as "these bytes were checked" —
hence the separate `.matched`/`.notPublished` result rather than inferring a
check from the hash's presence (doc comment).
**Approved**: pending
