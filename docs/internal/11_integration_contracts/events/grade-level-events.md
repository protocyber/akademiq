# Events: GradeLevel lifecycle

**Event types:** `grade_level.created`, `grade_level.updated`,
`grade_level.deleted`, `grade_level.reordered`  
**Produced By:** Academic Config Service  
**Consumed By:** Academic Operations Service (`known_grade_level` projection,
homeroom grade-level links, promotion engine)  

## When They Are Emitted
Each write to an academic year's grade-level ladder emits exactly one event,
through the outbox, in the same transaction as the write.

## Payload Schemas (v1)

`grade_level.created` and `grade_level.updated` carry the full row:

```json
{
  "event_id": "uuid",
  "occurred_at": "datetime",
  "tenant_id": "uuid",
  "academic_year_id": "uuid",
  "grade_level_id": "uuid",
  "code": "X",
  "label": "Kelas X",
  "ordinal": 1,
  "is_final": false
}
```

`grade_level.deleted`:

```json
{
  "event_id": "uuid",
  "occurred_at": "datetime",
  "tenant_id": "uuid",
  "grade_level_id": "uuid"
}
```

`grade_level.reordered` carries the whole ladder's final ordinals:

```json
{
  "event_id": "uuid",
  "occurred_at": "datetime",
  "tenant_id": "uuid",
  "academic_year_id": "uuid",
  "levels": [
    { "grade_level_id": "uuid", "ordinal": 1 },
    { "grade_level_id": "uuid", "ordinal": 2 }
  ]
}
```

## Notes
- `created` and `updated` share one payload shape so a consumer can upsert
  from either.
- A reorder is one event for the whole ladder, emitted after both reorder
  phases, so it only ever carries final ordinals — never the temporary
  parking values used to avoid unique-ordinal collisions.
- A grade level's `academic_year_id` never changes after creation.
- The consumer skips a reordered id that is not yet in its projection rather
  than failing the batch; the eventual `created`/`updated` delivery fills it in.
- The promotion engine uses `ordinal` and `is_final`: a year must have exactly
  one final grade level before a promotion run can be created.
- RabbitMQ does not replay events published before the consumer's queue
  existed; `scripts/bootstrap-projections.sh` backfills `known_grade_level`
  from `academic_config.grade_level`.
