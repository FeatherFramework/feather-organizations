# Feather Organizations

Authoritative organization identity domain, independent of Society, Jobs, money,
permissions, or shop presentation. Native Feather; no legacy compatibility layer.

## First slice

Contract 1 flat results, bounded readiness, defensive trusted type reads, and
checksummed resource-owned migrations. Initial types: business, government,
government_agency. Persisted UUIDs survive restart; display labels do not define
authority. Durable organization creation/read and lifecycle transitions are now
implemented, together with single-parent hierarchy. Interests, membership, client RPC, and gameplay UI remain
unavailable and are reported as zero.

Only Organizations writes `feather_organization_types` and
`feather_organization_schema_migrations`. Configured labels sync on startup
and advance revision only if changed. Removing a type from Config does not
delete/retire it or free its stable key; retirement is a future explicit operation.
The type catalog is bounded to 32; no unbounded organization dump is exposed.

## Durable identity slice

`CreateOrganization(request)` accepts exactly `requestId`, `organizationType`,
`organizationKey`, `legalName`, `displayName`, and `reasonCode`. IDs are bounded
to 128 characters, start alphanumeric, and use letters/numbers/dots/underscores/
colons/hyphens. Keys are lowercase, start with a letter, and use letters/numbers/
underscores (64 characters maximum). Names are bounded nonblank text without
control characters (legal 160 bytes, display 100 bytes). Reason is a bounded
64-character lowercase token. No client identity or initial status is accepted.

Creation requires actual invoking-resource membership in `trustedCreators` and
`trustedReaders`. Optional Core action `organizations.organization.create` is
controlled by `Config.Authorization.enabled` (currently false for development).
This slice uses resource/service principals, not client-provided actor identity.
Policy deny/unavailable cannot bypass trust or domain validation.

New records start `pending`, revision 1. Caller/request receipts bind all material
fields using length-prefixed fingerprints. Exact retry returns the original
creation snapshot/UUID with `replayed=true`; it is not a current-state query.
Changed payload returns `idempotency_conflict`. Global organization keys cannot
be reused under another request, even by the same resource. Entity, receipt, and
append-only creation audit commit together; rejected duplicate attempts roll back
their receipt. No resource-local identity or display-name fallback exists.

Trusted `GetOrganization({ organizationId })` and
`FindOrganizationByKey({ organizationKey })` return current defensive snapshots.
Creation owns `feather_organizations`, `feather_organization_creation_receipts`,
and `feather_organization_events`. Audit records are durable database facts;
broker publication/outbox delivery and audit query APIs are not implemented yet.
Bounded listing, name edits, and single-parent hierarchy are documented below.

First run `OrganizationsCreationContractSmokeTest` (12/12, no entities created).
Then use `OrganizationsCreationLiveTest org-creation-001` with DevMode enabled.
It creates one real pending entity using fixed key `org_creation_test`, verifies
same-ID replay, payload conflict, global key conflict, and one entity/audit row.
Restart and repeat the exact original request ID; never use a fresh key/ID to
recover this test. Disable DevMode and configure authorization before deployment.

## Revision-checked lifecycle

`ChangeOrganizationStatus(request)` accepts exactly `organizationId`,
`expectedRevision`, `status`, `requestId`, and `reasonCode`. Revision is a numeric
integer, not a string. UUIDs normalize to lowercase. Stable request IDs/reasons
follow creation's limits. Use distinct IDs for creation and each intended change;
the audit namespace reserves each caller/request ID across organization operations.

Mandatory trust: `trustedMutators` plus trusted read access. Ordinary mutators
can change only organizations created by that resource. `privilegedMutators`
explicitly permits cross-resource administration (Admin is configured). Optional
Core update/suspend/dissolve actions apply when Authorization is enabled.
This is resource-level control, not player ownership, membership, or job authority.

Allowed transitions:

- pending → active or dissolving
- active → suspended or dissolving
- suspended → active or dissolving
- dissolving → dissolved
- dissolved → none

Skipping dissolution, same-status changes, and terminal reactivation are rejected.
Lock the entity and compare expected revision inside the transaction. A successful
change increments revision once and atomically writes its payload-bound lifecycle
receipt and append-only audit event. Stale/invalid changes roll back the receipt.
Exact replay returns the original resulting revision/status, even if later changes
occurred; current reads remain the current-state authority. Altered retry payloads
fail. Retain the original request after timeout rather than issue a new one.

Dissolution does not delete the entity/free its key or touch accounts, employment,
property, licenses, or other domains. A trusted coordinating workflow must finish
any required downstream cleanup before explicitly completing dissolution; this
slice does not verify those external obligations or provide a worker for them.

