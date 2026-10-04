# AGENTS.md

The staging repository that builds third-party Compose projects for the preview server. Read
[`README.md`](README.md) for the import model and [`docs/SECURITY.md`](docs/SECURITY.md) for the
execution boundary before changing a workflow.

## Enforced rules

- Git history attributes work only to the human committer. Never add an AI `Co-authored-by:` trailer
  or use an agent identity as author/committer. Scrub PR titles and bodies too.
- Branch names use `agent/...` for work on this repository itself. Machine-written output never lands here: the `design-artifacts/<slug>` delivery branches
  and the catalog registry document live in
  [`yschimke/compose-preview-imports-out`](https://github.com/yschimke/compose-preview-imports-out),
  written with the `ARTIFACTS_TOKEN` secret by jobs that run no third-party code.
- **`main` is the configuration.** `import.yml` reads `imports/<slug>/` from the commit it runs on
  and renders that same commit by SHA. There are no per-import branches: raise every change to
  `imports/<slug>/` from an `agent/...` branch against `main`. To try a configuration before it
  merges, dispatch **Import a project** on that branch — it builds, but only a run on `main`
  publishes.
- Commit subjects and PR titles use Conventional Commits.
- The registry document a preview server reads, `.compose-preview/catalogs.json`, is generated from
  the `imports/` directory and lives on the output repository's `main`. Never hand-edit it:
  `catalog-registry.yml` regenerates and pushes it after a merge here, which is what stops concurrent
  imports colliding on one shared file. Nothing may push to this repository's `main` directly — a
  ruleset rejects it. An import's pull request adds `imports/<slug>/import.json` and
  `imports/<slug>/catalog.spec.json`, and nothing else. `scripts/sync-catalog-registry.sh --lint` is
  what CI runs on the pull request.

## The rule that is the point of this repository

**The job that runs a third-party build declares `permissions: {}` and never publishes.** Publishing
happens in a separate job that runs no third-party code. Any change that puts a writable token in
the same job as an imported project's build is wrong, however convenient — see `docs/SECURITY.md`.

Pin every action to a full commit SHA. An imported build is untrusted by assumption; the actions
around it must not be movable.
