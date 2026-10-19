# Promotion Letters (Plan 3e) — Design Spec

Date: 2026-10-18
Status: approved in brainstorming (Q1–Q6, approach 1, sections 1–4); awaiting written-spec review
Topic: SK Kenaikan Kelas and Surat Keterangan Lulus — principal data, stored letter numbers, printing
Parent: `2026-09-23-promotion-design.md` §8 (Cetak SK). Previous: `2026-10-12-promotion-ui-design.md` (3d).

## 1. Goal

After a promotion run is `executed`, the school issues and prints two official
letters:

- **SK Kenaikan Kelas** — one per source homeroom, listing every student of
  that class and their result (promoted to …, retained in …, graduated).
- **Surat Keterangan Lulus** — one per graduating student.

Letters are React A4 components with `@media print`, like
`report-card-print-document.tsx`. No PDF generator, no template builder.

**Done means:** an admin records the principal's name in the school profile;
on an executed run the admin issues an SK for every source class and a
certificate number for every graduate; the principal opens and prints both;
a year later, reprinting gives the same number, date, and principal name even
if the principal has changed.

### 1.1 Decisions from brainstorming

| # | Question | Decision |
|---|---|---|
| Q1 | Where the principal's name/NIP live | Two free-text fields on the school profile (billing `tenant`), plus a snapshot on every issued letter |
| Q2 | Letter number and date | Stored as letter records in academic-ops (not typed at print time) |
| Q3 | Graduation certificate numbers | Pattern + start number filled in by the web, previewed, correctable per student; class SK numbers typed by hand |
| Q4 | Editing an issued letter | Allowed in place; `updated_by` / `updated_at` recorded; snapshot refreshed only on explicit request |
| Q5 | How academic-ops gets the principal | New event `tenant.school_profile_updated` → projection `known_school_profile`; snapshot taken server-side |
| Q6 | Permissions | Issue / correct: `promotion.manage`. Read / print: `promotion.manage` or `promotion.approve`. No new permission |
| Approach | Storage shape | 1: dedicated `promotion_class_letter` table + extended `graduation_record` |

### 1.2 Deviations from `docs/internal/`

