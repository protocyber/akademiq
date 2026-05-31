# Validation Error Contract

Validation errors must follow this structure:

{
  "error": {
    "code": "VALIDATION_ERROR",
    "fields": {
      "field_name": ["error message", "another error message"],
      "another_field": ["error message", "..."]
    }
  }
}

Must align with frontend Zod validation format.
