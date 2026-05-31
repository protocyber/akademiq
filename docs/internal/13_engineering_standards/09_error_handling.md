# Error Handling Standards

Use shared error format across services.

## Error Structure
```rust
pub struct ApiError {
    pub code: String,
    pub message: String,
}
```

Map internal errors to standardized API errors.