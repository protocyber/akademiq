# Desain: Event `report_card.published` + Projection Sumber Nilai

Tanggal: 2026-09-23
Status: draft, menunggu review
Bagian dari: Plan 2 dari 4, roadmap A1 (kenaikan kelas)
Spec induk: `docs/superpowers/specs/2026-09-23-promotion-design.md` (§3.2, §5)

## 1. Ringkasan

Mesin evaluasi kenaikan kelas di `academic-ops-service` butuh dua fakta yang
dimiliki service lain: **nilai akhir rapor** (milik `grading-service`) dan
**KKM** (milik `academic-config-service`). `CONVENTIONS.md` melarang pengambilan
lewat HTTP antar-service, jadi keduanya harus sampai lewat event dan mendarat di
projection lokal.

Dokumen ini mendesain jalur itu. Tidak mencakup mesin evaluasinya sendiri (Plan 3).

### 1.1 Keputusan yang sudah diambil

| Pertanyaan | Keputusan |
|---|---|
| Rapor mana yang menentukan kenaikan? | **Opsi (a)** — satu `report_type` ditandai sekolah sebagai penentu |
| Bentuk muatan skor di event | **Opsi (a)** — event gemuk, skor ikut di payload, dan **selalu** dikirim untuk setiap rapor terbit |
| Penegakan "maksimal satu penentu" | **Opsi (a)** — command layer, meniru `grade_level.is_final`; **plus** sabuk pengaman di konsumen |

## 2. Temuan yang mengubah asumsi spec induk

Spec induk (§5) menyebut event `report_card.published` sebagai pekerjaan
tersembunyi yang perlu dibuat. Pembacaan kode menunjukkan gambaran berbeda, dan
lebih murah.

### 2.1 Event-nya sudah ada, hanya salah nama

`services/grading-service/src/commands.rs:1574` sudah menyalakan event **tepat di
titik yang benar** — saat status rapor berubah menjadi `Published`:

```rust
if next == ReportCardStatus::Published {
    outbox.insert_event(
        Uuid::new_v4(),
        "report_card.approved",        // <- nama menyesatkan
        &json!({ tenant_id, student_id, academic_year_id, report_card_id }),
        Utc::now(),
    )
}
```

Namanya peninggalan dari sebelum status `Published` ada. Jadi pekerjaannya bukan
membuat event baru dari nol, melainkan **mengganti nama + menambah muatan** pada
event yang sudah terbit di saat yang tepat.

### 2.2 Rename tidak merusak apa pun

`report_card.approved` **tidak punya konsumen satu pun** di seluruh monorepo.
Satu-satunya penyebutan di luar produsen ada di
`services/grading-service/tests/integration.rs:1257,1262`.

Konsekuensi: **tidak perlu `event_type_v2`**. Aturan versioning di `AGENTS.md`
melindungi konsumen yang ada; di sini tidak ada. Rename langsung, satu kontrak,
tanpa periode transisi.

Kontrak lama `docs/internal/11_integration_contracts/events/report-card-approved.md`
menyebut "Consumed By: Notification Service, Promotion Service" — keduanya belum
ada. Dokumen itu menggambarkan rencana, bukan kenyataan.

### 2.3 Tidak ada data lama yang perlu di-backfill

Database dev tidak punya satu pun rapor berstatus `Published` (81 `Draft`,
1 `HomeroomReview`). Tidak perlu skrip republish untuk rapor lama.

Catatan untuk produksi: bila suatu tenant sudah menerbitkan rapor sebelum
perubahan ini, projection-nya kosong. Ditangani di §7.

### 2.4 KKM sudah lengkap di sisi produsen

`academic-config-service/src/commands.rs:559` sudah meng-emit
`grading_policy.configured` dengan `minimum_passing_score`. `grading-service`
sudah mengonsumsinya ke `grading_policy_projection`
(`grading-service/src/events.rs:216`).

Jadi `known_grading_policy` di `academic-ops` adalah **konsumen baru atas event
yang sudah ada** — nol perubahan di produsen, polanya tinggal ditiru.

## 3. Penanda rapor penentu kenaikan

