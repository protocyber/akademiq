## 1. Backend — IAM last-role guard (bug fix)

- [x] 1.1 In `remove_user_role` (`services/iam-service/src/commands.rs`), after the last-admin check, count the user's remaining roles in the tenant and return `AppError::conflict("LAST_ROLE", ...)` when removing this role would reach zero
- [x] 1.2 Add a repo helper (e.g. `count_user_roles_in_tenant`) in `services/iam-service/src/repo.rs` if one does not already exist
- [x] 1.3 Add an integration test in `services/iam-service/tests/integration.rs`: removing a user's only role returns 409 `LAST_ROLE` and the user still appears in `GET /tenants/me/users`
- [x] 1.4 Run `cd apps/backend && make test` for iam-service and confirm green

## 2. Backend — contract docs

- [x] 2.1 Document the `LAST_ROLE` conflict code (on the remove-role endpoint) in `docs/internal/11_integration_contracts/apis/iam-service-api.md`
</content>