- `docs/internal/10_data_design/02_Billing_Service_ERD.md` says the school
  profile deliberately has no principal ("deferred until document/signature
  requirements need it"). That requirement is this plan. The link is free text,
  not a teacher or user reference (Q1). Update the ERD.
- `graduation_record.certificate_number` (V16) gets the endpoint it was
  reserved for, plus letter metadata columns.

## 2. Principal data and the school-profile event

### 2.1 Billing

Migration `V5__tenant_principal.sql` adds two nullable columns to `tenant`:
`principal_name VARCHAR(200)`, `principal_nip VARCHAR(64)`.

`GET /tenants/me/school-profile` returns both. `PATCH` accepts both with the
existing semantics (key absent = unchanged, `null` = cleared, string trimmed;
blank → `null`). `principal_nip` is optional — private schools and TPQs often
have none.

The web School Profile page (`/settings/school-profile`) gains a "Kepala
Sekolah" section with Nama and NIP.

### 2.2 Event `tenant.school_profile_updated`

Written to billing's outbox in the same transaction as every successful
school-profile PATCH and every logo upload/delete. It always carries the full
current letterhead state, not a diff:

```json
{
  "tenant_id": "uuid",
  "school_name": "SMP Negeri 1",
  "npsn": "20531234",
  "principal_name": "Dra. Siti Rahayu, M.Pd.",
  "principal_nip": "196805121993032004",
  "address_line": "Jl. Pemuda 1",
  "village": "Embong Kaliasin",
  "subdistrict": "Genteng",
  "city_regency": "Surabaya",
  "province": "Jawa Timur",
  "postal_code": "60271",
  "phone_number": "031-123456",
  "email": "info@smpn1.sch.id",
  "logo_url": "/api/v1/billing/media/school/<media_id>",
  "updated_at": "RFC3339"
}
```

Every field except `tenant_id`, `school_name` and `updated_at` may be `null`.
`logo_url` is the resolved public serve path (the same value
`GET /school-profile` returns; `GET /media/...` needs no token), so a print
page can render it without billing permissions.
Exchange `akademiq.events`, routing key `tenant.school_profile_updated`.
Consumer: academic-ops.

### 2.3 Academic-ops projections

**`known_school_profile`** — one row per tenant with the payload fields.
Upsert only when the incoming `updated_at` is newer than the stored one, so a
late, older event never overwrites a newer one. No dependency on other
projections.

**`known_academic_year.name`** — new nullable column, set from
`academic_year.created` (its payload already carries `name`). Letters and
print data need the source and target year names, and the principal holds
no `academic.config.read`. A rename in academic-config emits no event today,
so a renamed year keeps its old name here (recorded in the backlog).

`scripts/bootstrap-projections.sh` gains a `run_upsert` step copying
`billing.tenant` into `academic_ops.known_school_profile`, and its existing
`known_academic_year` step also copies `name`.

### 2.4 Why the print pages read only academic-ops

The principal prints letters (Q6) but holds neither `billing.manage` (school
profile) nor `academic.config.read` (year names). Every fact a print page
needs — letterhead, year names, student identity, letter snapshot — is
therefore returned by the academic-ops print endpoints from the two
projections above. The letterhead (logo, address, contact) is read live from
`known_school_profile`; only `school_name`, `principal_name`, `principal_nip`
are snapshotted on the letter (Q1).

### 2.5 No principal → no letter

Issuing a letter (first issue or refresh) when the projection has no row or a
blank `principal_name` is rejected with `400 VALIDATION_ERROR` on field
`principal`: "school profile has no principal name". A letter without a
signatory name is worse than no letter.

## 3. Letter records and API (academic-ops)

### 3.1 Migration `V20__promotion_letters.sql`

```sql
CREATE TABLE IF NOT EXISTS known_school_profile (
  tenant_id      UUID PRIMARY KEY,
  school_name    VARCHAR(200) NOT NULL,
  npsn           VARCHAR(32),
  principal_name VARCHAR(200),
  principal_nip  VARCHAR(64),
  address_line   VARCHAR(500),
  village        VARCHAR(200),
  subdistrict    VARCHAR(200),
  city_regency   VARCHAR(200),
  province       VARCHAR(200),
  postal_code    VARCHAR(16),
  phone_number   VARCHAR(64),
  email          VARCHAR(320),
  logo_url       VARCHAR(500),
  updated_at     TIMESTAMPTZ NOT NULL
);

ALTER TABLE known_academic_year ADD COLUMN IF NOT EXISTS name VARCHAR(100);

CREATE TABLE IF NOT EXISTS promotion_class_letter (
  letter_id      UUID PRIMARY KEY,
  tenant_id      UUID NOT NULL,
  run_id         UUID NOT NULL REFERENCES promotion_run (run_id),
  homeroom_id    UUID NOT NULL,
  letter_number  VARCHAR(64) NOT NULL,
  letter_date    DATE NOT NULL,
  city           VARCHAR(200) NOT NULL,
  school_name    VARCHAR(200) NOT NULL,
  principal_name VARCHAR(200) NOT NULL,
  principal_nip  VARCHAR(64),
  issued_by      UUID NOT NULL,
  issued_at      TIMESTAMPTZ NOT NULL,
  updated_by     UUID NOT NULL,
  updated_at     TIMESTAMPTZ NOT NULL,
  CONSTRAINT promotion_class_letter_run_homeroom_unique UNIQUE (run_id, homeroom_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS promotion_class_letter_number_uidx
  ON promotion_class_letter (tenant_id, letter_number);

ALTER TABLE graduation_record
  ADD COLUMN IF NOT EXISTS letter_date    DATE,
  ADD COLUMN IF NOT EXISTS city           VARCHAR(200),
  ADD COLUMN IF NOT EXISTS school_name    VARCHAR(200),
  ADD COLUMN IF NOT EXISTS principal_name VARCHAR(200),
  ADD COLUMN IF NOT EXISTS principal_nip  VARCHAR(64),
  ADD COLUMN IF NOT EXISTS issued_by      UUID,
  ADD COLUMN IF NOT EXISTS issued_at      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS updated_by     UUID,
  ADD COLUMN IF NOT EXISTS updated_at     TIMESTAMPTZ;
CREATE UNIQUE INDEX IF NOT EXISTS graduation_record_certificate_number_uidx
  ON graduation_record (tenant_id, certificate_number)
  WHERE certificate_number IS NOT NULL;
```

Every `certificate_number` is NULL today, so the partial unique index is safe.
A graduate is "issued" when `certificate_number IS NOT NULL`.

Only letter facts are snapshotted (school, principal, number, date, city).
Student facts (name, NIS, NISN, birth place/date) are read live at print time,
so a corrected student name flows into reprints.

### 3.2 Endpoints

Base `/api/v1/academic-ops`, gate `academic_ops`, tenant from the JWT. Every
endpoint requires the run to be `executed`; otherwise `409
PROMOTION_RUN_INVALID_STATUS`. Unknown or foreign run → `404`.

| Endpoint | Permission | Behaviour |
|---|---|---|
| `GET /promotion-runs/:run_id/letters` | manage or approve | Summary: `school_profile` (projection row or `null`), `class_letters[]` (one per source homeroom: `homeroom_id`, `homeroom_name`, counts by result, `letter` or `null`), `certificates { graduates, issued }` |
| `GET /promotion-runs/:run_id/class-letters/:homeroom_id` | manage or approve | Print data: `letterhead` (live `known_school_profile` row or `null`), `source_year_name`, `target_year_name`, `homeroom_name`, the letter (or `null` → web shows "belum terbit"), and rows `{student_id, full_name, nis, nisn, result, target_homeroom_name}` ordered by name |
| `PUT /promotion-runs/:run_id/class-letters/:homeroom_id` | manage | Body `{letter_number, letter_date, city?}`. First call inserts with a snapshot and `issued_*` = `updated_*`. Later calls change number/date/city and `updated_*` only. Response: the letter |
| `GET /promotion-runs/:run_id/certificates?student_id=` | manage or approve | `{letterhead, source_year_name, certificates: [...]}`; each certificate `{student_id, full_name, nis, nisn, birth_place, birth_date, last_homeroom_name, graduation_date, certificate_number, letter_date, city, school_name, principal_name, principal_nip}` (letter fields `null` until issued); optional filter to one student |
| `PUT /promotion-runs/:run_id/certificates` | manage | Body `{letter_date, city?, items:[{student_id, certificate_number}]}`, 1–2,000 items, all-or-nothing. Graduates issued for the first time get a snapshot and `issued_*`; already-issued ones get number/date/city and `updated_*`. Response `{updated: n}` |
| `POST /promotion-runs/:run_id/letters/refresh-principal` | manage | Re-snapshots `school_name`, `principal_name`, `principal_nip` on every issued letter of the run (class letters and certificates), sets `updated_*`. Response `{updated: n}` |

`homeroom_id` must be a source homeroom of the run (some decision's
`homeroom_id`), else `404`. `city` absent or blank → `known_school_profile.city_regency`;
both blank → `400` on `city`.

### 3.3 Validation (`400 VALIDATION_ERROR`, English messages as elsewhere)

| Field | Message | When |
|---|---|---|
| `letter_number` / `certificate_number` | `is required` / `must be at most 64 characters` | Trimmed value empty / too long |
| `letter_number` | `is already used by another letter` | 23505 on `promotion_class_letter_number_uidx` |
| `letter_date` | `is required` | Missing |
| `city` | `is required` | No value and no profile city |
| `principal` | `school profile has no principal name` | §2.5 |
| `items` | `must contain between 1 and 2000 items` | Size |
| `items` | `student <id>: not a graduate of this run` | No `graduate` decision for that student in this run |
| `items` | `student <id>: listed more than once` | Duplicate student in batch |
| `items` | `student <id>: certificate number <n> is used twice in this request` | Duplicate number in batch |
| `items` | `student <id>: certificate number <n> is already used by another letter` | Number held by another graduation record of the tenant (checked before write; 23505 on the partial index maps to the same message) |

23505 → 400 only for the two letter indexes; any other database error stays
500. No new error codes. No outbound events (nothing consumes letters).

## 4. Web

### 4.1 "Surat" tab on the run detail

Visible only when the run is `executed`. Editable with `promotion.manage`,
read-only and printable with `promotion.approve`.

Header card "Data kepala sekolah": name, NIP, city from `school_profile`. When
the name is missing, an alert links to `/settings/school-profile` and every
issue button is disabled. For a run with issued letters, "Perbarui data kepala
sekolah" calls refresh after confirming "N surat akan memakai data kepala
sekolah terbaru".

**SK Kenaikan Kelas section** — one row per source homeroom: class, counts
(naik / tinggal / lulus), number, date, status ("Belum terbit" or "Terbit ·
diubah <date>"). "Terbitkan" / "Ubah" opens a dialog (Zod + RHF): Nomor SK,
Tanggal (default today), Kota (default from profile); 400 field errors map to
the form. "Cetak" opens `/promotion/[runId]/print/class-letter/[homeroomId]`
in a new tab; disabled until issued.

**Surat Keterangan Lulus section** — shown when the run has graduates.
"Isi nomor dari pola" dialog: Pola (must contain `{n}`, e.g.
`421.3/{n}/SMP-X/2026`), Nomor awal, Jumlah digit, Tanggal, Kota. A pure
function `buildCertificateNumbers` orders graduates by class then name and
fills the draft; by default it fills only rows without a number, with an
explicit "Timpa nomor yang sudah ada" checkbox. The graduates table (name,
NIS, class, number) allows inline correction; the draft is local with an
unsaved indicator and `beforeunload`, like the placement tab. Duplicate
numbers inside the draft are flagged before sending. "Simpan" sends one PUT
with the rows whose number differs from the saved one; `student <id>:` errors
map to rows. "Cetak semua" opens `/promotion/[runId]/print/certificates`
(issued graduates, one A4 page each); "Cetak" per row adds `?student=<id>`.

### 4.2 Print documents

Both reuse `ReportCardPrintStyles` (A4, `@media print`) and the report-card
print page pattern: load, then `window.print()`, with a Back button that does
not print. Each page makes one academic-ops call (§2.4); no billing or
academic-config request. Letter facts come from the stored snapshot; the
letterhead comes from `letterhead`.

**SK Kenaikan Kelas:** letterhead (logo, NPSN, address and contact from the
response's `letterhead`; school name from the letter snapshot), title "SURAT KEPUTUSAN KEPALA SEKOLAH", number, subject
"Kenaikan Kelas Tahun Ajaran <source year>", a fixed decision paragraph, a
table (No, Nama, NIS / NISN, Hasil: "Naik ke kelas <target>", "Tinggal di
kelas <target>", "Lulus"), "<city>, <date>", signature block (Kepala Sekolah,
space, name, "NIP. …" only when present). Long tables continue on later pages
with a repeated `thead`; the signature block is `break-inside-avoid`.

**Surat Keterangan Lulus:** same letterhead, title "SURAT KETERANGAN LULUS",
number, "Yang bertanda tangan di bawah ini, Kepala <school> menerangkan
bahwa:", student identity (name, place/date of birth, NIS, NISN, last class),
"telah LULUS dari <school> pada Tahun Ajaran <source year>", graduation date,
same signature block.

Letter text is fixed in code (template builder is backlog).

Print pages use `PromotionPage` for the manage-or-approve guard. An unissued
letter or a run that is not executed shows an alert, never an empty document.

### 4.3 Errors

New copy lives in `src/lib/errors/messages.ts`. Field labels for
`promotionFieldGroups`: `letter_number` "Nomor SK", `certificate_number`
"Nomor surat", `letter_date` "Tanggal surat", `city` "Kota", `principal`
"Kepala sekolah", `items` "Daftar lulusan". `student <id>` is replaced by the
student's name (`withStudentNames`). A 409 shows an alert and refetches.

## 5. Testing

Backend (targeted per task; full suites once at the final gate, §7.1):

- Billing: PATCH stores/returns/clears the principal fields; every PATCH and
  logo change writes one `tenant.school_profile_updated` outbox row with the
  full payload.
- Academic-ops projection: upsert, older event ignored, tenant isolation.
- Class letter: first issue snapshots; correction changes only
  number/date/city and `updated_*`; city default; no principal → 400
  `principal`; non-executed run → 409; non-source homeroom → 404; duplicate
  number in tenant → 400.
- Certificates: all-or-nothing; the four `student <id>:` messages; 2,000 cap;
  first issue vs correction.
- Refresh: replaces snapshots on this run's letters only.
- Print data: class rows survive closed source enrollments; certificate data
  carries birth place/date; both carry the letterhead and year names, and a
  principal (approve-only) token reads them.
- `academic_year.created` stores `name` on `known_academic_year`.
- Every endpoint rejects a foreign tenant.
- E2E (RabbitMQ): billing PATCH → `known_school_profile` row.

Web (Vitest): `buildCertificateNumbers` (requires `{n}`, padding, ordering,
keeps corrections unless overwrite is chosen, duplicate detection); dialog
schemas; letters tab locked without a principal; class-letter dialog maps
field errors; graduates table maps row errors; both print documents render
the snapshot and hide an empty NIP; school-profile form sends the principal
fields. No Playwright.

## 6. Contract docs

- `apis/billing-service-api.md`: principal fields on the school profile.
- New `events/tenant.school_profile_updated.md`.
- `apis/promotion-service-api.md`: "Letters" section (six endpoints, §3.3 table).
- `10_data_design/02_Billing_Service_ERD.md` (principal) and the academic-ops /
  promotion ERD (letter tables).
- `scripts/bootstrap-projections.sh`: the new `known_school_profile` step and
  `name` in the `known_academic_year` step.
- `events/academic-year-created.md`: academic-ops now projects `name`.

## 7. Out of scope

Recorded in `docs/superpowers/backlog.md` (Promotion — product scope):
template builder, server-side PDF, digital signature / QR, cancel-and-reissue,
number history, a `promotion.letters` permission, letters for retained
students, transcript attachment.
