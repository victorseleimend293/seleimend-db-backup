# Changelog

All notable changes to this project will be documented in this file. See [Conventional Commits](https://www.conventionalcommits.org/) for commit guidelines.

## <small>1.1.4 (2026-10-04)</small>

* refactor(dr): remove obsolete DR_HEALTHCHECK_URL references ([1262a85](https://github.com/victorseleimend293/seleimend-db-backup/commit/1262a85))

## <small>1.1.3 (2026-10-04)</small>

* fix(security): resolve Docker Scout vulnerabilities by updating base image and binaries ([e5bcddd](https://github.com/victorseleimend293/seleimend-db-backup/commit/e5bcddd))
* docs(readme): render architecture diagram as SVG for Docker Hub compatibility ([af3cf02](https://github.com/victorseleimend293/seleimend-db-backup/commit/af3cf02))

## <small>1.1.2 (2026-10-04)</small>

* fix(ci): pass interactive stdin to psql in database seeding step ([2a3332c](https://github.com/victorseleimend293/seleimend-db-backup/commit/2a3332c))

## <small>1.1.1 (2026-10-04)</small>

* fix(ci): fix S3 test container, terraform warning and dockerhub metadata ([d6849b1](https://github.com/victorseleimend293/seleimend-db-backup/commit/d6849b1))

## 1.1.0 (2026-10-03)

* feat(dr): add disaster recovery drills, b2 terraform and unified deployment ([56f49e4](https://github.com/victorseleimend293/seleimend-db-backup/commit/56f49e4))

## <small>1.0.1 (2026-10-03)</small>

* fix(ci): point GitGuardian action to ggshield-action repository ([012a1a5](https://github.com/victorseleimend293/seleimend-db-backup/commit/012a1a5))
* ci(security): add GitGuardian secret scanning and consolidate changelog ([46c15c6](https://github.com/victorseleimend293/seleimend-db-backup/commit/46c15c6))

## 1.0.0 (2026-10-03)

### Features

* **core**: add container entrypoint, streaming backup, and disaster recovery restore scripts ([4f3d923](https://github.com/victorseleimend293/seleimend-db-backup/commit/4f3d923))
* **core**: implement code quality tooling, test suite, and automated releases ([e70f1ac](https://github.com/victorseleimend293/seleimend-db-backup/commit/e70f1ac))
* **docker**: add production multi-architecture Dockerfile (`linux/amd64`, `linux/arm64`) with non-root security context ([899c1ec](https://github.com/victorseleimend293/seleimend-db-backup/commit/899c1ec))
* **k8s**: add Kubernetes `CronJob` manifests and secret templates ([df47341](https://github.com/victorseleimend293/seleimend-db-backup/commit/df47341))

### Bug Fixes

* **ci**: bypass git hooks in CI and ignore changelog from prettier formatting ([b2891ab](https://github.com/victorseleimend293/seleimend-db-backup/commit/b2891ab))

### CI/CD & DevOps

* **ci**: add GitHub Actions workflow for automated linting, test suite with 100% coverage, and multi-arch GHCR publishing ([e3c7484](https://github.com/victorseleimend293/seleimend-db-backup/commit/e3c7484))

### Documentation

* **docs**: add comprehensive README with architecture diagram, B2 setup guide, Kubernetes/Docker Compose deployment, and disaster recovery workflows ([306224d](https://github.com/victorseleimend293/seleimend-db-backup/commit/306224d))

### Maintenance

* **chore**: initial repository configuration with MIT license and gitignore ([ea43fe1](https://github.com/victorseleimend293/seleimend-db-backup/commit/ea43fe1))
