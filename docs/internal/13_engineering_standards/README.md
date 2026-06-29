# AkademiQ Engineering Standards

This folder defines technical standards and conventions to be followed across all backend microservices.

These standards ensure:
- Consistent architecture
- Easier onboarding
- Reduced technical debt

## Documents

| File | Topic |
|------|-------|
| `01_repo_structure.md` | Backend monorepo layout (services / libs) |
| `02_tech_stack.md` | Language, framework, database, ORM, auth |
| `03_api_conventions.md` | Base path, envelopes, pagination |
| `04_event_standards.md` | Event naming, envelope, transport, versioning |
| `05_environment_strategy.md` | Environments and config |
| `06_cicd_pipeline.md` | CI/CD baseline |
| `07_security_baseline.md` | Security baseline |
| `08_logging_tracing.md` | Logging, tracing, OpenTelemetry |
| `09_error_handling.md` | Error handling rules |
| `10_cqrs_pattern.md` | Command vs query separation |
| `11_devops_local_setup.md` | Local development setup |
| `12_makefile_standards.md` | Standard Makefile target list per service |
| `13_api_documentation.md` | API documentation conventions |
| `14_validation_contract.md` | Validation error contract (must align with frontend Zod) |
| `15_feature_entitlement.md` | Feature entitlement (plan-based access) |
| `16_implementation_phases.md` | Phased build order: foundation → academic config → academic ops → tenant users |
| `17_enum_catalog.md` | Canonical enumerated values for profiles, statuses, relationships, and media |
| `18_media_storage.md` | Media storage strategy: shared `common-media` lib vs `storage-service`, and migration triggers |
