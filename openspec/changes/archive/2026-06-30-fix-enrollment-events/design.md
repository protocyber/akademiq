# Design: Fix Enrollment Event Propagation

## Context

AkademiQ menggunakan arsitektur microservices dengan event-driven communication untuk menjaga konsistensi data antar service. Saat ini ada dua service yang terlibat dalam enrollment workflow:

- **academic-ops-service**: Owner dari tabel `enrollment` (source of truth)
- **grading-service**: Consumer yang mem-proyeksikan data enrollment ke tabel `enrolled_student` untuk keperluan roster, grading, dan report cards

Komunikasi dilakukan melalui RabbitMQ event bus dengan pattern:
1. Academic-ops melakukan operasi database + emit event ke outbox
2. Outbox publisher mengirim event ke RabbitMQ exchange `academic-ops.events`
3. Grading-service subscribe dan update projection table

**Masalah saat ini:** Ada 2 jalur enrollment yang tidak emit event, menyebabkan data projection di grading-service tidak sinkron dengan source of truth di academic-ops.

**Stakeholders:**
- Backend developers (implementasi)
- Frontend developers (tidak ada perubahan UI)
- Students/Teachers (end users yang affected oleh bug)

## Goals / Non-Goals

**Goals:**
- Memastikan semua jalur enrollment emit event yang tepat ke event bus
- Grading-service dapat handle event `student.unenrolled` untuk update projection
- Data `enrolled_student` selalu konsisten dengan `enrollment`
- Zero downtime deployment (backward compatible)

**Non-Goals:**
- Backfill data historis untuk siswa yang sudah terkena bug (akan ditangani terpisah jika diperlukan)
- Perubahan UI/UX (bug akan auto-fix setelah data sync)
- Event replay mechanism atau dead letter queue (future enhancement)
- Idempotency key untuk events (sudah handled oleh database constraint)

## Decisions

### Decision 1: Event Schema untuk `student.unenrolled`

**Pilihan:** Gunakan payload schema yang sama dengan `student.enrolled` untuk konsistensi.

**Rationale:**
- Payload sudah contains semua informasi yang dibutuhkan (student_id, homeroom_id, academic_year_id)
- Consumer bisa reuse existing deserializer
- Mudah untuk debug dan trace event flow

**Schema:**
```json
{
  "event_type": "student.unenrolled",
  "payload": {
    "student_id": "uuid",
    "homeroom_id": "uuid", 
    "academic_year_id": "uuid"
  }
}
```

**Alternatif yang dipertimbangkan:**
- Tambah field `unenrolled_at` timestamp → Rejected karena grading-service bisa infer dari event timestamp
- Gunakan event type berbeda per reason (unenrolled vs transferred) → Rejected karena grading-service handle semua dengan cara yang sama

### Decision 2: Grading-Service Projection Update Strategy

**Pilihan:** Update `enrolled_student.status` menjadi `'inactive'` saat terima `student.unenrolled`.

**Rationale:**
- Preserves audit trail (bisa lihat history enrollment)
- Konsisten dengan existing status enum (`active`, `inactive`, `transferred`)
- Queries yang filter `status = 'active'` otomatis exclude unenrolled students

**Implementasi:**
```rust
// di grading-service event handler
match event_type {
  "student.unenrolled" => {
    UPDATE enrolled_student 
    SET status = 'inactive', updated_at = NOW()
    WHERE student_id = $1 AND academic_year_id = $2
  }
}
```

**Alternatif yang dipertimbangkan:**
- DELETE row dari `enrolled_student` → Rejected karena kehilangan audit trail
- Set `deleted_at` timestamp → Rejected karena tidak konsisten dengan existing schema

### Decision 3: Emit Event di `try_initial_placement`

**Pilihan:** Emit `student.enrolled` event SETELAH INSERT enrollment berhasil, dalam transaction yang sama.

**Rationale:**
- Konsisten dengan behavior `enroll_student` yang sudah ada
- Event hanya emit jika enrollment berhasil (atomic dengan DB operation)
- Grading-service tidak perlu bedakan antara initial placement vs manual enrollment

**Implementasi:**
```rust
pub async fn try_initial_placement(
    &self,
    tenant_id: Uuid,
    student_id: Uuid, 
    homeroom_id: Uuid,
    academic_year_id: Uuid,
    tx: &mut Transaction<'_, Postgres>,
) -> Result<(), AppError> {
    // 1. INSERT enrollment
    sqlx::query("INSERT INTO enrollment ...")
        .execute(&mut *tx)
        .await?;
    
    // 2. Emit event (dalam transaction yang sama)
    self.emit_enrollment_event(
        "student.enrolled",
        student_id,
        homeroom_id, 
        academic_year_id,
        tx
    ).await?;
    
    Ok(())
}
```

**Alternatif yang dipertimbangkan:**
- Emit event setelah transaction commit → Rejected karena risk event loss jika service crash sebelum emit
- Gunakan separate event type `student.initial_placement` → Rejected karena grading-service tidak perlu bedakan

### Decision 4: Event Ordering dan Race Conditions

**Pilihan:** Andalkan database constraint + event timestamp untuk handle ordering.

**Rationale:**
- `enrolled_student` punya unique constraint pada `(student_id, academic_year_id)`
- Jika enroll dan unenroll events tiba out-of-order, database state tetap konsisten
- Grading-service queries selalu filter `status = 'active'`

