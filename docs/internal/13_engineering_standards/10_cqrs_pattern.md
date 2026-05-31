# CQRS Pattern

Services must separate:

- **Commands** → Modify state
- **Queries** → Read-only operations

Command handlers and query handlers must be implemented separately.