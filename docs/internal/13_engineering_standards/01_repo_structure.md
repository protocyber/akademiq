# Repository Structure (Monorepo)

```
/backend
  /services
    /iam-service
    /billing-service
    /academic-config-service
    /academic-ops-service
    /attendance-service
    /grading-service
    /promotion-service
    /notification-service
  /libs
    /common-auth
    /common-db
    /common-logging
    /common-errors
```

Each service must be independently buildable and deployable.