# API Conventions

## Base URL
`/api/v1/{service}`

## Authentication
Header: `Authorization: Bearer <JWT>`

## Success Response
```json
{ "data": {}, "meta": {} }
```

## Error Response
```json
{
  "error": {
    "code": "STRING_CODE",
    "message": "Human readable message"
  }
}
```

## Pagination
`GET /resource?page=1&size=20`