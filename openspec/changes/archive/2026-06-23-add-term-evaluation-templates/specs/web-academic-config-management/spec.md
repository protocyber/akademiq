## ADDED Requirements

### Requirement: The term edit form SHALL provide an Evaluasi tab after the Rapor tab

The term (semester) edit form at `/settings/academic/terms` MUST present its tabs in the order **Info, Status, Rapor, Evaluasi**. The Evaluasi tab MUST appear after the Rapor tab because its weight matrix columns are the report types managed in the Rapor tab. The Evaluasi tab MUST reuse the "Kelola Evaluasi" experience: a template evaluation list (add, edit, delete, reorder) plus a weight matrix whose columns are the term's report types. The tab MUST be available only to admins permitted to manage academic configuration.

#### Scenario: Evaluasi tab is shown after Rapor

- **WHEN** an admin opens the edit form for a term
- **THEN** the tabs read Info, Status, Rapor, Evaluasi in that order

#### Scenario: Editing template evaluations

- **WHEN** the admin adds a template evaluation on the Evaluasi tab and saves
- **THEN** the template evaluation is persisted for that term and appears in the list in `position` order

#### Scenario: Weight matrix columns are the term's report types

- **WHEN** the admin opens the Evaluasi tab for a term that has report types defined on the Rapor tab
- **THEN** the weight matrix shows one column per report type and accepts weights that must total 100% per report type before saving

### Requirement: The term edit form SHALL let admins apply the template to existing assignments

The Evaluasi tab MUST provide an action to apply the term's template (evaluations and weights) to all teaching assignments in the term that have no evaluations yet. The action MUST report how many assignments were filled and MUST be safe to invoke repeatedly. The tab MUST surface a nudge when assignments in the term still lack evaluations.

#### Scenario: Apply button fills assignments lacking evaluations

- **WHEN** the admin clicks "Terapkan daftar evaluasi ini untuk semua penugasan" for a term with template entries
- **THEN** assignments without evaluations receive the template's evaluations and the admin sees how many were filled

#### Scenario: Nudge reflects remaining work

- **WHEN** the term has assignments without evaluations
- **THEN** the Evaluasi tab shows a count of assignments that still need the template applied
