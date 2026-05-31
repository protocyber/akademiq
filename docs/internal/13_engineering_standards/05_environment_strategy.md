# Environment Strategy

| Environment | Purpose |
|-------------|---------|
| local | Developer machines |
| dev | Shared integration |
| staging | Pre-production |
| prod | Production |

Each environment must have:
- Separate database
- Separate message broker
- Separate object storage