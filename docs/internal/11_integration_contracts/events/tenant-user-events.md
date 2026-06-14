# Tenant User Events

Published by `iam-service` to the `akademiq.events` topic exchange.

Envelope:

```json
{
  "event_id": "uuid",
  "event_type": "tenant_user.invited",
  "occurred_at": "2026-06-09T12:00:00Z",
  "payload": {}
}
```

## `tenant_user.invited`

Routing key: `tenant_user.invited`

Payload:

```json
{
  "tenant_id": "uuid",
  "invitation_id": "uuid",
  "email": "teacher@school.test",
  "role": "teacher",
  "invited_by": "uuid",
  "expires_at": "2026-06-16T12:00:00Z"
}
```

## `tenant_user.activated`

Routing key: `tenant_user.activated`

Payload:

```json
{
  "tenant_id": "uuid",
  "invitation_id": "uuid",
  "user_id": "uuid",
  "email": "teacher@school.test",
  "role": "teacher"
}
```

## `tenant_user.role_changed`

Routing key: `tenant_user.role_changed`

Payload:

```json
{
  "tenant_id": "uuid",
  "user_id": "uuid",
  "role": "principal"
}
```

The user's current access token remains valid until expiry. The new role is
reflected on the next refresh-token rotation.

## `tenant_user.disabled`

Routing key: `tenant_user.disabled`

Payload:

```json
{
  "user_id": "uuid"
}
```

## `tenant_user.created`

Routing key: `tenant_user.created`

Emitted when a tenant admin creates a brand-new user directly (not via
invitation) through `POST /tenants/me/users`. Payload:

```json
{
  "tenant_id": "uuid",
  "user_id": "uuid",
  "username": "budi_guru",
  "email": "budi@school.test|null",
  "full_name": "Budi Santoso",
  "roles": ["teacher", "homeroom_teacher"]
}
```

## `tenant_user.updated`

Routing key: `tenant_user.updated`

Emitted when a tenant admin updates a user's identity fields through
`PATCH /tenants/me/users/{id}`. The `changes` object records only the fields
that actually changed, each as a `{ "from": ..., "to": ... }` pair, so the audit
log can render a meaningful entry. Payload:

```json
{
  "tenant_id": "uuid",
  "user_id": "uuid",
  "changes": {
    "full_name": { "from": "Budi", "to": "Budi Santoso" },
    "username": { "from": "budi", "to": "budi_guru" }
  }
}
```

Editing `username` rewrites the global login key but does NOT invalidate live
sessions (access tokens key off `sub`, not `username`).

## `tenant_user.removed`

Routing key: `tenant_user.removed`

Emitted when a tenant admin explicitly off-boards a user through
`DELETE /tenants/me/users/{id}`, dropping ALL of the user's roles in the tenant
in one transaction. The global `user` record is not deleted. Payload:

```json
{
  "tenant_id": "uuid",
  "user_id": "uuid",
  "roles": ["teacher", "homeroom_teacher"]
}
```

The role-set events `tenant_user.role_assigned` (add) and
`tenant_user.role_removed` (remove) keep their existing names. The single-role
*replace* path emits `tenant_user.role_changed` and is unchanged. Bulk
role-change MUST be implemented via add/remove (so the `LAST_ROLE` / `LAST_ADMIN`
guards run) and MUST NOT route through the replace path.
