## MODIFIED Requirements

### Requirement: The grading service SHALL manage evaluations scoped per homeroom, subject, and year

The service MUST provide evaluation CRUD under `/api/v1/grading/evaluations`,
tenant-scoped from the JWT. An evaluation captures
`{ homeroom_id, subject_id, academic_year_id, term_id, code, name, position }` and
defines one assessment column (e.g. "UH1", "UTS") for that class+subject+year+term.
Two different homerooms teaching the same subject MUST be able to define
different evaluation lists. `code` MUST be unique per
`(tenant_id, homeroom_id, subject_id, academic_year_id, term_id)`.

Concrete evaluations MAY be created either manually by an assigned teacher (or
tenant admin) or by materialization from a per-term evaluation template. A
template acts as a seed only: after materialization, assigned teachers MAY add
or delete concrete evaluations for their `(homeroom, subject, year, term)`
without any constraint imposed by the template.

Evaluation writes (create, update, delete) MUST require the
`grade.evaluation.manage` permission as the primary authority gate. In addition,
a caller who is not a tenant admin MUST also be assigned to the evaluation's
subject+homeroom+year. A caller lacking `grade.evaluation.manage` MUST receive
HTTP 403 `FORBIDDEN`; an authorized non-admin caller who is not assigned to the
scope MUST receive HTTP 403 `NOT_ASSIGNED`.

#### Scenario: Teacher defines an evaluation column for a class+subject

- **WHEN** an assigned teacher holding `grade.evaluation.manage` POSTs `{ homeroom_id, subject_id, academic_year_id, term_id, code: "UH1", name: "Ulangan Harian 1", position: 1 }` to `/evaluations`
- **THEN** the response is HTTP 201 with the stored evaluation

#### Scenario: Caller without grade.evaluation.manage is rejected

- **WHEN** a caller who does not hold `grade.evaluation.manage` POSTs, PATCHes, or DELETEs an evaluation
- **THEN** the response is HTTP 403 `FORBIDDEN` and nothing changes

#### Scenario: Duplicate code in the same class+subject+year+term is rejected

- **WHEN** a teacher POSTs an evaluation whose `code` already exists for that `(homeroom, subject, year, term)`
- **THEN** the response is HTTP 409 `DUPLICATE_EVALUATION_CODE` and no evaluation is created

#### Scenario: Evaluations are listed for a class+subject+year in column order

- **WHEN** a client GETs `/evaluations?homeroom_id&subject_id&academic_year_id`
- **THEN** the response lists that scope's evaluations ordered by `position`

#### Scenario: Deleting an evaluation removes its grades

- **WHEN** a teacher DELETEs an evaluation that has recorded grades
- **THEN** the evaluation and all grades referencing it are removed, and a subsequent grid read no longer returns that column

#### Scenario: Unassigned teacher cannot manage evaluations

- **WHEN** a non-admin teacher who holds `grade.evaluation.manage` but is not assigned to that subject+homeroom+year POSTs, PATCHes, or DELETEs an evaluation
- **THEN** the response is HTTP 403 `NOT_ASSIGNED` and nothing changes

#### Scenario: Teacher overrides a materialized evaluation list

- **WHEN** evaluations were materialized from a term template and an assigned teacher then deletes one and adds another
- **THEN** both changes succeed and the template is unaffected
