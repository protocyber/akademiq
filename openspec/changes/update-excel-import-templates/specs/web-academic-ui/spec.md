## MODIFIED Requirements

### Requirement: The template files SHALL include guidance and examples

The static `.xlsx` files at `public/templates/students-template.xlsx` and
`teachers-template.xlsx` MUST include:
- Sheet 1 ("Data"): the English header row (row 1) matching the backend's
  expected columns, followed by blank rows for user input.
- Sheet 2 ("Petunjuk"): a column-by-column guide with Indonesian label,
  required/optional status, expected format, and an example value for each
  column.

#### Scenario: Template has a guidance sheet

- **WHEN** a user opens the downloaded template file
- **THEN** they see a "Petunjuk" sheet with Indonesian labels, format hints,
  and examples for every column

#### Scenario: Data sheet headers match backend expectation

- **WHEN** the user fills in the "Data" sheet and uploads it
- **THEN** the headers in row 1 exactly match the backend's expected English
  field names, and the import validates successfully