**Edge case handling:**
- Enroll → Unenroll → Enroll lagi: Row di-update status-nya, tidak ada duplicate
- Unenroll event tiba sebelum enroll: INSERT akan failed (constraint violation), retry mechanism akan handle
- Multiple rapid unenrolls: Idempotent karena UPDATE dengan WHERE clause

**Alternatif yang dipertimbangkan:**
- Implement event versioning/sequence number → Rejected karena over-engineering untuk use case ini
- Gunakan optimistic locking dengan version column → Rejected karena added complexity tanpa clear benefit

## Risks / Trade-offs

**Risk 1: Event Loss jika Service Crash**
- **Scenario:** Academic-ops commit transaction tapi crash sebelum emit event
- **Impact:** Data tidak sinkron sampai manual intervention
- **Mitigation:** 
  - Outbox pattern sudah implemented (event disimpan di DB sebelum publish)
  - Background job publish events dari outbox table
  - Monitoring alert jika outbox backlog > threshold

**Risk 2: Event Ordering Issues**
- **Scenario:** Enroll dan unenroll events tiba di grading-service out-of-order
- **Impact:** Temporary inconsistency, eventually consistent
- **Mitigation:**
  - Database unique constraint prevent duplicates
  - UPDATE query idempotent
  - Consumer retry mechanism dengan exponential backoff

**Risk 3: Backward Compatibility**
- **Scenario:** Grading-service lama tidak recognize `student.unenrolled` event
- **Impact:** Event di-ignore, unenroll tidak ter-propagate
- **Mitigation:**
  - Deploy grading-service update DULU (subscribe ke event baru)
  - Baru deploy academic-ops (start emit event)
  - Event schema versioning jika diperlukan di masa depan

**Risk 4: Performance Impact**
- **Scenario:** High volume enrollment operations membebani event bus
- **Impact:** Increased latency, potential event backlog
- **Mitigation:**
  - Event payload minimal (hanya UUIDs)
  - RabbitMQ sudah proven untuk high-throughput
  - Monitoring queue depth dan consumer lag

**Trade-off: Audit Trail vs Storage**
- Kita pilih preserve audit trail dengan update status, bukan delete
- Trade-off: Slightly more storage, tapi bisa trace enrollment history
- Worth it untuk compliance dan debugging

## Open Questions

**Q1: Apakah perlu backfill data untuk siswa yang sudah terkena bug?**
- **Current stance:** Tidak perlu untuk now, bisa manual fix jika ada complaint
- **Revisit jika:** Ada banyak affected students atau compliance requirement

**Q2: Apakah perlu implement event replay mechanism?**
- **Current stance:** Tidak perlu, outbox pattern sudah sufficient
- **Revisit jika:** Sering ada event loss atau need untuk reprocess historical events

**Q3: Apakah perlu add monitoring dashboard untuk enrollment events?**
- **Current stance:** Gunakan existing RabbitMQ monitoring
- **Revisit jika:** Perlu visibility lebih untuk troubleshooting

## Migration Plan

### Pre-Deployment Checklist
- [ ] Verify RabbitMQ cluster health
- [ ] Check outbox table tidak ada backlog
- [ ] Backup `enrolled_student` table (precaution)

### Deployment Steps (Order Matters!)

**Phase 1: Deploy Grading-Service (Consumer)**
1. Deploy grading-service dengan update untuk handle `student.unenrolled`
2. Verify service started dan subscribe ke event queue
3. Check logs untuk konfirmasi event subscription
4. Run smoke test: manually publish test `student.unenrolled` event, verify grading-service handle it

**Phase 2: Deploy Academic-Ops-Service (Producer)**
1. Deploy academic-ops-service dengan update untuk emit events
2. Verify service started dan outbox publisher running
3. Run smoke test: unenroll student via UI, verify event muncul di outbox dan RabbitMQ
4. Check grading-service logs untuk konfirmasi event received dan processed

**Phase 3: Verification**
1. Test full workflow: create student → enroll → grade → unenroll → verify roster updated
2. Test initial placement: create student dengan placement → verify muncul di grading roster
3. Check database consistency: compare `enrollment` vs `enrolled_student` untuk beberapa students
4. Monitor error rates dan queue metrics untuk 24 jam

### Rollback Strategy

**Jika grading-service bermasalah:**
- Rollback grading-service ke versi sebelumnya
- Academic-ops tetap emit events (tidak masalah, events akan di-queue dan diproses nanti)
- Investigasi issue, fix, redeploy

**Jika academic-ops bermasalah:**
- Rollback academic-ops ke versi sebelumnya
- Grading-service akan stop receive events baru (tapi projection lama tetap valid)
- Investigasi issue, fix, redeploy

**Data rollback (jika diperlukan):**
- Restore `enrolled_student` dari backup
- Re-run event processing dari outbox jika ada missed events

### Post-Deployment Monitoring

**Metrics to watch (first 24 hours):**
- Outbox queue depth (should stay near 0)
- Event processing latency (should be < 1 second)
- Error rate di grading-service logs (should be < 0.1%)
- Database consistency check (manual query compare enrollment vs projection)

**Alert thresholds:**
- Outbox backlog > 100 events
- Consumer lag > 5 minutes
- Error rate > 1%
- Any `student.unenrolled` event failed to process
