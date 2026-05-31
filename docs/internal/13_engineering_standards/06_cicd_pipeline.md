# CI/CD Pipeline Design

## On Pull Request
- Run tests
- Run linting

## On Merge to Main
- Build Docker image
- Push to container registry

## On Tag Release
- Deploy to staging

## Production Deployment
- Manual approval required