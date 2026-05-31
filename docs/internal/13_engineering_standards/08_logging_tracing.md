# Logging & Tracing Standards

## Logging
Use `tracing` crate with structured logs.

## Log Fields
- request_id
- user_id
- tenant_id
- service_name


- Every request must generate or propagate a `request_id`
- `request_id` must be logged in every log entry


## Tracing
Use OpenTelemetry for distributed tracing across services.
