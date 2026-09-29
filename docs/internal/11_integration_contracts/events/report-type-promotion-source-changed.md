# Event: ReportTypePromotionSourceChanged

**Event type:** `report_type.promotion_source_changed`  
**Produced By:** Grading Service  
**Consumed By:** Academic Operations Service (`known_report_type` projection, promotion engine)  

## When It Is Emitted
Whenever the **effective** value of `report_type.is_promotion_source` changes:

- a report type is created with `is_promotion_source = true` → `true`;
- an update flips the flag (`false` → `true` or `true` → `false`) → the new value;
- a report type that was the promotion source is deleted → `false`.

Nothing is emitted when the value does not change (re-saving `true`, creating
with `false`, deleting a non-source report type), when a request is rejected
(e.g. `REPORT_TYPE_PROMOTION_SOURCE_TAKEN`), or when report types are copied
between terms — copying never sets the flag.

## Payload Schema (v1)
```json
{
  "event_id": "uuid",
  "occurred_at": "datetime",
  "tenant_id": "uuid",
  "academic_year_id": "uuid",
  "report_type_id": "uuid",
  "is_promotion_source": true
}
```

## Notes
- The flag write and this outbox insert commit in one database transaction,
  so the event is never emitted for a change that did not persist.
- The flag is **year-scoped** while report types are term-scoped: at most one
  report type per `(tenant_id, academic_year_id)` is the promotion source.
  Grading-service enforces this in its command layer.
- On `true`, the consumer clears any other report type of the same tenant and
  year before upserting this one. On `false`, it updates only this report
  type, so a late `false` for an old source never clears the current one.
- This event is the authoritative source for "which report type decides
  promotion now". `report_card.published`'s `is_promotion_source` is a
  publish-time snapshot kept for audit only.
- RabbitMQ does not replay events published before the consumer's queue
  existed; `scripts/bootstrap-projections.sh` backfills `known_report_type`
  from `grading.report_type` for existing data.
