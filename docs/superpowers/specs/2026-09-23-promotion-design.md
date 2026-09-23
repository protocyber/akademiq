# Design Spec: Kenaikan Kelas, Kelulusan & Tingkat Kelas (A1)

Date: 2026-09-23
Topic: modul promotion di `academic-ops-service` + entitas `grade_level` di `academic-config-service`
Status: approved (design) — siap masuk `writing-plans`
Roadmap: `.ai/plans/21_academic_year_cycle_roadmap.md` (fitur A1)

## 1. Tujuan dan Konteks

AkademiQ saat ini bisa menutup tahun ajaran (`academic_year.status_changed` →
`Closed`) tetapi **siswa tidak ke mana-mana**. Tidak ada mekanisme yang
memindahkan siswa ke tahun ajaran berikutnya, meluluskan siswa di tingkat akhir,
atau mencatat siswa yang tinggal kelas. Siklus satu tahun ajaran belum tertutup.

Fitur ini menutup siklus tersebut. Selesai berarti: sekolah bisa menjalankan
evaluasi kenaikan, meninjau dan menimpa keputusan per siswa, mendapat persetujuan
kepala sekolah, mengeksekusi perpindahan enrollment ke tahun ajaran berikutnya,
dan mencetak SK.

`promotion` sudah terdaftar sebagai feature code di `apps/backend/features.toml`
dan **sudah dijual di plan Premium** tanpa implementasi. Ini menutup utang itu.

### 1.1 Keputusan yang disepakati saat brainstorming

| Pertanyaan | Keputusan |
|---|---|
| Cara sekolah memutuskan kenaikan | Berbeda per tenant — dikonfigurasi, bukan di-hardcode |
| Bentuk konfigurasi aturan | **Opsi 1**: daftar kriteria bertipe tetap, digabung AND, tenant mengisi angkanya |
| Penempatan modul | **Opsi B**: modul di dalam `academic-ops-service`, bukan service ke-7 |
| Cakupan | Keputusan + eksekusi + kelulusan + cetak SK sederhana |
| Template builder | **Di luar cakupan** — masuk backlog, dipakai bersama SK dan rapor custom |

### 1.2 Penyimpangan dari `docs/internal/` yang disengaja

`docs/internal/10_data_design/07_Promotion_Service_ERD.md` memodelkan promotion
sebagai service terpisah dengan database sendiri. Spec ini **menempatkan tabel
yang sama di schema `academic_ops`**.

Alasan: inti fitur ini adalah memindahkan enrollment antar tahun ajaran, dan
enrollment hidup di `academic-ops`. Memisahkannya berarti keputusan ada di satu
database dan akibatnya di database lain tanpa transaksi bersama — eksekusi yang
gagal separuh jalan akan menyebarkan siswa setengah-pindah di awal tahun ajaran.
Risiko nyata untuk keuntungan yang hanya konseptual.

Bentuk tabel tetap mengikuti ERD persis, sehingga kalau kelak terbukti perlu
dipisah, pemindahannya mekanis. Penyimpangan ini harus dicatat di
`docs/internal/10_data_design/07_Promotion_Service_ERD.md` dan
`docs/internal/11_integration_contracts/apis/promotion-service-api.md` agar
dokumen dan kode tidak saling berbohong.

## 2. Prasyarat: Tingkat Kelas jadi Entitas

### 2.1 Masalah

`homeroom.grade_level` dan `class_template.grade_level` bertipe `VARCHAR(64)`
bebas. Test backend memakai `"X"`, `"XI"`; form web adalah input teks biasa.
Akibatnya sistem tidak bisa menjawab tiga hal yang mutlak diperlukan promotion:

1. Urutan tingkat — mana "tingkat berikutnya" dari `X`?
2. Tingkat akhir — siapa yang lulus alih-alih naik?
3. Konsistensi penulisan — `"X"` vs `"10"` vs `"x"` adalah tiga tingkat berbeda
   bagi database.

### 2.2 Tabel baru (`academic-config-service`)

Ditempatkan bersama `class_template`, mengikuti pola per-tahun-ajaran.

```sql
CREATE TABLE grade_level (
  grade_level_id   UUID PRIMARY KEY,
  tenant_id        UUID NOT NULL,
  academic_year_id UUID NOT NULL REFERENCES academic_year(academic_year_id),
  code             VARCHAR(32) NOT NULL,   -- "X", "XI", "XII"
  label            VARCHAR(64) NOT NULL,   -- "Kelas X"
  ordinal          INT NOT NULL,           -- 1, 2, 3 — sumber "tingkat berikutnya"
  is_final         BOOLEAN NOT NULL DEFAULT FALSE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT grade_level_code_unique    UNIQUE (tenant_id, academic_year_id, code),
  CONSTRAINT grade_level_ordinal_unique UNIQUE (tenant_id, academic_year_id, ordinal),
  CONSTRAINT grade_level_ordinal_chk    CHECK (ordinal > 0)
);
```