Run `OrganizationsLifecycleContractSmokeTest`: expect 15/15, no state changes.
Dev-only `OrganizationsLifecycleLiveTest org-lifecycle-001` creates a separate
fixed-key test entity, activates/suspends/resumes it, stages/completes dissolution,
and verifies exact replay, changed-payload rejection, stale revision rejection,
terminal protection, six audit events, and rejected-receipt rollback. It never
touches the original creation-test entity, money, or items. Restart then repeat
the exact ID; expect dissolved revision 6 with allReplayed=true and still six
events. After these manifest additions run refresh before restarting the resource.

## Contention and real export-boundary acceptance

`OrganizationsConcurrencyTest org-concurrency-001` is dev-only. It creates one
separate entity at fixed key `org_concurrency_test`, then concurrently submits
activation and begin-dissolution against revision 1 using distinct request IDs.
Either contender may win: expect exactly one success, one `revision_conflict`,
revision 2, two audit events (creation + winner), one lifecycle receipt, and
successful exact winner replay. Loser receipt reservation must roll back.
The test uses an explicit completion counter and a 30-second watchdog; timeout
does not cancel database work. Retain IDs and inspect state rather than create
another attempt under new IDs. Repeating the original command checks stored
winner replay; it is not another fresh contention measurement.

Optional `feather-organizations-tests` exercises real Cfx calls from a different
resource. With DevMode true, it receives reader/creator/mutator trust but never
privileged override. `OrganizationsOwnershipBoundaryTest org-ownership-001`
rejects foreign mutation and caller injection, preserves the creation-test
organization, and allows/replays a separate fixture-owned entity's activation.
See its README for deployment. It is not shipped in default startup/recipe.
Stop/remove the fixture and disable DevMode before production. These acceptance
tests passed in development, including export-boundary replay across restart.
They do not certify Core policy/provider failure behavior.

## Directory and identity edits

Trusted `ListOrganizations({ limit?, cursor?, status?, organizationType? })` returns
`{ items, nextCursor? }`. Limit defaults to 20 and accepts numeric integers 1–50.
Rows sort by immutable organization key using database binary collation. Cursor
is the last returned key, exclusive; keep filters unchanged on subsequent pages.
No totals, offset dump, or unbounded list is exposed. Pagination is a live view,
not a frozen snapshot: concurrent inserts/edits may affect later pages.

`UpdateOrganizationIdentity({ organizationId, expectedRevision, requestId,
reasonCode, legalName, displayName })` requires both names and the same mandatory
mutator/owner-or-privileged gates as lifecycle changes. Optional Core update
authorization applies when enabled. UUID, key, type, and status cannot be edited.
Names follow creation's byte limits and nonblank/control-character validation.
Pending/active/suspended identities can be renamed; dissolving/dissolved records
cannot receive fresh edits. Unchanged names return `no_change` without revision
or audit changes. Stale expected revisions return `revision_conflict`.

Identity changes, payload-bound receipts, and audit records commit together.
Length-prefixed fingerprints bind all material fields. Exact retry returns its
original name/revision snapshot, even after later edits; use GetOrganization for
current state. Request IDs must be distinct across organization operations. A
failed attempt rolls back receipt reservation. Migration 004 adds the identity
receipt table without changing applied foundation/creation/lifecycle migrations.

Recorded development acceptance commands (all passed, including exact restart
replay and the identity export-boundary fixture):

- `OrganizationsDirectoryContractSmokeTest`: 13/13 read-only checks.
- `OrganizationsIdentityContractSmokeTest`: 12/12, no edits.
- `OrganizationsIdentityLiveTest org-identity-001`: a separate fixed-key entity
  renamed/restored to revision 3, replay/mismatch/stale/no-change checks, blocked
  edits to the dissolved lifecycle-test entity, and three audit events.
- Repeat the live test with the same ID after restart, never a new request.
- Optional fixture `OrganizationsIdentityBoundaryTest org-identity-boundary-001`
  verifies real exported bounded reads, foreign rename denial, and fixture-owned
  edit/replay (requires earlier ownership fixture acceptance).

After manifest additions run refresh then restart Organizations; start the
optional fixture again only when testing its cross-resource calls. No gameplay
UI or recipe entry is added by this slice.

### Shared identity/lifecycle revision contention

Dev-only `OrganizationsIdentityLifecycleConcurrencyTest org-identity-race-001`
creates one separate fixed-key entity and races a rename against begin-dissolution
at revision 1. Either operation may win. Expect one success, one revision conflict,
revision 2, two audit events including creation, exactly one receipt across both
mutation tables, consistent winner-only names/status, and exact winner replay.
No previous acceptance entity, money, or item changes. This entity stays pending
and renamed, or dissolving with original names, depending on the winner.

