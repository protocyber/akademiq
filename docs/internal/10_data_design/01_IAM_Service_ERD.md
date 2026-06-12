# AcademiQ ERD — Identity & Access Service

```mermaid
erDiagram
USER {
  uuid user_id PK
  string username "NOT NULL, unique (ci), no '@'"
  string email "nullable, unique-if-present (ci)"
  bool email_verified
  string password_hash "nullable (Google-only = null)"
  string google_sub "nullable, unique-if-present"
  string status
}

ROLE {
  uuid role_id PK
  string name
}

PERMISSION {
  uuid permission_id PK
  string code
}

USER_TENANT_ROLE {
  uuid id PK
  uuid user_id FK
  uuid tenant_id
  uuid role_id FK
}

REFRESH_TOKEN {
  uuid user_id PK,FK
  uuid jti PK
  uuid tenant_id "scope of the refreshed token"
  string token_hash
  timestamptz expires_at
  timestamptz revoked_at "nullable"
}

ROLE ||--o{ PERMISSION : grants
USER ||--o{ USER_TENANT_ROLE : assigned
ROLE ||--o{ USER_TENANT_ROLE : scoped
USER ||--o{ REFRESH_TOKEN : holds
```

## 🧠 What This Database Owns
This service handles authentication and authorization.

### Main Entities
| Entity | Purpose |
|-------|---------|
| User | Login identity. `username` is the universal key; `email`, `password_hash`, and `google_sub` are all optional, enabling email/username/Google login and passwordless accounts. |
| Role | Group of permissions |
| Permission | Fine-grained access control |
| User Tenant Role | Role assignment per tenant (a user may have zero or many) |
| Refresh Token | Tenant-scoped refresh credential; refreshing renews the same tenant's access token |

## 🔗 Important Relationships
Users receive roles within a tenant scope, and roles grant permissions. Identity
and membership are separate: a user can exist with **no** tenant membership
(public signup or Google auto-provision) and may belong to **many** tenants.
Login resolves a user without a tenant; a tenant is selected afterward, and
`User Tenant Role` is checked when issuing a tenant-scoped token.