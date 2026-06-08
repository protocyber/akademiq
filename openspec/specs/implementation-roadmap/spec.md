# implementation-roadmap Specification

## Purpose

Establishes a versioned engineering standard for implementation phases, outlining service ownership, verification flows, and deferred scope across the foundational and subsequent development milestones.

## Requirements

### Requirement: Implementation phases SHALL be published as a versioned engineering standard

The roadmap MUST be committed at
`docs/internal/13_engineering_standards/16_implementation_phases.md` and
referenced from `docs/internal/13_engineering_standards/README.md`. The
document SHALL define numbered phases, each phase's scope, exit criteria,
and the openspec change name(s) that deliver it.

#### Scenario: Roadmap document is committed

- **WHEN** a contributor lists `docs/internal/13_engineering_standards/`
- **THEN** the file `16_implementation_phases.md` exists and is referenced from `README.md` in the same directory

#### Scenario: Each phase has scope and exit criteria

- **WHEN** a contributor opens `16_implementation_phases.md`
- **THEN** every phase in the document declares its scope, the services or features it delivers, and at least one exit criterion that an outside reader can verify

### Requirement: Roadmap SHALL define phases 1 through 4 with explicit service ownership

The document MUST list at minimum four phases in build order: Foundation
(IAM + Billing), Academic Configuration, Academic Operations, and Tenant
User Management. Each phase entry SHALL identify the owning service(s) and
the openspec change name that delivers it.

#### Scenario: Phase 1 ownership is documented

- **WHEN** a contributor reads phase 1 in `16_implementation_phases.md`
- **THEN** it lists `iam-service` and `billing-service` as owning services and `mvp-foundation-iam-billing` as the delivering change

#### Scenario: Phases 2 through 4 are documented

- **WHEN** a contributor reads phases 2, 3, and 4
- **THEN** each phase identifies its owning service(s) (`academic-config-service` for phase 2, `academic-ops-service` for phase 3, `iam-service` extension for phase 4) and a placeholder change name in kebab-case

### Requirement: Roadmap SHALL identify the test flows that prove each phase complete

For phase 1, the document MUST list the exact end-to-end flows that
demonstrate completion: tenant registration, plan selection, login, module
toggling. Subsequent phases SHALL each list at least one analogous flow
(create academic year for phase 2, add/import students for phase 3, invite
tenant user for phase 4).

#### Scenario: Phase 1 lists demo flows

- **WHEN** a contributor reads phase 1's exit criteria
- **THEN** the criteria include "register tenant", "select plan", "log in", and "toggle entitled modules" as verifiable user-visible flows

#### Scenario: Later phases list demo flows

- **WHEN** a contributor reads phases 2, 3, and 4
- **THEN** each phase lists at least one user-visible flow that proves the phase is functional

### Requirement: Roadmap SHALL declare deferred work explicitly

The document MUST include a "Deferred / Future Phases" section listing
attendance, grading, promotion, notification, file/storage, payment
provider integration, and email/SMS delivery as out of scope for phases
1-4 with a one-line rationale each.

#### Scenario: Deferred work is enumerated

- **WHEN** a contributor reads the deferred section
- **THEN** the seven listed concerns each appear with a brief rationale
