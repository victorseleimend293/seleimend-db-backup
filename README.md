# seleimend-db-backup

[![CI/CD](https://github.com/victorseleimend293/seleimend-db-backup/actions/workflows/ci.yml/badge.svg)](https://github.com/victorseleimend293/seleimend-db-backup/actions/workflows/ci.yml)
[![Disaster Recovery](https://github.com/victorseleimend293/seleimend-db-backup/actions/workflows/disaster-recovery.yml/badge.svg)](https://github.com/victorseleimend293/seleimend-db-backup/actions/workflows/disaster-recovery.yml)
[![Docker Hub](https://img.shields.io/badge/docker-Docker%20Hub-blue.svg?logo=docker&logoColor=white)](https://hub.docker.com/r/seleimend/seleimend-db-backup)
[![GHCR Image](https://img.shields.io/badge/docker-ghcr.io-blue.svg)](https://github.com/victorseleimend293/seleimend-db-backup/pkgs/container/seleimend-db-backup)
[![Coverage: 100%](https://img.shields.io/badge/coverage-100%25-brightgreen.svg)](https://github.com/victorseleimend293/seleimend-db-backup)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)
[![Semantic Release](https://img.shields.io/badge/%20%20%F0%9F%93%A6%F0%9F%9A%80-semantic--release-e10079.svg)](https://github.com/semantic-release/semantic-release)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17%20%7C%2016%20%7C%2015-336791.svg?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Storage: Backblaze B2](<https://img.shields.io/badge/storage-Backblaze%20B2%20(S3)-red.svg>)](https://www.backblaze.com/b2/)

An enterprise-ready, containerized PostgreSQL backup agent that streams compressed database snapshots directly to **Backblaze B2** (via its S3-compatible API). Features zero local disk overhead, native server-side encryption (`SSE-B2` / AES-256), native bucket lifecycle retention rules, automated disaster recovery drills with ephemeral test database provisioning, unified HTTP health checks, and automated infrastructure provisioning via **Terraform** on container startup. Available on both **Docker Hub** and **GitHub Container Registry (GHCR)**.

---

## Architecture Overview

![Architecture Diagram](https://raw.githubusercontent.com/victorseleimend293/seleimend-db-backup/main/assets/architecture.svg)

<details>
<summary>View Mermaid Source</summary>

```mermaid
flowchart TD
    subgraph ContainerService ["Consolidated Single Service (Docker Compose / Kubernetes Deployment)"]
        Startup["Startup Hook: provision_b2.sh<br/>(Terraform Apply SSE-B2 & Lifecycle)"]
        Supercronic["Supercronic Daemon"]
        BackupTask["Backup Job (CRON_SCHEDULE)"]
        DRTask["Disaster Recovery Drill (DR_SCHEDULE)"]

        Startup --> Supercronic
        Supercronic --> BackupTask
        Supercronic --> DRTask
    end

    subgraph PostgresEnv ["PostgreSQL Cluster"]
        ProdDB[("Production Database")]
        TestDB[("Ephemeral Test DB<br/>(dr_test_dbname_timestamp)")]
    end

    subgraph BackblazeB2 ["Offsite Object Storage (Backblaze B2)"]
        Bucket[("Backblaze B2 Bucket<br/>SSE-B2 Encryption (AES-256)<br/>Bucket Lifecycle Retention")]
        StateFile[("terraform.tfstate")]
    end

    subgraph Monitoring ["Unified Health Check"]
        HC["Monitoring Ping<br/>(HEALTHCHECK_URL)<br/>/start, /fail, OK"]
    end

    BackupTask -->|"pg_dump -Fc (streaming)"| ProdDB
    BackupTask -->|"Direct S3 Stream"| Bucket
    BackupTask -.->|"Ping on backup"| HC

    DRTask -->|"CREATE & DROP DATABASE"| PostgresEnv
    DRTask -->|"Download & Restore"| Bucket
    DRTask -->|"pg_restore & Integrity Verification"| TestDB
    DRTask -.->|"Ping on DR drill"| HC

    Startup <-->|"Pull / Push State"| StateFile
    Startup -->|"Manage Bucket & Rules"| Bucket

    style ContainerService fill:#e8f5e9,stroke:#4caf50
    style Bucket fill:#fff3e0,stroke:#ff9800
    style PostgresEnv fill:#e1f5fe,stroke:#03a9f4
    style Monitoring fill:#ffebee,stroke:#f44336
```

</details>

---

## Key Features

- **Direct Memory Streaming**: `pg_dump` is piped directly into Backblaze B2 via AWS CLI streaming multipart uploads. Dumps are never staged onto the local disk, eliminating container disk starvation and scratch space sizing issues.
- **Native Server-Side Encryption (`SSE-B2`)**: Backblaze B2 automatically encrypts all snapshots at rest using standard AES-256 encryption without client-side overhead.
- **Automated Startup Provisioning via Terraform**: On container startup, the image automatically invokes Terraform to provision the B2 bucket, enable default server-side encryption, and apply lifecycle retention rules using container environment variables. Terraform state is synchronized to and from B2 object storage.
- **Automated Disaster Recovery Drills (`dr-test`)**: Using the target database credentials, the agent automatically creates an isolated temporary test database (`dr_test_<dbname>_<timestamp>`), restores the snapshot, asserts schema/table count integrity and custom verification queries, and tears down the test database cleanly.
- **Single Consolidated Service (Docker & Kubernetes)**: Run both scheduled backups and automated disaster recovery drills within a single container using `supercronic`, eliminating redundant containers, multiple Compose services, or separate Kubernetes CronJobs.
- **Unified Health Checks**: A single `HEALTHCHECK_URL` monitors both backup and DR drills with `/start`, `/fail`, and success pings.
- **Native Cloud Retention**: Retention is handled natively by Backblaze B2 Bucket Lifecycle Rules, automatically purging expired snapshots without container-side deletion loops.
- **Strict Security Context (Non-Root)**: The image runs as a non-privileged user (`backup:backup`, UID `10001`), supporting `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, and `capabilities: drop: ["ALL"]`.
- **100% Code Coverage**: Adheres strictly to DRY and KISS principles with a shared `scripts/common.sh` library, verified by a comprehensive Bats test suite with 100% code coverage.
- **Dual Container Registries**: Multi-architecture images (`linux/amd64`, `linux/arm64`) published to both Docker Hub and GitHub Container Registry (GHCR).

---

## Configuration Reference

The container is configured entirely via environment variables (12-Factor App design):

| Variable                |   Required   | Description                                                              | Example                                               |
| :---------------------- | :----------: | :----------------------------------------------------------------------- | :---------------------------------------------------- |
| `B2_ENDPOINT`           |   **Yes**    | Backblaze B2 S3 API endpoint                                             | `s3.us-west-004.backblazeb2.com`                      |
| `B2_APPLICATION_KEY_ID` |   **Yes**    | Backblaze B2 Application Key ID (or `AWS_ACCESS_KEY_ID`)                 | `004a1b2c3d4e5f6...`                                  |
| `B2_APPLICATION_KEY`    |   **Yes**    | Backblaze B2 Application Key (or `AWS_SECRET_ACCESS_KEY`)                | `K004...`                                             |
| `B2_BUCKET`             |   **Yes**    | Dedicated Backblaze B2 bucket name                                       | `seleimend-db-backups`                                |
| `B2_PREFIX`             |      No      | Subdirectory prefix inside the bucket                                    | `production/postgres` _(default: `backups/postgres`)_ |
| `B2_REGION`             |      No      | S3 region identifier                                                     | `us-west-004` _(default: `us-east-005`)_              |
| `AUTO_PROVISION_B2`     |      No      | Automatically apply Terraform config on startup                          | `true` _(default: `true`)_                            |
| `ENABLE_B2_ENCRYPTION`  |      No      | Enable Backblaze B2 default SSE-B2 (AES-256) encryption                  | `true` _(default: `true`)_                            |
| `RETENTION_DAYS`        |      No      | Backblaze B2 Lifecycle Rule retention period (days)                      | `30` _(default: `30`)_                                |
| `DATABASE_URL`          |  **Yes\***   | Full PostgreSQL connection URI                                           | `postgresql://user:pass@db:5432/mydb`                 |
| `DB_HOST`               |     No\*     | PostgreSQL hostname (if `DATABASE_URL` omitted)                          | `postgres.default.svc.cluster.local`                  |
| `DB_PORT`               |      No      | PostgreSQL port                                                          | `5432`                                                |
| `DB_NAME`               |     No\*     | Target database name                                                     | `app_production`                                      |
| `DB_USER`               |     No\*     | PostgreSQL user                                                          | `backup_user`                                         |
| `DB_PASSWORD`           |      No      | PostgreSQL password                                                      | `super_secret`                                        |
| `CRON_SCHEDULE`         |      No      | Backup cron schedule (activates `supercronic` daemon)                    | `0 2 * * *`                                           |
| `DR_SCHEDULE`           |      No      | Disaster recovery test schedule (activates `supercronic`)                | `0 4 * * 0`                                           |
| `DR_DATABASE_URL`       |      No      | Explicit test database target (skips auto-creation)                      | `postgresql://user:pass@db:5432/dr_sandbox`           |
| `DR_VERIFY_QUERY`       | **Yes (DR)** | Required SQL query asserting database validity during DR tests           | `SELECT count(*) FROM users WHERE status = 'active';` |
| `HEALTHCHECK_URL`       |      No      | Unified webhook URL for both backup and DR drill start, fail, and OK ops | `https://hc-ping.com/your-uuid`                       |

_\* Note: Either `DATABASE_URL` or individual connection variables (`DB_HOST`, `DB_NAME`, `DB_USER`) must be specified._

---

## Automated Backblaze B2 Infrastructure via Terraform

### Container Startup Auto-Provisioning

By default (`AUTO_PROVISION_B2=true`), upon container initialization:

1. The container runs [`scripts/provision_b2.sh`](scripts/provision_b2.sh).
2. It checks Backblaze B2 for an existing state file at `s3://${B2_BUCKET}/.terraform/terraform.tfstate`.
3. It passes container environment variables (`B2_BUCKET`, `RETENTION_DAYS`, `ENABLE_B2_ENCRYPTION`, etc.) to the pre-packaged Terraform module in [`terraform/`](terraform/).
4. It applies the configuration idempotently:
   - Provisions or verifies the B2 bucket.
   - Enforces default Server-Side Encryption (`SSE-B2` / AES-256).
   - Applies B2 Bucket Lifecycle Rules to automatically expire snapshots older than `RETENTION_DAYS`.
5. It synchronizes the updated state back to `s3://${B2_BUCKET}/.terraform/terraform.tfstate`.

Zero manual Terraform commands or workspace files are required.

---

## Automated Disaster Recovery Drills

A backup that has never been restored is not a reliable backup. `seleimend-db-backup` includes an automated disaster recovery verification system ([`scripts/dr_test.sh`](scripts/dr_test.sh) / `dr-test`).

### How It Works

1. **Auto-creates Isolated Database**: Connects to the PostgreSQL instance and creates a temporary test database (`dr_test_<dbname>_<timestamp>`). Production data is never touched.
2. **Restores Latest Snapshot**: Pulls the most recent backup from Backblaze B2 and restores the schema and data into the ephemeral database.
3. **Data Integrity Assertions**: Asserts that tables exist in the `public` schema (`count(*) > 0`) and executes the required custom verification SQL query (`DR_VERIFY_QUERY`).
4. **Guaranteed Teardown**: An exit trap automatically drops the test database (`DROP DATABASE "..." WITH (FORCE)`), ensuring zero residual disk usage even if the test fails.
5. **Unified Health Check Alerts**: Dispatches `/start`, `/fail`, and completion pings to `HEALTHCHECK_URL`.

### Running a DR Drill Manually

```bash
docker run --rm \
  -e B2_ENDPOINT="s3.us-west-004.backblazeb2.com" \
  -e B2_APPLICATION_KEY_ID="..." \
  -e B2_APPLICATION_KEY="..." \
  -e B2_BUCKET="seleimend-db-backups" \
  -e DATABASE_URL="postgresql://user:pass@db:5432/app_production" \
  -e DR_VERIFY_QUERY="SELECT 1 FROM users LIMIT 1;" \
  -e HEALTHCHECK_URL="https://hc-ping.com/your-uuid" \
  ghcr.io/victorseleimend293/seleimend-db-backup:latest dr-test --latest
```

---

## Single Consolidated Service (Docker Compose)

Run both scheduled backups and automated disaster recovery tests concurrently in a single container:

```yaml
services:
  db-backup:
    image: ghcr.io/victorseleimend293/seleimend-db-backup:latest
    container_name: db-backup
    restart: unless-stopped
    environment:
      - DATABASE_URL=postgresql://app_user:app_password@postgres:5432/app_production
      - B2_ENDPOINT=s3.us-west-004.backblazeb2.com
      - B2_APPLICATION_KEY_ID=your_key_id
      - B2_APPLICATION_KEY=your_app_key
      - B2_BUCKET=your-b2-bucket
      - B2_PREFIX=backups/production
      - AUTO_PROVISION_B2=true
      - RETENTION_DAYS=30
      - ENABLE_B2_ENCRYPTION=true
      - CRON_SCHEDULE=0 2 * * *
      - DR_SCHEDULE=0 4 * * 0
      - DR_VERIFY_QUERY=SELECT 1;
      - HEALTHCHECK_URL=https://hc-ping.com/your-uuid
```

---

## Consolidated Kubernetes Deployment

Instead of managing multiple CronJobs, `seleimend-db-backup` deploys as a single 1-replica Kubernetes `Deployment` ([`k8s/deployment.yaml`](k8s/deployment.yaml)):

### 1. Create the Secret

Copy [`k8s/secret.example.yaml`](k8s/secret.example.yaml) to `k8s/secret.yaml`, fill in your credentials, and apply:

```bash
kubectl apply -f k8s/secret.yaml
```

### 2. Deploy Single Backup & DR Service

Apply the consolidated Deployment ([`k8s/deployment.yaml`](k8s/deployment.yaml)):

```bash
kubectl apply -f k8s/deployment.yaml
```

The pod automatically runs Terraform once on startup to configure B2, then runs `supercronic` to manage both `CRON_SCHEDULE` and `DR_SCHEDULE` concurrently with a single `HEALTHCHECK_URL`.

---

## Testing & 100% Code Coverage

```bash
# Run unit tests and commitlint checks
pnpm test

# Run Bats test suite with 100% code coverage verification
pnpm run test:coverage

# Run linters (ShellCheck and Prettier)
pnpm run lint

# Run local end-to-end disaster recovery drill with live Docker containers
pnpm run test:dr
```

### Code Coverage Summary

| Target Script             | Executable Lines | Covered Lines | Coverage | Status |
| :------------------------ | :--------------: | :-----------: | :------: | :----: |
| `scripts/common.sh`       |        68        |      68       | **100%** |  PASS  |
| `scripts/backup.sh`       |        24        |      24       | **100%** |  PASS  |
| `scripts/restore.sh`      |        44        |      44       | **100%** |  PASS  |
| `scripts/entrypoint.sh`   |        28        |      28       | **100%** |  PASS  |
| `scripts/dr_test.sh`      |        72        |      72       | **100%** |  PASS  |
| `scripts/provision_b2.sh` |        35        |      35       | **100%** |  PASS  |
| **Total**                 |     **271**      |    **271**    | **100%** |  PASS  |

---

## License

This project is open source and licensed under the [MIT License](LICENSE).

Copyright (c) 2026 Seleimend. All rights reserved.