"Tingkat berikutnya" = baris dengan `ordinal + 1` pada tahun ajaran tujuan.
Kelulusan dipicu `is_final = TRUE`. Tidak ada parsing angka romawi, tidak ada
tebakan dari string.

### 2.3 Migrasi data yang sudah ada

`homeroom` dan `class_template` mendapat kolom `grade_level_id UUID NULL`.
Kolom `grade_level` string **dipertahankan** selama masa transisi.

Migrasi otomatis: untuk setiap nilai `grade_level` distinct per tahun ajaran,
buat baris `grade_level`; `ordinal` diisi urut berdasarkan urutan yang terdeteksi
(romawi bila cocok, selain itu abjad) sebagai **tebakan awal**, `is_final` selalu
`FALSE`.

Admin **wajib meninjau** hasil tebakan ini di UI sebelum evaluasi kenaikan
pertama bisa dijalankan. Evaluasi menolak berjalan bila tahun ajaran tidak punya
tepat satu `grade_level` dengan `is_final = TRUE`. Tidak ada urutan yang
dipalsukan diam-diam.

### 2.4 UI

Rute baru `/settings/academic/grade-levels`: CRUD sederhana, drag untuk mengatur
urutan, satu checkbox penanda tingkat akhir. Mengikuti pola halaman
`class-templates`.

## 3. Model Data Promotion (schema `academic_ops`)

```sql
-- Aturan dibekukan saat evaluasi dijalankan, sehingga keputusan lama tetap
-- bisa dijelaskan walaupun aturan sekolah berubah tahun berikutnya.
CREATE TABLE promotion_rule_snapshot (
  rule_id                UUID PRIMARY KEY,
  tenant_id              UUID NOT NULL,
  academic_year_id       UUID NOT NULL,
  min_average            NUMERIC NULL,   -- rata-rata minimum
  max_subjects_below_kkm INT NULL,       -- maksimal mapel di bawah KKM
  min_attendance_percent NUMERIC NULL,   -- disiapkan; aktif setelah A2 (attendance)
  kkm_snapshot           NUMERIC NOT NULL,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Satu angkatan evaluasi per tahun ajaran.
CREATE TABLE promotion_run (
  run_id           UUID PRIMARY KEY,
  tenant_id        UUID NOT NULL,
  academic_year_id UUID NOT NULL,
  rule_id          UUID NOT NULL REFERENCES promotion_rule_snapshot(rule_id),
  status           VARCHAR(32) NOT NULL,
  created_by       UUID NOT NULL,
  approved_by      UUID NULL,
  executed_at      TIMESTAMPTZ NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT promotion_run_status_chk
    CHECK (status IN ('draft', 'submitted', 'approved', 'executed'))
);

CREATE TABLE promotion_decision (
  decision_id        UUID PRIMARY KEY,
  run_id             UUID NOT NULL REFERENCES promotion_run(run_id) ON DELETE CASCADE,
  tenant_id          UUID NOT NULL,
  student_id         UUID NOT NULL,
  enrollment_id      UUID NOT NULL,
  academic_year_id   UUID NOT NULL,
  homeroom_id        UUID NOT NULL,
  recommended        VARCHAR(16) NOT NULL,  -- hasil hitungan sistem
  result             VARCHAR(16) NOT NULL,  -- keputusan final
  overridden         BOOLEAN NOT NULL DEFAULT FALSE,
  reason             TEXT NULL,             -- wajib bila overridden
  computed_metrics   JSONB NOT NULL,        -- bukti perhitungan
  target_homeroom_id UUID NULL,             -- diisi saat eksekusi
  CONSTRAINT promotion_decision_recommended_chk
    CHECK (recommended IN ('promote', 'retain', 'graduate')),
  CONSTRAINT promotion_decision_result_chk
    CHECK (result IN ('promote', 'retain', 'graduate')),
  CONSTRAINT promotion_decision_override_reason_chk
    CHECK (NOT overridden OR (reason IS NOT NULL AND length(trim(reason)) >= 10)),
  CONSTRAINT promotion_decision_run_student_unique UNIQUE (run_id, student_id)
);

CREATE TABLE graduation_record (
  graduation_id      UUID PRIMARY KEY,
  tenant_id          UUID NOT NULL,
  student_id         UUID NOT NULL,
  academic_year_id   UUID NOT NULL,
  graduation_date    DATE NOT NULL,
  certificate_number VARCHAR(64) NULL,
  CONSTRAINT graduation_record_student_year_unique UNIQUE (student_id, academic_year_id)
);

CREATE TABLE retention_record (
  retention_id     UUID PRIMARY KEY,
  tenant_id        UUID NOT NULL,
  student_id       UUID NOT NULL,
  academic_year_id UUID NOT NULL,
  reason           TEXT NOT NULL,
  CONSTRAINT retention_record_student_year_unique UNIQUE (student_id, academic_year_id)
);
```

