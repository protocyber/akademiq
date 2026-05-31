# Security Baseline

- Passwords hashed using Argon2
- JWT tokens signed using RS256
- All services validate JWT signature
- RBAC enforced at middleware
- No direct trust of client-provided tenant_id
- All DB connections use TLS