### 3.1 Masalah

Satu siswa punya beberapa rapor per tahun: `report_card` unik per
`(report_type_id, student_id)`, dan `report_type` bebas ditentukan sekolah
("UTS", "UAS", "Semester 1", "Semester 2").

Mesin evaluasi di spec induk §4.3 berbunyi "rata-rata `final_score`" tanpa
menyebut rapor yang mana. Rata-rata dari UTS ≠ rata-rata dari rapor akhir tahun,
dan selisihnya menentukan seorang anak naik kelas atau tidak.

### 3.2 Keputusan

Kolom baru di `report_type`:

```sql
ALTER TABLE report_type
  ADD COLUMN is_promotion_source BOOLEAN NOT NULL DEFAULT FALSE;
```

Sekolah menandai satu `report_type` per tahun ajaran sebagai penentu kenaikan.

**Ditolak — `position` tertinggi.** Menebak maksud sekolah dari urutan. Kalau
sekolah salah mengurutkan `position`, siswa dinilai dari rapor yang salah tanpa
ada yang sadar. Ini persis jenis tebakan diam-diam yang sudah ditolak untuk
`grade_level.is_final` di Plan 1 (backfill V9 tidak pernah menebak `is_final`).

**Ditolak — rata-rata semua `report_type`.** Menyeret nilai UTS ke keputusan
kenaikan kelas, yang tidak sesuai praktik sekolah Indonesia.

### 3.3 Penegakan "maksimal satu per tahun ajaran"

Ditegakkan di **command layer**, meniru `ensure_no_other_final` pada
`grade_level.is_final` (`academic-config-service/src/commands.rs`). Tanpa
constraint DB, konsisten dengan pola yang sudah ditetapkan.

**Asimetri yang disadari, dan mitigasinya.** `grade_level.is_final` salah →
Plan 3 menolak jalan (gagal keras, ketahuan). `report_type.is_promotion_source`
ganda → evaluasi bisa memilih rapor yang salah dan **tetap jalan** (gagal diam-
diam). Konsekuensinya lebih buruk.

Karena itu penegakan ada di **dua sisi**:

1. Produsen (`grading-service`): command menolak menandai penentu kedua.
2. Konsumen (`academic-ops-service`): evaluasi **menolak berjalan** bila
   menemukan lebih dari satu rapor penentu untuk satu `(tenant, tahun, siswa)`.

Sabuk pengaman di konsumen inilah yang membuat pilihan command-layer sama amannya
dengan constraint DB untuk kasus yang benar-benar berbahaya. Konsumen tidak boleh
memercayai produsen dalam hal yang keputusannya menyangkut nasib siswa.

## 4. Kontrak event `report_card.published`

### 4.1 Payload

```json
{
  "event_id": "uuid",
  "event_type": "report_card.published",
  "occurred_at": "datetime",
  "payload": {
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
}
```

Sumber `scores` adalah `report_subject_score` — nilai **beku** yang dihitung saat
rapor di-generate. Bukan `subject_report_score`, yang masih berubah setiap guru
menyimpan nilai. Spec induk §4.3 sudah menetapkan ini; dicatat ulang karena kedua
nama tabel nyaris sama dan mudah tertukar.

### 4.2 Skor selalu dikirim, tidak hanya untuk rapor penentu

Setiap rapor yang terbit membawa skornya, apa pun nilai `is_promotion_source`.

Alasannya: penanda penentu bisa dipindahkan sekolah **setelah** rapor UTS terbit.
Kalau UTS tidak pernah mengirim skor, memindahkan penanda ke UTS menghasilkan
projection kosong, dan satu-satunya pemulihan adalah republish manual. Membawa
skor selalu — lalu `academic-ops` menyimpan semuanya dan memilih saat evaluasi —
tahan terhadap salah-urut penandaan.

`is_promotion_source` ikut di payload sebagai **snapshot saat terbit**, tapi
bukan sumber kebenaran saat evaluasi; lihat §5.2.

### 4.3 Ukuran

15 mapel × ~60 byte ≈ 1 KB per event. Satu angkatan 300 siswa ≈ 300 KB sekali
panen. RabbitMQ tidak keberatan.

