# AGENTS.md

The staging repository that builds third-party Compose projects for the preview server. Read
[`README.md`](README.md) for the import model and [`docs/SECURITY.md`](docs/SECURITY.md) for the
execution boundary before changing a workflow.

## Enforced rules

- Git history attributes work only to the human committer. Never add an AI `Co-authored-by:` trailer
  or use an agent identity as author/committer. Scrub PR titles and bodies too.
- Branch names use `agent/...` for work on this repository itself. `import/<slug>` is reserved for
  imports and `design-artifacts/<slug>` for machine-written delivery branches.
- Commit subjects and PR titles use Conventional Commits.

## The rule that is the point of this repository

**The job that runs a third-party build declares `permissions: {}` and never publishes.** Publishing
happens in a separate job that runs no third-party code. Any change that puts a writable token in
the same job as an imported project's build is wrong, however convenient — see `docs/SECURITY.md`.

Pin every action to a full commit SHA. An imported build is untrusted by assumption; the actions
around it must not be movable.
