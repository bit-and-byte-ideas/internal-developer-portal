# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Backstage Internal Developer Portal** (v1.47.0) for the Bit & Byte Ideas organization. It uses the standard Backstage monorepo structure with Yarn 4.4.1 workspaces.

## Common Commands

| Command | Description |
|---------|-------------|
| `yarn start` | Start frontend (port 3000) and backend (port 7007) together |
| `yarn test` | Run tests for changed packages |
| `yarn test:all` | Run all tests with coverage |
| `yarn test:e2e` | Run Playwright E2E tests |
| `yarn lint` | Lint files changed since origin/main |
| `yarn lint:all` | Lint all files |
| `yarn tsc` | TypeScript type checking |
| `yarn fix` | Auto-fix lint/formatting issues |
| `yarn build:all` | Build all packages |
| `yarn build:backend` | Build backend only |
| `yarn new` | Scaffold a new plugin or package |

Run a single test file: `yarn test -- --testPathPattern=<pattern>`

## Architecture

**Monorepo layout** managed by Yarn workspaces (`packages/*`, `plugins/*`):

- **`packages/app`** — Frontend React 18 app using Material-UI v4 and Backstage core components. Entry point is `src/App.tsx` which configures routes, plugin bindings, and GitHub OAuth sign-in.
- **`packages/backend`** — Node.js backend using `@backstage/backend-defaults`. Entry point is `src/index.ts` which registers all backend plugins via `backend.add(import(...))`.
- **`plugins/`** — Directory for custom plugins (currently empty). Use `yarn new` to scaffold.

### Backend Plugins Registered

Catalog (with GitHub org discovery), Scaffolder (with GitHub module), TechDocs, Auth (GitHub + guest providers), Search (PostgreSQL engine, catalog + techdocs collators), Permissions (allow-all policy), Kubernetes, Notifications, Signals, Proxy.

### Frontend Routes

`/catalog`, `/docs`, `/create` (scaffolder), `/api-docs`, `/search`, `/settings`, `/catalog-graph`, `/notifications`, `/catalog-import` (permission-gated).

## Configuration

- **`app-config.yaml`** — Development config: SQLite in-memory DB, GitHub OAuth (requires `AUTH_GITHUB_CLIENT_ID` and `AUTH_GITHUB_CLIENT_SECRET` env vars), GitHub App integration via `github-app-credentials.yaml`.
- **`app-config.production.yaml`** — Production config: PostgreSQL, guest auth.
- **`app-config.local.yaml`** — Local overrides (gitignored).

GitHub integration discovers repos from the `bit-and-byte-ideas` organization and imports `catalog-info.yaml` files.

## Tech Stack

- **Runtime:** Node.js 22 or 24
- **Language:** TypeScript ~5.8
- **Frontend:** React 18, React Router 6, Material-UI v4
- **Backend:** Backstage backend-defaults (modular plugin system)
- **Database:** better-sqlite3 (dev), PostgreSQL (prod)
- **Testing:** Jest 30, Playwright, @testing-library/react
- **Formatting:** Prettier 2.x (config from `@backstage/cli/config/prettier`)
- **Linting:** ESLint via `@backstage/cli`, lint-staged for pre-commit hooks
