# Event: ReportCardPublished

**Produced By:** Grading Service  
**Consumed By:** Academic Operations Service (promotion projections)  

## When It Is Emitted
When a report card transitions to `Published` — that is, on principal approval
of the final workflow step. Emitted for **every** published card, whether or
not its report type is currently flagged as the academic year's promotion
source.

## Payload Schema (v1)
```json
{
  "event_id": "uuid",
  "occurred_at": "datetime",
  "tenant_id": "uuid",
  "student_id": "uuid",
  "academic_year_id": "uuid",
  "report_card_id": "uuid",
  "report_type_id": "uuid",
  "is_promotion_source": true,
  "scores": [
    { "subject_id": "uuid", "final_score": 82.5 }
  ]
}
```

## Notes
- `scores` are read from `report_subject_score` — the per-subject values
  frozen when the card was generated — not from the live
  `subject_report_score` projection. Editing grades after a card is published
  does not change what was emitted.
- An empty `scores` array is legitimate (e.g. a report type with no scored
  subjects) and must not be treated as an error by consumers.
- `is_promotion_source` is a snapshot of whether `report_type_id` was the
  academic year's promotion source **at publish time**. A school may move the
  flag to a different report type afterwards, so consumers must not treat
  this field as authoritative at evaluation time — see
  `docs/internal/10_data_design/04_Academic_Operations_ERD.md` for how the
  `known_report_score` projection stores it purely for audit.
- The status write, the `report_approval` audit row, and this outbox insert
  all commit in one database transaction, so the event is never emitted for a
  transition that did not actually persist.
- Replaces the former `report_card.approved`, which was misnamed: it already
  fired on the transition to `Published`, not on an intermediate approval
  step. That event name had zero consumers, so it was renamed in place
  (no `event_type_v2` shim was needed).
