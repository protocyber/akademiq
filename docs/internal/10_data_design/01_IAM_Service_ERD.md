# AcademiQ ERD — Identity & Access Service

```mermaid
erDiagram
USER {
  uuid user_id PK
  string email
  string password_hash
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

ROLE ||--o{ PERMISSION : grants
USER ||--o{ USER_TENANT_ROLE : assigned
ROLE ||--o{ USER_TENANT_ROLE : scoped
```

## 🧠 What This Database Owns
This service handles authentication and authorization.

### Main Entities
| Entity | Purpose |
|-------|---------|
| User | Login identity |
| Role | Group of permissions |
| Permission | Fine-grained access control |
| User Tenant Role | Role assignment per tenant |

## 🔗 Important Relationships
Users receive roles within a tenant scope, and roles grant permissions.