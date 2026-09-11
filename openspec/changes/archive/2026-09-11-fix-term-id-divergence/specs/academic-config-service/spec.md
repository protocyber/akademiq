## ADDED Requirements

### Requirement: The service SHALL republish `academic_term.created` for existing terms

academic-config MUST provide an operation that enqueues an
`academic_term.created` event through the transactional outbox for every existing
`academic_term` row, carrying the real `{ tenant_id, term_id, academic_year_id,
name, start_date, end_date, status }`. The operation supports the one-time heal
that populates downstream projections (e.g. grading's `valid_term`) with real
term ids. It MUST be safe to run more than once.

#### Scenario: Republish enqueues an event per existing term

- **WHEN** the republish operation runs for a tenant with existing terms
- **THEN** one `academic_term.created` event carrying the term's real `term_id`
  is enqueued through the outbox for each existing term

#### Scenario: Republish is idempotent for downstream consumers

- **WHEN** the republish operation runs twice
- **THEN** downstream projection consumers upsert the same `valid_term` rows
  without duplication or corruption (the events carry stable real `term_id`s)