### 3.1 Dua tambahan di luar ERD, beserta alasannya

**`promotion_run`** tidak ada di ERD. Tanpanya tidak ada wadah untuk keadaan
"sudah dievaluasi tapi belum disetujui", dan tidak ada cara mengulang evaluasi
tanpa menimpa keputusan lama. Tabel ini juga yang memungkinkan alur persetujuan
kepala sekolah.

**`computed_metrics` JSONB** disimpan berdampingan dengan `promotion_rule_snapshot`.
Setahun kemudian pertanyaan "kenapa anak ini tinggal kelas" masih bisa dijawab
dengan angka yang dipakai saat itu — bukan angka hari ini. Rapor bisa direvisi;
keputusan yang sudah diambil tidak boleh ikut berubah diam-diam.

### 3.2 Perubahan constraint yang sudah ada

Keduanya sudah tertulis di `docs/internal/09_states/` tetapi belum ada di DB:

```sql
-- enrollment: tambah state 'promoted' (State_Student_Enrollment_Lifecycle)
ALTER TABLE enrollment DROP CONSTRAINT enrollment_status_chk;
ALTER TABLE enrollment ADD CONSTRAINT enrollment_status_chk
  CHECK (status IN ('active', 'transferred', 'unenrolled', 'promoted'));

-- student: tambah 'lulus' dan 'alumni' (State_Student_Academic_Status_Lifecycle)
ALTER TABLE student DROP CONSTRAINT student_status_chk;
ALTER TABLE student ADD CONSTRAINT student_status_chk
  CHECK (status IN ('aktif', 'nonaktif', 'arsip', 'lulus', 'alumni'));
```

Projection `enrolled_student` di `grading-service` memakai check status yang sama
dan **harus ikut diperbarui**, kalau tidak consumer akan menolak event.

## 4. Alur Kerja dan Eksekusi

### 4.1 State machine `promotion_run`

```
draft ──(evaluasi dijalankan)──> submitted ──(kepsek setuju)──> approved ──(eksekusi)──> executed
  ^                                   |                            |
  └────────────── return ─────────────┴────────────────────────────┘
```

| Status | Arti | Yang boleh dilakukan |
|---|---|---|
| `draft` | Evaluasi sudah dihitung | Jalankan ulang evaluasi (menimpa), override keputusan |
| `submitted` | Sudah ditinjau wali kelas/admin | Terkunci; override butuh `return` ke draft |
| `approved` | Disetujui kepala sekolah | Petakan homeroom tujuan, eksekusi |
| `executed` | Enrollment tahun berikutnya dibuat | Tidak ada; sekali jalan, tidak bisa diulang |

### 4.2 Syarat menjalankan evaluasi

- Tahun ajaran berstatus `Active` atau `Closed`.
- Tahun ajaran punya tepat satu `grade_level` dengan `is_final = TRUE`.
- Rapor siswa sudah `Published`.

Siswa tanpa rapor terbit **tidak diam-diam dianggap tinggal kelas**. Mereka masuk
daftar terpisah "tidak bisa dievaluasi" beserta alasannya. Kegagalan senyap pada
fitur sekelas ini merusak kepercayaan sekolah secara permanen.

### 4.3 Perhitungan rekomendasi

Semua kriteria digabung **AND**. Kriteria bernilai `NULL` dilewati.

```
jumlah mapel dengan final_score < kkm_snapshot > max_subjects_below_kkm  → retain
rata-rata final_score                          < min_average             → retain
persen kehadiran (setelah A2)                  < min_attendance_percent  → retain
selain itu, bila grade_level.is_final                                    → graduate
selain itu                                                               → promote
```

