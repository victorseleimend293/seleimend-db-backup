# Contributing to seleimend-db-backup

Thank you for contributing to `seleimend-db-backup`! We welcome bug reports, improvements, and pull requests.

## Prerequisites

- [Node.js](https://nodejs.org/) (v22+)
- [pnpm](https://pnpm.io/) (v10+)
- [Docker](https://www.docker.com/) (for building and smoke testing images)

## Development Setup

1. Clone the repository:

   ```bash
   git clone https://github.com/victorseleimend293/seleimend-db-backup.git
   cd seleimend-db-backup
   ```

2. Install dependencies and set up git hooks:
   ```bash
   pnpm install
   ```

## Commit Message Guidelines

This repository strictly enforces the [Conventional Commits](https://www.conventionalcommits.org/) specification using `commitlint` and `husky`:

```
<type>(<scope>): <description>
```

### Commit Rules

1. **Scopes**:
   - Scopes are required for functional changes (`feat`, `fix`, `refactor`, `perf`).
   - Example: `feat(core): add streaming multipart upload`
   - Example: `fix(b2): sanitize prefix with slashes`
2. **Omitted Scope Rule**:
   - If the commit type is the same as the scope (e.g., `test`, `ci`, `docs`, `chore`), the scope **must be omitted**.
   - Valid: `test: add unit tests for restore`
   - Invalid: `test(test): add unit tests for restore`
3. **Breaking Changes**:
   - Major breaking changes must include `!` before the colon or `BREAKING CHANGE:` in the footer.
   - Example: `feat(core)!: drop individual connection parameters in favor of DATABASE_URL`

## Code Style & Linting

Before committing, run linters and formatters:

```bash
# Format code
pnpm run format

# Verify formatting
pnpm run format:check

# Run ShellCheck
pnpm run lint:shell

# Run all linters
pnpm run lint
```

## Testing & Code Coverage

All scripts in `scripts/` must maintain **100% test coverage**:

```bash
# Run unit tests
pnpm test

# Run test suite with 100% code coverage verification
pnpm run test:coverage
```

## Docker Image Smoke Testing

```bash
docker build -t seleimend-db-backup:local .
docker run --rm seleimend-db-backup:local id
docker run --rm seleimend-db-backup:local pg_dump --version
docker run --rm seleimend-db-backup:local aws --version
docker run --rm seleimend-db-backup:local supercronic -version
```
