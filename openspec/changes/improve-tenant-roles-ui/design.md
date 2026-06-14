# Design — improve-tenant-roles-ui

## Context

`/settings/roles` is the last major IAM admin screen still on the pre-shadcn
pattern. The sibling `/settings/users` screen was just rebuilt on a shadcn data
table (`improve-tenant-users-ui`), establishing the patterns this change reuses:
`@tanstack/react-table`, the thin `DataTable` wrapper
(`src/components/ui/data-table.tsx`), URL-synced view-state params
(`src/lib/schemas/tenant-users-params.ts`), and the `{ data, meta }` list
envelope on the backend.

The role list is smaller than the user list (built-in set + a handful of custom
roles per tenant), so server-side pagination is arguably overkill. The user
chose **full server-side parity** anyway for consistency with the users screen
and to avoid a divergent client-only filtering path. This doc records the
decisions and the few role-specific wrinkles.

## Key decisions

### 1. Reuse the users-screen primitives verbatim
No new table/dropdown/datatable primitives are needed — `improve-tenant-users-ui`
already added `@tanstack/react-table` and `DataTable`. This change only adds one
new web primitive: a reusable `AlertDialog`.

### 2. Columns: Nama, Tipe, Jumlah User — no permission column
The card grid showed every permission as a badge. That does not survive the move
to dense rows, and the user explicitly chose to drop it from the table:
permissions are only viewed/edited in the create/edit/clone modal's existing
checkbox grid. The table answers "what roles exist, which are custom, and how
heavily is each used" — not "what can this role do".

```
┌────┬──────────────────────────┬───────────┬─────────────┬──────────┐
│ ☐  │ Nama            ▲▼       │ Tipe  ▲▼  │ Jumlah ▲▼   │  (aksi)  │
├────┼──────────────────────────┼───────────┼─────────────┼──────────┤
│ ☐  │ Wakil Kurikulum          │ [Custom]  │      3      │   [ ⋯ ]  │
│    │ wakil_kurikulum          │           │             │          │
│ ☐  │ Kepala Sekolah           │ [Bawaan]  │      1      │   [ ⋯ ]  │
└────┴──────────────────────────┴───────────┴─────────────┴──────────┘
```

### 3. `user_count` is new data, computed per-tenant
`role_view` (`http.rs:786`) returns no usage count today. The repo already has
`count_role_holders(tenant_id, role_id)` (used by `delete_role`'s `ROLE_IN_USE`
guard), so the count is well-defined. It MUST be scoped to the calling tenant
even for built-in roles (`tenant_id IS NULL`): the number is "users in *this*
tenant holding the role", computed from `user_tenant_role`, not a global count.
The list query computes it for all rows in one pass (a correlated subquery or a
`LEFT JOIN ... GROUP BY` over `user_tenant_role`) rather than N follow-up calls.

### 4. Sort keys map to stable SQL expressions
Mirror `TenantUsersQuery`'s approach. Sort fields:
- `name` / `-name` → `r.name`
- `type` / `-type` → `r.is_builtin` (built-in vs custom grouping)
- `users` / `-users` → the computed `user_count`

Default sort preserves today's ordering intent: built-in first, then by code
(`ORDER BY r.is_builtin DESC, r.code`). The default param maps to that so an
unsorted view looks unchanged.

### 5. Bulk delete is all-or-nothing, guards live server-side
The UI prevents built-in roles from ever reaching the endpoint (Hapus disabled
when any built-in is selected), but the backend MUST NOT trust that. The bulk
endpoint pre-validates **every** id:
- any built-in → reject whole request `403 BUILT_IN_ROLE_IMMUTABLE`
- any role with `count_role_holders > 0` → reject whole request `409 ROLE_IN_USE`
- any id not a custom role of this tenant → `404`/validation

Only if all pass does it delete them in a single transaction, emitting one
`role.deleted` event per role (same event the single delete already emits). This
reuses the exact guard logic already in `delete_role`; the bulk path just batches
the pre-checks before the transaction. All-or-nothing (not partial-success) was
chosen because a destructive multi-delete should be predictable: the admin sees
exactly why it was refused and nothing is half-applied.

### 6. Selection → delete-button state machine

```
selection contains a built-in role   → [Hapus] DISABLED
                                         🔴 "Lepaskan role bawaan dari pilihan
                                            untuk menghapus"
selection is all custom (≥1)         → [Hapus] ENABLED
                                         click → AlertDialog confirm → bulk delete
selection empty                      → bulk action bar hidden (as on users screen)
```

The red helper text appears only when the selection contains a built-in role.
A role still assigned to users (`user_count > 0`) is allowed to be *selected*,
but the server refuses it with `ROLE_IN_USE`; the resulting error is surfaced via
toast. (Optionally the UI may also reflect in-use roles, but the server is the
source of truth.)

### 7. AlertDialog is a new reusable primitive
The codebase confirms destructive actions with `window.confirm` today
(`users/page.tsx:809,819`). This change introduces a proper shadcn
`AlertDialog` under `src/components/ui/` for the role bulk-delete confirmation.
To keep scope tight, it does **not** retrofit the existing `window.confirm`
sites — that can be a follow-up.

## Risks / trade-offs

- **Server-side pagination for a small list is over-engineered.** Accepted for
  consistency with the users screen and to avoid maintaining a second
  filtering idiom. If role counts stay tiny, the pagination controls will simply
  always show "Halaman 1 dari 1".
- **`user_count` adds a join/subquery to every list call.** Negligible at
  expected role volumes; revisit only if the roles table grows unexpectedly.
- **New AlertDialog vs existing `window.confirm`.** Temporarily two confirmation
  idioms coexist. Acceptable; the new one is the intended direction.

## Open questions
- (none blocking — endpoint naming `POST /tenants/me/roles/bulk/delete` follows
  the users screen's `bulk/enable|disable|role` convention)