Konsekuensi yang disengaja: sekolah yang memutuskan lewat rapat pleno cukup
mengosongkan semua kriteria — semua siswa mendapat `promote`, lalu diubah manual
dengan alasan. Sekolah yang ingin otomatis mengisi kriteria ketat dan menyetujui
massal. Satu mesin melayani ketiga gaya kerja tanpa tiga alur terpisah.

Sumber nilai adalah `report_subject_score.final_score` (angka yang **dibekukan**
saat rapor terbit), bukan `subject_report_score` yang masih berubah setiap guru
menyimpan nilai.

### 4.4 Eksekusi — satu transaksi di `academic_ops`

| `result` | Enrollment lama | Enrollment baru | Efek lain |
|---|---|---|---|
| `promote` | → `promoted` | `active` di tahun berikutnya, homeroom `ordinal + 1` | — |
| `retain` | → `promoted` | `active` di tahun berikutnya, tingkat sama | `retention_record` |
| `graduate` | → `promoted` | tidak ada | `graduation_record`; `student.status` → `lulus` |

`retain` tetap menutup enrollment lama menjadi `promoted` karena tahun ajaran itu
memang sudah selesai baginya; yang membedakan adalah tingkat tujuannya sama.

**`lulus`, bukan langsung `alumni`.** `State_Student_Academic_Status_Lifecycle`
memisahkan keduanya: `Graduated` berarti siswa sudah menuntaskan tingkat akhir
tetapi tahun ajaran belum resmi ditutup; `Alumni` baru berlaku setelah penutupan.
Karena itu eksekusi menetapkan `lulus`, dan perpindahan `lulus` → `alumni`
ditangani consumer event `academic_year.status_changed` → `Closed` yang sudah ada
di `academic-ops`. Meloncat langsung ke `alumni` akan menghapus perbedaan yang
sengaja dimodelkan dan mengacaukan pelaporan siswa yang lulus pada tahun berjalan.

Event terbit lewat outbox yang sudah ada: `student.promoted`, `student.retained`,
`student.graduated`.

### 4.5 Pemetaan homeroom tujuan

Admin memetakan homeroom asal → homeroom tujuan per tingkat sebelum eksekusi
(misalnya `X IPA 1` → `XI IPA 1`). Sistem **menyarankan** berdasarkan kecocokan
nama dan tingkat; admin mengoreksi.

Penempatan otomatis berbasis kapasitas **sengaja tidak dibuat**. Perombakan kelas
adalah keputusan sekolah yang sarat pertimbangan non-akademik (pemerataan
kemampuan, pemisahan siswa bermasalah, permintaan orang tua). Otomatisasi di
sini hampir pasti salah dan akan selalu ditimpa manual.

## 5. Projection yang Dibutuhkan

`academic-ops` perlu data dari dua service lain. Mengikuti pola projection yang
sudah ada (`known_academic_year`, `known_tenant_user`) — **bukan** panggilan HTTP
langsung, yang melanggar `apps/backend/CONVENTIONS.md` dan membuat evaluasi gagal
saat service lain mati.

```sql
CREATE TABLE known_report_score (
  tenant_id        UUID NOT NULL,
  academic_year_id UUID NOT NULL,
  student_id       UUID NOT NULL,
  subject_id       UUID NOT NULL,
  report_type_id   UUID NOT NULL,
  final_score      DOUBLE PRECISION NOT NULL,
  PRIMARY KEY (tenant_id, report_type_id, student_id, subject_id)
);

CREATE TABLE known_grading_policy (
  tenant_id             UUID NOT NULL,
  academic_year_id      UUID NOT NULL,
  minimum_passing_score NUMERIC NOT NULL,
  PRIMARY KEY (tenant_id, academic_year_id)
);
```

Sumber event:

- `known_report_score` ← event `report_card.published` dari `grading-service`,
  membawa daftar `report_subject_score`. Saat ini kontrak yang ada adalah
  `report-card-approved.md`; perlu dipastikan ada event yang terbit tepat saat
  status menjadi `Published` **beserta skornya**. Ini pekerjaan tambahan di
  grading-service.
- `known_grading_policy` ← event dari `academic-config-service`.
  `grading-service` sudah punya `grading_policy_projection`, jadi polanya tinggal
  ditiru.

## 6. API

Semua di bawah `/api/v1/academic-ops`, dijaga feature code `promotion`.

