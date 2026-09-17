# Feather Organizations

Authoritative organization identity domain, independent of Society, Jobs, money,
permissions, or shop presentation. Native Feather; no legacy compatibility layer.

## First slice

Contract 1 flat results, bounded readiness, defensive trusted type reads, and
checksummed resource-owned migrations. Initial types: business, government,
government_agency. Persisted UUIDs survive restart; display labels do not define
authority. Durable organization creation/read is now implemented. Status mutation,
hierarchy, interests, membership, client RPC, and gameplay UI remain unavailable
and are reported as zero. Next slice adds revision-checked lifecycle transitions.

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
Lifecycle transitions, identity edits, pagination, and hierarchy remain deferred.

First run `OrganizationsCreationContractSmokeTest` (12/12, no entities created).
Then use `OrganizationsCreationLiveTest org-creation-001` with DevMode enabled.
It creates one real pending entity using fixed key `org_creation_test`, verifies
same-ID replay, payload conflict, global key conflict, and one entity/audit row.
Restart and repeat the exact original request ID; never use a fresh key/ID to
recover this test. Disable DevMode and configure authorization before deployment.

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
entities. Runtime type registration/providers and durable audit facts remain
future work. Restarting Core can stop this consumer; start it again after Core
is ready. Cross-resource methods must be checked with IsCallable rather than
Lua function-only checks when provider tables are introduced.
