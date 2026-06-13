# Security Baseline

- Passwords hashed using Argon2
- JWT tokens signed using RS256
- All services validate JWT signature
- RBAC enforced through tenant-scoped JWT `perms[]`; guards check permissions, not role names
- Tenant-scoped JWTs also carry `roles[]` for workflow identity and display; services must not trust client-provided tenant_id
- No direct trust of client-provided tenant_id; resolve tenant scope from `AuthContext`
- All DB connections use TLS