| Method | Path | Keterangan |
|---|---|---|
| POST | `/promotion-runs` | Buat draft + jalankan evaluasi |
| GET | `/promotion-runs?academic_year_id=` | Daftar angkatan evaluasi |
| GET | `/promotion-runs/:run_id` | Detail + ringkasan |
| GET | `/promotion-runs/:run_id/decisions` | Filter per homeroom |
| PATCH | `/promotion-runs/:run_id/decisions/:decision_id` | Override + alasan |
| POST | `/promotion-runs/:run_id/submit` | draft → submitted |
| POST | `/promotion-runs/:run_id/approve` | submitted → approved |
| POST | `/promotion-runs/:run_id/return` | kembali ke draft |
| PUT | `/promotion-runs/:run_id/homeroom-map` | Pemetaan homeroom tujuan |
| POST | `/promotion-runs/:run_id/execute` | approved → executed |

`grade_level` CRUD berada di `academic-config` mengikuti tempat tabelnya.

Permission baru di IAM: `promotion.manage` (evaluasi, override, submit, execute)
dan `promotion.approve` (khusus kepala sekolah).

Feature code `promotion` sudah ada di `features.toml`; tidak perlu entri baru,
tinggal dipasang middleware-nya.

## 7. UI (`apps/web`)

Rute baru `/promotion`, mengikuti `apps/web/CONVENTIONS.md` — shadcn/ui,
TanStack Query, pola tabel dari `students-screen.tsx`.

- Daftar angkatan evaluasi per tahun ajaran dengan status.
- Halaman detail: tab per homeroom; tabel siswa dengan kolom rekomendasi, metrik
  pendukung (rata-rata, jumlah mapel di bawah KKM), dan aksi override.
- Panel pemetaan homeroom tujuan.
- Tombol submit / approve / execute sesuai permission.
- Daftar terpisah "tidak bisa dievaluasi" beserta alasan tiap siswa.

Entri sidebar baru dengan visibility `moduleAndPermission`
(`featureCode: "promotion"`, `permissionCode: "promotion.manage"`).

## 8. Cetak SK

Dua komponen cetak statis meniru `report-card-print-document.tsx` (React +
`@media print`, A4) — **bukan** generator PDF baru:

- SK Kenaikan Kelas — per kelas, daftar siswa beserta hasilnya.
- Surat Keterangan Lulus — per siswa.

Kop surat dari `school-profile` yang sudah ada, tanda tangan kepala sekolah,
nomor surat diisi manual.

**Template builder di luar cakupan.** Dicatat sebagai kebutuhan backlog yang
dipakai bersama oleh SK dan rapor custom. Menggabungkannya ke sini akan
menggandakan ukuran pekerjaan dan menunda penutupan siklus, sementara SK statis
sudah cukup dipakai sekolah tahun ini.

## 9. Pengujian

Mengikuti `apps/backend/CONVENTIONS.md` dan `apps/web/CONVENTIONS.md`; TDD per
`superpowers:test-driven-development`.

Backend — yang wajib ada:

- Perhitungan rekomendasi: tiap kriteria sendiri-sendiri, kombinasi AND, semua
  kriteria `NULL` (semua `promote`), tingkat akhir → `graduate`.
- Evaluasi menolak berjalan bila `is_final` tidak tepat satu.
- Siswa tanpa rapor terbit masuk daftar "tidak bisa dievaluasi", bukan `retain`.
- Override tanpa alasan ditolak; alasan < 10 karakter ditolak.
- Transisi status ilegal ditolak (mis. execute dari `draft`).
- Eksekusi idempoten: `execute` kedua kali ditolak, tidak menggandakan enrollment.
- Eksekusi gagal separuh jalan me-rollback seluruh transaksi.
- `graduate` menetapkan `student.status` = `lulus`, dan menjadi `alumni` hanya
  setelah `academic_year.status_changed` → `Closed`.
- Isolasi tenant pada setiap endpoint.

Web: pengujian komponen untuk tabel keputusan dan dialog override.

## 10. Urutan Implementasi yang Disarankan

1. `grade_level` di academic-config: tabel, migrasi data, API, UI.
2. Perubahan constraint `enrollment` dan `student` (+ projection grading).
3. Event `report_card.published` bermuatan skor di grading-service.
4. Projection `known_report_score` dan `known_grading_policy` di academic-ops.
5. Tabel promotion + mesin evaluasi + pengujiannya.
6. API promotion-run dan alur statusnya.
7. Eksekusi + event `student.promoted/retained/graduated`.
8. UI `/promotion`.
9. Cetak SK.
10. Perbarui `docs/internal/` (ERD, kontrak API, state diagram) sesuai penyimpangan
    di bagian 1.2.

Langkah 1-4 adalah prasyarat yang tidak menghasilkan fitur terlihat; jangan
dipotong.
