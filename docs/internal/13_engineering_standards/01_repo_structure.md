# Repository Structure (Backend Monorepo)

The backend monorepo is mounted in the parent repo as a submodule at
`apps/backend`. Inside that submodule the layout is:

```
/apps/backend
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

The web frontend (Next.js) lives in a separate submodule at `apps/web`
(`git@github.com:protocyber/akademiq-web.git`) and is out of scope for
this document.