### 4.4 Bentuk yang ditolak

**Event tipis + tarik lewat HTTP.** Melanggar `CONVENTIONS.md`, dan evaluasi
gagal saat `grading-service` mati.

**Satu event per mapel.** Memecah satu fakta atomik ("rapor ini terbit dengan
nilai segini") menjadi belasan pesan yang harus dirakit ulang tanpa penanda
kelengkapan. Konsumen tidak pernah tahu pasti sudah menerima semua mapel atau
belum → evaluasi kenaikan kelas dari data separuh.

## 5. Projection di `academic-ops-service`

### 5.1 Tabel

Mengikuti pola `known_*` yang sudah ada (`known_academic_year`,
`known_academic_term`, `known_tenant_user`).

```sql
CREATE TABLE known_report_score (
  tenant_id           UUID NOT NULL,
  academic_year_id    UUID NOT NULL,
  student_id          UUID NOT NULL,
  subject_id          UUID NOT NULL,
  report_type_id      UUID NOT NULL,
  final_score         DOUBLE PRECISION NOT NULL,
  is_promotion_source BOOLEAN NOT NULL,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (tenant_id, report_type_id, student_id, subject_id)
);

CREATE TABLE known_grading_policy (
  tenant_id             UUID NOT NULL,
  academic_year_id      UUID NOT NULL,
  minimum_passing_score DOUBLE PRECISION NOT NULL,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (tenant_id, academic_year_id)
);
```

Primary key `known_report_score` menyertakan `report_type_id`, sehingga skor dari
beberapa rapor hidup berdampingan — prasyarat agar §4.2 berguna.

`minimum_passing_score` bertipe `DOUBLE PRECISION` mengikuti
`grading_policy_projection` di grading-service, bukan `NUMERIC` seperti tertulis
di spec induk §5. Selisih tipe antar-projection atas fakta yang sama adalah
sumber bug perbandingan yang halus.

### 5.2 `is_promotion_source` adalah snapshot, bukan sumber kebenaran

Kolom ini menyimpan nilai **saat rapor terbit**. Bila sekolah memindahkan
penanda setelah rapor terbit, baris lama menyimpan nilai basi.

Karena itu evaluasi di Plan 3 **tidak boleh** memilih rapor berdasarkan kolom ini
saja. Yang benar: `academic-ops` menanyakan `report_type` mana yang saat ini
ditandai penentu (lewat projection `report_type` — lihat §8), lalu menyaring
`known_report_score` dengan `report_type_id` itu.

Kolom snapshot tetap disimpan untuk keperluan audit dan diagnosis ("rapor ini
terbit saat ia masih/bukan penentu").

### 5.3 Idempotensi

Consumer memakai `ON CONFLICT (tenant_id, report_type_id, student_id, subject_id)
DO UPDATE`, mengikuti `upsert_grading_policy_projection`. Event yang terkirim dua
kali menghasilkan keadaan yang sama.

Mapel yang **hilang** dari payload berikutnya tidak terhapus oleh upsert. Rapor
yang di-generate ulang dengan mapel lebih sedikit akan meninggalkan baris yatim.
Ditangani di §7.

## 6. Perubahan constraint (prasyarat Plan 3)

Dicatat di sini karena satu perubahan menyentuh dua service dan pernah gagal
diam-diam sebelumnya.

| Tabel | Service | Perubahan |
|---|---|---|
| `enrollment.status` | academic-ops | tambah `'promoted'` |
| `enrolled_student.status` | **grading** | tambah `'promoted'` |
| `student.status` | academic-ops | tambah `'lulus'`, `'alumni'` |

**Wajib satu perubahan yang sama.** `enrolled_student` di grading-service adalah
projection dari enrollment. Bila nilai `'promoted'` ditambahkan di academic-ops
tapi tidak di grading, consumer grading menolak event dan projection melenceng
**tanpa error yang terlihat**. Kegagalan persis ini sudah pernah terjadi
(`.ai/plans/20`, consumer mati 8 hari sebelum ketahuan).

`homeroom.grade_level` di academic-ops bertipe `VARCHAR(64)`. Plan 3 tidak boleh
mempersempitnya ke 32 — penyempitan seperti itu sudah menyebabkan satu Critical
di Plan 1 (`value too long`, SQLSTATE 22001).

`'lulus'` dan `'alumni'` adalah dua keadaan berbeda: eksekusi menetapkan
`'lulus'`; `'alumni'` menyusul hanya setelah tahun ajaran ditutup.

## 7. Pemulihan dan kasus tepi

**Tenant yang sudah menerbitkan rapor sebelum perubahan ini.** Projection-nya
kosong; evaluasi akan melihat siswa tanpa nilai. Plan 3 harus **menolak** dan
menyebut siswa mana yang datanya tidak ada, bukan memperlakukan "tanpa nilai"
sebagai "nilai nol" — nol berarti tinggal kelas. Perintah CLI republish
(`akademiq grading republish-report-scores --year <id>`) dipertimbangkan di Plan 3
bila ada tenant nyata yang terkena; tidak dibangun sekarang.

**Rapor di-generate ulang dengan mapel lebih sedikit.** Upsert meninggalkan baris
mapel lama. Consumer menghapus baris untuk `(tenant, report_type, student)` yang
`subject_id`-nya tidak ada di payload, dalam transaksi yang sama — delete-then-
upsert per rapor, bukan upsert saja.

**Rapor dibatalkan dari `Published`.** Transisi yang ada hanya
`Published → Archived` (`domain.rs:287`, hanya role `System`). Arsip tidak
menghapus skor: rapor yang pernah terbit tetap fakta historis. Bila kelak ada
transisi keluar dari `Published`, event pembatalan harus didesain bersamaan.

**Siswa pindah tenant.** Semua kunci diawali `tenant_id`; tidak ada jalur
kebocoran antar-tenant.

## 8. Yang sengaja tidak dicakup

- **Mesin evaluasi** (Plan 3).
- **Projection `report_type`** ke academic-ops. Dibutuhkan §5.2 agar evaluasi
  tahu rapor penentu yang berlaku sekarang. Masuk Plan 3 bersama konsumennya,
  karena sebelum mesin evaluasi ada, tidak ada yang membacanya.
- **UI penanda penentu** di halaman jenis rapor. Perubahan kecil di web; ikut
  Plan 3 bersama UI promotion agar tidak ada layar setengah jadi.
- **Notification service** — belum ada.

## 9. Urutan pengerjaan

1. `is_promotion_source` di `report_type` + penegakan command layer + tes.
2. Rename `report_card.approved` → `report_card.published`, tambah muatan skor +
   tes (termasuk tes bahwa skor berasal dari `report_subject_score` yang beku).
3. Perubahan constraint `enrollment` / `enrolled_student` / `student` —
   **satu perubahan, dua service**.
4. Projection `known_report_score` + `known_grading_policy` di academic-ops +
   consumer + tes idempotensi dan delete-then-upsert.
5. Perbarui `docs/internal/`: ganti `report-card-approved.md` menjadi
   `report-card-published.md`, ERD grading (`is_promotion_source`), ERD
   academic-ops (dua tabel `known_*`).

Langkah 1-4 tidak menghasilkan fitur yang terlihat pengguna. Jangan dipotong:
tanpa keempatnya, mesin evaluasi di Plan 3 tidak punya data untuk dihitung.

## 10. Pengujian yang wajib ada

- Event terbit **hanya** saat transisi ke `Published`, bukan saat approval lain.
- Payload memuat setiap mapel di `report_subject_score` untuk rapor itu.
- Skor berasal dari tabel beku, bukan `subject_report_score` — uji dengan
  mengubah `subject_report_score` setelah generate lalu pastikan payload tidak
  ikut berubah.
- Menandai `report_type` penentu kedua ditolak di command layer.
- Consumer idempoten: event yang sama dua kali → keadaan sama.
- Delete-then-upsert: rapor ulang dengan mapel lebih sedikit tidak meninggalkan
  baris yatim.
- Isolasi tenant pada kedua projection.
- Skor tetap masuk projection meski `is_promotion_source` bernilai `false`.
