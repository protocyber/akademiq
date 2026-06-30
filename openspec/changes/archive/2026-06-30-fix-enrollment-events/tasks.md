## 1. Academic-Ops: Event Emission untuk Initial Placement

- [x] 1.1 Add `outbox` parameter ke `try_initial_placement` function signature (currently receives `_state` but unused for outbox)
- [x] 1.2 Setelah successful INSERT enrollment, call `outbox.enqueue` dengan event type `student.enrolled` dan payload `{tenant_id, student_id, homeroom_id, academic_year_id}` dalam transaction yang sama
- [ ] 1.3 Write unit test: verify event emitted ke outbox saat initial placement berhasil
- [ ] 1.4 Write unit test: verify transaction rollback jika event emit gagal

## 2. Academic-Ops: Event Emission untuk Unenroll

- [x] 2.1 Add event emission di `unenroll_student` command: setelah successful UPDATE enrollment status ke 'unenrolled', call `outbox.enqueue` dengan event type `student.unenrolled` dan payload `{tenant_id, student_id, homeroom_id, academic_year_id}`
- [x] 2.2 Wrap unenroll operation dalam database transaction (currently langsung execute tanpa tx) untuk atomicity dengan event emission
- [x] 2.3 Fetch `homeroom_id` dan `academic_year_id` dari existing enrollment sebelum update (needed untuk event payload)
- [ ] 2.4 Write unit test: verify event emitted ke outbox saat unenroll berhasil
- [ ] 2.5 Write unit test: verify no event emitted jika unenroll affects 0 rows

## 3. Grading-Service: Handle `student.unenrolled` Event

- [x] 3.1 Add `student.unenrolled` ke routing key subscription list di `events.rs` (line ~84-96)
- [x] 3.2 Create `StudentUnenrolledPayload` struct dengan fields: tenant_id, student_id, homeroom_id, academic_year_id
- [x] 3.3 Add match arm untuk event type `student.unenrolled` di consumer loop
- [x] 3.4 Implement `update_enrolled_student_status` method di ProjectionRepo: UPDATE enrolled_student SET status='inactive' WHERE student_id AND academic_year_id match
- [x] 3.5 Handle case dimana student tidak ada di enrolled_student (log warning, ack event)
- [ ] 3.6 Write integration test: verify enrolled_student status updated ke 'inactive' setelah receive unenroll event

## 4. Testing & Verification

- [ ] 4.1 End-to-end test: create student dengan initial_placement → verify student muncul di grading roster
- [ ] 4.2 End-to-end test: unenroll student → verify student hilang dari grading roster
- [ ] 4.3 End-to-end test: unenroll lalu re-enroll → verify student muncul kembali dengan status active
- [ ] 4.4 Verify existing `student.enrolled` events tetap diproses dengan benar (backward compatibility)
- [ ] 4.5 Database consistency check: query compare `enrollment` vs `enrolled_student` untuk verify sync

## 5. Documentation

- [ ] 5.1 Update `docs/internal/11_integration_contracts/events/student-enrolled.md` dengan note bahwa event sekarang juga emitted dari initial_placement
- [ ] 5.2 Create `docs/internal/11_integration_contracts/events/student-unenrolled.md` dengan payload schema dan consumer list

## 6. Deployment

- [ ] 6.1 Deploy grading-service update DULU (consumer harus ready sebelum producer emit new event)
- [ ] 6.2 Verify grading-service logs menunjukkan subscription ke `student.unenrolled` event
- [ ] 6.3 Deploy academic-ops-service update
- [ ] 6.4 Monitor outbox queue depth dan event processing latency untuk 24 jam
- [ ] 6.5 Run smoke test: unenroll student via UI, verify roster updated di grading
