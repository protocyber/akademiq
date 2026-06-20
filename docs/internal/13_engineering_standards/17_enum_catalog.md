# Enum Catalog — Canonical Values

This document is the single source of truth for enumerated value sets used across
AcademiQ backend services and the web frontend. Backend CHECK constraints, domain
`FromStr`/`as_str` impls, and frontend Zod enum schemas MUST use exactly these values
(including casing: all lowercase snake_case).

## School profile (Billing)

### `school_level`
| Value | Meaning |
|-------|---------|
| `sd` | Sekolah Dasar |
| `smp` | Sekolah Menengah Pertama |
| `sma` | Sekolah Menengah Atas |
| `mi` | Madrasah Ibtidaiyah |
| `mts` | Madrasah Tsanawiyah |
| `ma` | Madrasah Aliyah |
| `slb` | Sekolah Luar Biasa |
| `lainnya` | Lainnya |

### `school_status`
| Value | Meaning |
|-------|---------|
| `negeri` | Negeri (public) |
| `swasta` | Swasta (private) |

### `accreditation`
| Value | Meaning |
|-------|---------|
| `a` | Akreditasi A |
| `b` | Akreditasi B |
| `c` | Akreditasi C |
| `belum_terakreditasi` | Belum terakreditasi |

## Person profile status (Academic Ops)

### Student / Teacher / Family `status`
| Value | Meaning |
|-------|---------|
| `aktif` | Active |
| `nonaktif` | Inactive |
| `arsip` | Archived |

### Student `archive_reason`
| Value | Meaning |
|-------|---------|
| `nonaktif_sementara` | Temporarily inactive |
| `lulus` | Graduated |
| `pindah` | Transferred to another school |
| `keluar` | Left |
| `meninggal` | Deceased |
| `lainnya` | Other |

### Teacher `archive_reason`
| Value | Meaning |
|-------|---------|
| `nonaktif_sementara` | Temporarily inactive |
| `resign` | Resigned |
| `mutasi` | Transferred (mutation) |
| `pensiun` | Retired |
| `meninggal` | Deceased |
| `lainnya` | Other |

### Family `archive_reason`
| Value | Meaning |
|-------|---------|
| `tidak_aktif` | No longer active |
| `meninggal` | Deceased |
| `putus_hubungan` | Lost contact / relationship severed |
| `duplikat` | Duplicate profile |
| `lainnya` | Other |

## Family / relationship attributes (Academic Ops)

### `relationship_type` (student-family link)
| Value | Meaning |
|-------|---------|
| `ayah` | Father |
| `ibu` | Mother |
| `wali` | Guardian / sponsor |
| `kakek` | Grandfather |
| `nenek` | Grandmother |
| `saudara` | Sibling |
| `lainnya` | Other |

### Student-family link `status`
| Value | Meaning |
|-------|---------|
| `aktif` | Active link |
| `nonaktif` | Inactive link |

## Media (Billing + Academic Ops)

### `owner_type`
| Value | Owner service | Meaning |
|-------|---------------|---------|
| `school` | Billing | School logo |
| `teacher` | Academic Ops | Teacher photo |
| `student` | Academic Ops | Student photo |
| `family` | Academic Ops | Family profile photo |

### Allowed upload content types
| Value |
|-------|
| `image/jpeg` |
| `image/png` |
| `image/webp` |

Maximum upload size: **2 MB** (2_097_152 bytes).

## Demographic reference fields

These are administrative reference fields on person profiles. They are stored as
free-text-normalized lowercase strings but have recommended canonical value sets.

### `gender` (student / teacher)
| Value | Meaning |
|-------|---------|
| `male` | Laki-laki |
| `female` | Perempuan |
| `other` | Lainnya |

### `religion`
| Value | Meaning |
|-------|---------|
| `islam` | Islam |
| `kristen` | Kristen |
| `katolik` | Katolik |
| `hindu` | Hindu |
| `buddha` | Buddha |
| `khonghucu` | Khonghucu |
| `lainnya` | Lainnya |

### `education_level` (teacher / family)
| Value | Meaning |
|-------|---------|
| `sd` | SD |
| `smp` | SMP |
| `sma_smk` | SMA / SMK |
| `d1` | Diploma I |
| `d2` | Diploma II |
| `d3` | Diploma III |
| `d4` | Diploma IV |
| `s1` | Sarjana (S1) |
| `s2` | Magister (S2) |
| `s3` | Doktor (S3) |
| `lainnya` | Lainnya |

### `employment_status` (teacher)
| Value | Meaning |
|-------|---------|
| `pns` | PNS |
| `pppk` | PPPK |
| `gtt` | GTT (Guru Tidak Tetap) |
| `gty` | GTY (Guru Tidak Tetap Yayasan) |
| `honorer` | Honorer |
| `lainnya` | Lainnya |

### `life_status` (family)
| Value | Meaning |
|-------|---------|
| `hidup` | Alive |
| `meninggal` | Deceased |

### `marital_status` (family)
| Value | Meaning |
|-------|---------|
| `kawin` | Married |
| `belum_kawin` | Not married |
| `cerai` | Divorced |
| `lainnya` | Other |

### `income_range` (family)
| Value | Meaning |
|-------|---------|
| `di_bawah_1_juta` | < Rp 1.000.000 |
| `1_3_juta` | Rp 1.000.000 – 3.000.000 |
| `3_5_juta` | Rp 3.000.000 – 5.000.000 |
| `5_10_juta` | Rp 5.000.000 – 10.000.000 |
| `10_20_juta` | Rp 10.000.000 – 20.000.000 |
| `di_atas_20_juta` | > Rp 20.000.000 |
| `tidak_berpenghasilan` | No income |
| `lainnya` | Other |
