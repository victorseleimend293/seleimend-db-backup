# seleimend-db-backup

[![CI/CD](https://github.com/victorseleimend293/seleimend-db-backup/actions/workflows/ci.yml/badge.svg)](https://github.com/victorseleimend293/seleimend-db-backup/actions/workflows/ci.yml)
[![Docker Image](https://img.shields.io/badge/docker-ghcr.io-blue.svg)](https://github.com/victorseleimend293/seleimend-db-backup/pkgs/container/seleimend-db-backup)
[![Coverage: 100%](https://img.shields.io/badge/coverage-100%25-brightgreen.svg)](https://github.com/victorseleimend293/seleimend-db-backup)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)
[![Semantic Release](https://img.shields.io/badge/%20%20%F0%9F%93%A6%F0%9F%9A%80-semantic--release-e10079.svg)](https://github.com/semantic-release/semantic-release)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17%20%7C%2016%20%7C%2015-336791.svg?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Storage: Backblaze B2](<https://img.shields.io/badge/storage-Backblaze%20B2%20(S3)-red.svg>)](https://www.backblaze.com/b2/)

An enterprise-ready, containerized PostgreSQL backup agent that streams compressed, encrypted database snapshots directly to **Backblaze B2** (via its S3-compatible API). Designed for zero local disk overhead, least-privilege security, modular DRY/KISS architecture, and seamless deployment as a **Kubernetes `CronJob`** or a **Docker Compose** service.

---

## Architecture Overview

```mermaid
flowchart TD
    subgraph K8sCluster ["Kubernetes Cluster / Compose Environment"]
        Cron["Kubernetes CronJob<br/>(Schedule: 0 2 * * *)"]
        Container["seleimend-db-backup<br/>(UID 10001, Non-Root)"]
        Postgres[("PostgreSQL Database<br/>(Production Cluster)")]

        Cron -->|Spawns Pod| Container
        Container -->|"pg_dump -Fc (stream)"| Postgres
    end

    subgraph BackblazeB2 ["Offsite Object Storage (Backblaze B2)"]
        Bucket[("Backblaze B2 Bucket<br/>(seleimend-db-backups)")]
    end

    Container -->|"Direct S3 Multipart Stream<br/>(Zero Disk Overhead, Zero Egress)"| Bucket

    style Container fill:#e8f5e9,stroke:#4caf50
    style Bucket fill:#fff3e0,stroke:#ff9800
    style Postgres fill:#e1f5fe,stroke:#03a9f4
```

---

## Key Features

- **Direct Memory Streaming**: `pg_dump` is piped directly into Backblaze B2 via AWS CLI streaming multipart uploads. Dumps are never staged onto the local disk, eliminating container disk starvation and scratch space sizing headaches.
- **Zero Egress Fees & Low Storage Costs**: Powered by Backblaze B2's high-durability storage ($0.006/GB/month) with free egress, ensuring disaster recovery restores never cause unexpected bandwidth bills.
- **Strict Security Context (Non-Root)**: The image runs as a non-privileged user (`backup:backup`, UID `10001`), supporting `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, and `capabilities: drop: ["ALL"]`.
- **Custom Compressed Format (`-Fc`)**: Generates PostgreSQL custom format archives supporting parallel restoration, selective schema/table extraction, and built-in compression.
- **Kubernetes Native**: Includes production manifests for Kubernetes `batch/v1` `CronJob` with `concurrencyPolicy: Forbid` and resource boundaries.
- **Docker Compose & Daemon Mode**: Built-in support for `supercronic` to run as a background cron daemon when `CRON_SCHEDULE` is set.
- **Disaster Recovery Restore Tooling**: Includes `restore.sh` to quickly list remote snapshots, download the target backup, and restore it into any PostgreSQL instance.
- **Healthcheck & Monitoring Alerts**: Optional webhook integration with healthcheck services (e.g., [healthchecks.io](https://healthchecks.io/), BetterStack, Discord/Slack webhooks).
- **Clean Architecture & 100% Test Coverage**: Fully adheres to DRY and KISS principles with a shared `scripts/common.sh` library, verified by a comprehensive Bats test suite with 100% code coverage.
- **Automated Governance & Releases**: Enforces Conventional Commits via Commitlint and Husky git hooks, automatically publishing semantic releases and multi-arch images to GitHub Container Registry.

---

## Configuration Reference

The container is configured entirely via environment variables (12-Factor App design):

| Variable                | Required  | Description                                               | Example                                               |
| :---------------------- | :-------: | :-------------------------------------------------------- | :---------------------------------------------------- |
| `B2_ENDPOINT`           |  **Yes**  | Backblaze B2 S3 API endpoint                              | `s3.us-west-004.backblazeb2.com`                      |
| `B2_APPLICATION_KEY_ID` |  **Yes**  | Backblaze B2 Application Key ID (or `AWS_ACCESS_KEY_ID`)  | `004a1b2c3d4e5f6...`                                  |
| `B2_APPLICATION_KEY`    |  **Yes**  | Backblaze B2 Application Key (or `AWS_SECRET_ACCESS_KEY`) | `K004...`                                             |
| `B2_BUCKET`             |  **Yes**  | Dedicated Backblaze B2 bucket name                        | `seleimend-db-backups`                                |
| `B2_PREFIX`             |    No     | Subdirectory prefix inside the bucket                     | `production/postgres` _(default: `backups/postgres`)_ |
| `B2_REGION`             |    No     | S3 region identifier                                      | `us-west-004` _(default: `us-east-005`)_              |
| `DATABASE_URL`          | **Yes\*** | Full PostgreSQL connection URI                            | `postgresql://user:pass@db:5432/mydb`                 |
| `DB_HOST`               |   No\*    | PostgreSQL hostname (if `DATABASE_URL` omitted)           | `postgres.default.svc.cluster.local`                  |
| `DB_PORT`               |    No     | PostgreSQL port                                           | `5432`                                                |
| `DB_NAME`               |   No\*    | Target database name                                      | `app_production`                                      |
| `DB_USER`               |   No\*    | PostgreSQL user                                           | `backup_user`                                         |
| `DB_PASSWORD`           |    No     | PostgreSQL password                                       | `super_secret`                                        |
| `RETENTION_DAYS`        |    No     | Days to retain snapshots before pruning                   | `30` _(default: `0` / disabled)_                      |
| `CRON_SCHEDULE`         |    No     | Cron schedule (activates `supercronic` daemon)            | `0 2 * * *`                                           |
| `HEALTHCHECK_URL`       |    No     | Webhook URL for start, success, and failure pings         | `https://hc-ping.com/your-uuid`                       |

_\* Note: Either `DATABASE_URL` or individual connection variables (`DB_HOST`, `DB_NAME`, `DB_USER`) must be specified._

---

## Backblaze B2 Setup Guide

To follow the **Principle of Least Privilege**, create a dedicated bucket and scoped application key:

1. **Create Bucket**:
   - Go to **Backblaze B2 > Buckets > Create a Bucket**.
   - Name: `seleimend-db-backups` (bucket names must be globally unique).
   - Set **Files in Bucket are**: `Private`.
   - _(Recommended)_ Enable **Default Encryption** (SSE-B2).
   - _(Optional)_ Enable **Lifecycle Rules** to automatically delete files older than 30 or 90 days.
2. **Create Scoped Application Key**:
   - Navigate to **App Keys > Add a New Application Key**.
   - Name: `k8s-db-backup-agent`.
   - Allow access to Bucket(s): select `seleimend-db-backups` only.
   - Type of Access: `Read and Write`.
   - Copy the `keyID` (`B2_APPLICATION_KEY_ID`) and `applicationKey` (`B2_APPLICATION_KEY`).
3. **Endpoint**:
   - On the bucket details page, note the **Endpoint** (e.g. `s3.us-west-004.backblazeb2.com`).

---

## Kubernetes Deployment

### 1. Create the Secret

Copy [`k8s/secret.example.yaml`](k8s/secret.example.yaml) to `k8s/secret.yaml`, fill in your credentials, and apply:

```bash
kubectl apply -f k8s/secret.yaml
```

### 2. Deploy the CronJob

Review [`k8s/cronjob.yaml`](k8s/cronjob.yaml) and apply:

```bash
kubectl apply -f k8s/cronjob.yaml
```

### 3. Test Immediately (Manual Trigger)

Trigger an immediate execution without waiting for the cron schedule:

```bash
kubectl create job --from=cronjob/seleimend-db-backup manual-backup-001
kubectl logs -f job/manual-backup-001
```

---

## Docker Compose Deployment

To run as a scheduled sidecar container alongside your database:

```yaml
services:
  postgres:
    image: postgres:17-alpine
    environment:
      POSTGRES_USER: app_user
      POSTGRES_PASSWORD: app_password
      POSTGRES_DB: app_production
    volumes:
      - pgdata:/var/lib/postgresql/data

  backup:
    image: ghcr.io/victorseleimend293/seleimend-db-backup:latest
    restart: unless-stopped
    depends_on:
      - postgres
    environment:
      CRON_SCHEDULE: '0 2 * * *'
      DATABASE_URL: 'postgresql://app_user:app_password@postgres:5432/app_production'
      B2_ENDPOINT: 's3.us-west-004.backblazeb2.com'
      B2_APPLICATION_KEY_ID: '${B2_APPLICATION_KEY_ID}'
      B2_APPLICATION_KEY: '${B2_APPLICATION_KEY}'
      B2_BUCKET: 'seleimend-db-backups'
      B2_PREFIX: 'production/postgres'

volumes:
  pgdata:
```

---

## Disaster Recovery & Restore

The container includes `/scripts/restore.sh` to restore backups into any target database.

### 1. List Available Snapshots

```bash
docker run --rm \
  -e B2_ENDPOINT="s3.us-west-004.backblazeb2.com" \
  -e B2_APPLICATION_KEY_ID="..." \
  -e B2_APPLICATION_KEY="..." \
  -e B2_BUCKET="seleimend-db-backups" \
  -e B2_PREFIX="production/postgres" \
  ghcr.io/victorseleimend293/seleimend-db-backup:latest restore --list
```

### 2. Restore Latest Snapshot

```bash
docker run --rm \
  -e B2_ENDPOINT="s3.us-west-004.backblazeb2.com" \
  -e B2_APPLICATION_KEY_ID="..." \
  -e B2_APPLICATION_KEY="..." \
  -e B2_BUCKET="seleimend-db-backups" \
  -e B2_PREFIX="production/postgres" \
  -e DATABASE_URL="postgresql://user:pass@db-host:5432/target_db" \
  ghcr.io/victorseleimend293/seleimend-db-backup:latest restore --latest
```

### 3. Restore Specific Snapshot File

```bash
docker run --rm \
  -e B2_ENDPOINT="s3.us-west-004.backblazeb2.com" \
  -e B2_APPLICATION_KEY_ID="..." \
  -e B2_APPLICATION_KEY="..." \
  -e B2_BUCKET="seleimend-db-backups" \
  -e B2_PREFIX="production/postgres" \
  -e DATABASE_URL="postgresql://user:pass@db-host:5432/target_db" \
  ghcr.io/victorseleimend293/seleimend-db-backup:latest restore --file app_production_20261003_020000Z.dump
```

---

## Code Quality, Formatting & Linting

The repository adheres strictly to **DRY** (Don't Repeat Yourself) and **KISS** (Keep It Simple, Stupid) engineering standards:

- Shared functionality (credentials parsing, S3 sanitization, DB connectivity checks, logging, and webhooks) is encapsulated in [`scripts/common.sh`](scripts/common.sh).
- **Linter**: [ShellCheck](https://www.shellcheck.net/) validates all shell scripts with strict lint rules.
- **Formatter**: [Prettier](https://prettier.io/) with `prettier-plugin-sh` formats Shell scripts, Markdown, YAML, and JSON.

```bash
# Format all code files
pnpm run format

# Verify formatting without writing
pnpm run format:check

# Run ShellCheck across all scripts
pnpm run lint:shell

# Run complete linting and format verification
pnpm run lint
```

---

## Conventional Commits & Git Hooks

Commits must follow the **Conventional Commits** methodology, enforced via **Husky** git hooks and **Commitlint**:

- **Scopes**: Meaningful scopes are required for functional changes (e.g. `feat(core): ...`, `fix(b2): ...`, `refactor(db): ...`).
- **Omitted Scope Rule**: If the commit type is the same as the scope (e.g. `test`, `ci`, `docs`, `chore`), the scope **must be omitted** (e.g. `test: add unit test suite` instead of `test(test): ...`).
- **Breaking Changes**: Major changes are indicated using `!` after type/scope (e.g. `feat(core)!: drop legacy connection variables`).

```bash
# Examples of valid commits:
git commit -m "feat(core): add streaming backup procedure"
git commit -m "fix(b2): trim trailing slashes from prefix"
git commit -m "test: add comprehensive test suite with 100% coverage"
git commit -m "docs: add development and contribution guides"
git commit -m "feat(core)!: change default compression algorithm"

# Examples of rejected commits:
git commit -m "feat: missing scope"         # Rejected: scope required
git commit -m "test(test): redundant scope" # Rejected: scope matches type
```

---

## Testing & 100% Code Coverage

A comprehensive test suite built on [Bats-core](https://github.com/bats-core/bats-core) verifies all execution branches, error traps, healthchecks, retention pruning, and CLI flags with mocks for `aws`, `pg_dump`, `pg_restore`, `pg_isready`, `curl`, and `supercronic`.

```bash
# Run unit and integration tests
pnpm test

# Run test suite with 100% code coverage verification
pnpm run test:coverage
```

### Coverage Report Summary

| Target Script           | Executable Lines | Covered Lines | Coverage | Status |
| :---------------------- | :--------------: | :-----------: | :------: | :----: |
| `scripts/common.sh`     |        67        |      67       | **100%** |  PASS  |
| `scripts/backup.sh`     |        35        |      35       | **100%** |  PASS  |
| `scripts/restore.sh`    |        44        |      44       | **100%** |  PASS  |
| `scripts/entrypoint.sh` |        18        |      18       | **100%** |  PASS  |
| **Total**               |     **164**      |    **164**    | **100%** |  PASS  |

---

## Automated Releases & Registry Publishing

The GitHub Actions CI/CD pipeline triggers on pushes to `main` and version tags (`v*`):

1. **Lint & Code Style**: Runs ShellCheck and Prettier verification.
2. **Unit Tests & 100% Coverage**: Executes Bats test suite and asserts 100% code coverage.
3. **Secret Scanning**: Runs GitGuardian (`ggshield`) to prevent credentials, tokens, and sensitive keys from being committed.
4. **Docker Build & Smoke Tests**: Builds multi-arch container image and tests runtime binaries.
5. **Semantic Release**: Calculates semantic version (`patch`, `minor`, `major`), updates [`CHANGELOG.md`](CHANGELOG.md), and creates GitHub release tags.
6. **Publish to GHCR**: Automatically pushes multi-arch images (`linux/amd64`, `linux/arm64`) to GitHub Container Registry tagged with the semantic version, major/minor tags, and `latest`.

---

## Local Development & Docker Testing

### Build the Image Locally

```bash
docker build -t seleimend-db-backup:local .
```

### Run Smoke Tests

```bash
docker run --rm seleimend-db-backup:local id
docker run --rm seleimend-db-backup:local pg_dump --version
docker run --rm seleimend-db-backup:local aws --version
docker run --rm seleimend-db-backup:local supercronic -version
```

---

## License

This project is open source and licensed under the [MIT License](LICENSE).

Copyright (c) 2026 Seleimend. All rights reserved.
