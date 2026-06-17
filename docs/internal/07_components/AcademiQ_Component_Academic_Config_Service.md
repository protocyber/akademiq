# AcademiQ Component Diagram — Academic Config Service

```mermaid
flowchart TB

subgraph API_Layer
    CTRL[Academic Config REST Controllers]
end

subgraph Application_Layer
    UC1[Manage Academic Year Use Case]
    UC2[Manage Academic Term Use Case]
    UC3[Transition Year Status Use Case]
    UC4[Transition Term Status Use Case]
    UC5[Manage Curriculum Version Use Case]
    UC6[Manage Subjects Use Case]
    UC7[Manage Class Templates Use Case]
    UC8[Manage Grading Policy Use Case]
end

subgraph Domain_Layer
    AY[Academic Year Entity + YearStatus]
    AT[Academic Term Entity + TermStatus]
    CV[Curriculum Version Entity]
    SB[Subject Entity]
    CT[Class Template Entity]
    GP[Grading Policy Entity]
end

subgraph Infrastructure_Layer
    REPO[Repositories]
    DB[(Academic Config Database)]
    OUTBOX[Transactional Outbox]
    MQ[RabbitMQ Publisher]
end

CTRL --> UC1
CTRL --> UC2
CTRL --> UC3
CTRL --> UC4
CTRL --> UC5
CTRL --> UC6
CTRL --> UC7
CTRL --> UC8

UC1 --> AY
UC2 --> AT
UC3 --> AY
UC4 --> AT
UC5 --> CV
UC6 --> SB
UC7 --> CT
UC8 --> GP

UC1 --> REPO
UC2 --> REPO
UC3 --> REPO
UC4 --> REPO
UC5 --> REPO
UC6 --> REPO
UC7 --> REPO
UC8 --> REPO

REPO --> DB
UC1 --> OUTBOX
UC2 --> OUTBOX
UC3 --> OUTBOX
UC4 --> OUTBOX
OUTBOX --> DB
OUTBOX --> MQ
```

## Published Events

| Event | Trigger |
|-------|---------|
| `academic_year.created` | Year created |
| `academic_year.status_changed` | Year status transitioned |
| `academic_term.created` | Term created (including auto-seed on year creation) |
| `academic_term.status_changed` | Term status transitioned |
