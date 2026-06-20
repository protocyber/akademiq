# Proposal: Fix Enrollment Event Propagation

## Masalah

Saat ini ada **dua jalur enrollment** yang tidak memancarkan event ke grading-service, menyebabkan data siswa tidak tersinkronisasi antara academic-ops-service dan grading-service.

### Bug #1: Unenroll Tidak Emit Event

**Lokasi:** `academic-ops-service/src/commands.rs:807-816`

Saat admin meng-unenroll siswa dari kelas, academic-ops-service hanya mengubah status enrollment di database lokal tanpa memancarkan event `student.unenrolled`. Akibatnya:
- Grading-service tidak tahu siswa sudah di-unenroll
- Tabel `enrolled_student` di grading_db tetap `status='active'`
- Siswa masih muncul di roster grading dan bisa menerima nilai/rapor padahal seharusnya tidak

### Bug #2: Initial Placement Tidak Emit Event

**Lokasi:** `academic-ops-service/src/commands.rs:362-406`

Saat admin membuat siswa baru dengan `initial_placement` (langsung enroll ke kelas), fungsi `try_initial_placement` hanya membuat enrollment tanpa memancarkan event `student.enrolled`. Akibatnya:
- Grading-service tidak menerima notifikasi enrollment
- Tabel `enrolled_student` di grading_db tidak terisi
- Siswa tidak muncul di roster grading, tidak bisa menerima nilai/rapor

### Dampak

**Data Inconsistency:**
- Academic-ops: enrollment ada dan aktif
- Grading: enrolled_student tidak ada atau status salah
- Frontend: roster kosong, "Siswa tidak ditemukan", rapor tidak bisa dibuat

**User Experience:**
- Admin bingung kenapa siswa yang sudah di-enroll tidak muncul di grading
- Harus manual re-enroll via UI untuk memicu event (workaround sementara)
- Data rapor dan nilai tidak akurat

## Solusi

### 1. Emit Event di `unenroll_student`

Tambahkan event `student.unenrolled` dengan payload:
```rust
{
  "tenant_id": Uuid,
  "student_id": Uuid,
  "homeroom_id": Uuid,
  "academic_year_id": Uuid
}
```

### 2. Emit Event di `try_initial_placement`

Tambahkan event `student.enrolled` dengan payload yang sama seperti `enroll_student`:
```rust
{
  "tenant_id": Uuid,
  "student_id": Uuid,
  "homeroom_id": Uuid,
  "academic_year_id": Uuid
}
```

### 3. Grading-Service Listen Event Baru

Tambahkan routing key `student.unenrolled` di grading-service event consumer untuk mengupdate `enrolled_student.status` menjadi `inactive` atau menghapus record.

## Ruang Lingkup

### In Scope
- Modify `unenroll_student` command untuk emit event
- Modify `try_initial_placement` function untuk emit event
- Add event handler di grading-service untuk `student.unenrolled`
- Update event schema documentation
- Testing event propagation end-to-end

### Out of Scope
- Backfill data untuk siswa yang sudah terkena bug ini (bisa dilakukan manual atau separate migration)
- UI changes (tidak diperlukan karena data akan sync otomatis setelah fix)
- Event replay mechanism (future enhancement)

## Kriteria Keberhasilan

1. ✅ Saat siswa di-unenroll via UI, grading-service menerima event dan update `enrolled_student`
2. ✅ Saat siswa dibuat dengan initial_placement, grading-service menerima event dan create `enrolled_student`
3. ✅ Data `enrolled_student` di grading_db selalu konsisten dengan enrollment di academic_ops_db
4. ✅ Frontend roster, nilai, dan rapor menampilkan data yang benar tanpa manual re-enroll
