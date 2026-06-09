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
