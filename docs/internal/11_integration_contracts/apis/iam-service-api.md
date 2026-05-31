# IAM Service API

## POST /auth/login
Request:
```json
{ "email": "string", "password": "string" }
```
Response:
```json
{ "access_token": "jwt", "refresh_token": "jwt" }
```

## GET /users/{id}
Returns user profile and tenant roles.