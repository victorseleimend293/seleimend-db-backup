# Changelog

All notable changes to this project will be documented in this file. See [Conventional Commits](https://www.conventionalcommits.org/) for commit guidelines.

## 1.0.0 (2026-10-03)

* fix(ci): bypass git hooks in CI and ignore changelog from prettier formatting ([b2891ab](https://github.com/victorseleimend293/seleimend-db-backup/commit/b2891ab))
* feat(core): add container entrypoint, backup, and restore scripts ([4f3d923](https://github.com/victorseleimend293/seleimend-db-backup/commit/4f3d923))
* feat(core): implement code quality tooling, test suite, and automated releases ([e70f1ac](https://github.com/victorseleimend293/seleimend-db-backup/commit/e70f1ac))
* feat(docker): add production multi-arch Dockerfile ([899c1ec](https://github.com/victorseleimend293/seleimend-db-backup/commit/899c1ec))
* feat(k8s): add Kubernetes CronJob manifests and secret templates ([df47341](https://github.com/victorseleimend293/seleimend-db-backup/commit/df47341))
* docs: add comprehensive README with setup, architecture, and DR guide ([306224d](https://github.com/victorseleimend293/seleimend-db-backup/commit/306224d))
* ci: add GitHub Actions workflow for shell script linting and docker build ([e3c7484](https://github.com/victorseleimend293/seleimend-db-backup/commit/e3c7484))
* chore: initial repository configuration with MIT license and gitignore ([ea43fe1](https://github.com/victorseleimend293/seleimend-db-backup/commit/ea43fe1))

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