The completion counter has a 30-second watchdog; timeout does not cancel DB work.
Keep original IDs for inspection/retry. Restart replay validates persisted winner
state, not a second fresh race. This cross-operation test and restart replay passed
with lifecycle winning and the edit rejected as stale. Policy-provider failures
and broad pagination contention remain gates.

## Single-parent hierarchy

`SetParentOrganization({ organizationId, parentOrganizationId, expectedRevision,
requestId, reasonCode })` and `RemoveParentOrganization({ organizationId,
expectedRevision, requestId, reasonCode })` use the same mandatory mutator/reader
trust as edits. Ordinary callers must own the child and proposed parent; explicit
privileged mutators may cross owner boundaries. Optional Core action is
`organizations.relationship.manage`. This is structural control, not player
membership or an implicit permission to use the parent's accounts/facilities.

Each child has at most one parent. Reject self-parent, cycles, unchanged links,
stale child revision, and fresh changes involving dissolving/dissolved child or
proposed parent. Existing links are preserved if lifecycle later changes; status
does not cascade to children. Removal changes only the link, not identity.
Only the child revision advances; parent revision/status is untouched.

All graph writers first lock a persisted guard row, then validate within their
transaction. Parent changes, child revision, durable receipt, and audit event
commit together. The graph is bounded to 4096 links and 32 ancestry links;
validation includes descendants so moving a subtree cannot exceed the depth cap.
These are deliberately small-foundation limits, not unbounded graph support.
Snapshot reads include `parentOrganizationId` when linked. Exact change replay
returns the original receipt and does not undo a later removal/reparent.

Trusted `ListOrganizationChildren({ organizationId, limit?, cursor? })` uses the
same 1–50 stable-key pagination as the directory and requires an existing parent.
`ListOrganizations` also accepts `parentOrganizationId` as a filter. Neither
query recursively dumps the tree or inherits authorization from a relationship.
Migration 005 adds parent links, serialization guard, and hierarchy receipts;
applied migrations remain unchanged. No typed relationships are implemented.

Recorded hierarchy acceptance:

- `OrganizationsHierarchyContractSmokeTest`: expect 13/13, no link changes.
- `OrganizationsHierarchyLiveTest org-hierarchy-001`: creates three separate
  pending entities, links a chain, rejects cycle/stale/mismatched requests,
  removes one link, and replays the old set without restoring it. Six audit
  events and rejected-receipt rollback are required; restart uses the same ID.
- Optional fixture `OrganizationsHierarchyBoundaryTest org-hierarchy-boundary-001`
  denies foreign child/parent linkage and permits owned set/replay/children reads.
  It requires prior ownership/identity fixture acceptance and adds one parent
  entity; no money, employment, or item data changes.

Contract passed 13/13. Live hierarchy and exact restart replay passed with six
events, cycle/stale/mismatch rejection, and the removed link staying absent.
Actual export-boundary tests and restart passed for foreign child/parent denial,
owned linking/replay, bounded children, and unchanged foreign target.

Dev-only `OrganizationsHierarchyConcurrencyTest org-hierarchy-race-001` is the
remaining pending gate. It creates two separate entities and concurrently submits
A → B and B → A. Either contender may win; require one commit, one hierarchy-cycle
rejection, one link/receipt, three events including both creations, unchanged
parent revision, and exact winner replay. A bounded 30-second watchdog does not
cancel DB work. Retain original IDs on timeout or restart; repeating the test
replays the persisted winner rather than running another fresh race. No money,
items, or earlier acceptance entities change.
Run refresh after manifest additions, then restart Organizations. Stop the
optional fixture after testing and disable DevMode before production.

## Installation and first acceptance

Place in `resources/[feather]/feather-organizations`. Start oxmysql and Core first.
No Economy or Character dependency; do not change their activation for this slice.
Run in the server console:

```text
refresh
ensure feather-organizations
OrganizationsFoundationSmokeTest
```

Expect 13/13 read-only passes. Then restart the resource and rerun to validate
startup/migration replay. Checksummed applied migrations must not be modified.
Database failures/checksum mismatches fail readiness; inspect server startup logs.
This resource is not automatically added to the recipe yet.

## Server exports

`GetCapabilities()`, `GetHealth()`, `AwaitReady(timeoutMs)` (default 30000,
integer 0–60000) return `{ ok = true, value = ... }` or flat
`{ ok = false, code, message, details }`.
`GetOrganizationType(key)` and `ListOrganizationTypes()` require the actual Cfx
invoking resource in `Config.Access.trustedReaders`. They return copies and are
readiness-gated. No client may supply a trusted resource identity.

Types are initial classifications, not capabilities or active organization
entities. Runtime type registration/providers and broker audit publication remain
future work. Restarting Core can stop this consumer; start it again after Core
is ready. Cross-resource methods must be checked with IsCallable rather than
Lua function-only checks when provider tables are introduced.
