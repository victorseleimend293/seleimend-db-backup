# Changelog

All notable changes to this project will be documented in this file. See [Conventional Commits](https://www.conventionalcommits.org/) for commit guidelines.

## [1.0.0] - 2026-10-03

### Features

- **core**: add container entrypoint, streaming backup, and disaster recovery restore scripts.
- **docker**: add production multi-architecture Dockerfile (`linux/amd64`, `linux/arm64`) with non-root security context.
- **k8s**: add Kubernetes `CronJob` manifests and secret templates.

### CI/CD & DevOps

- configure GitHub Actions CI/CD workflow for automated linting, test suite with 100% coverage, and multi-arch GHCR publishing.
- configure semantic versioning, changelog automation, commitlint, and husky git hooks.

### Documentation

- add comprehensive README with architecture diagram, B2 setup guide, Kubernetes/Docker Compose deployment, and disaster recovery workflows.
