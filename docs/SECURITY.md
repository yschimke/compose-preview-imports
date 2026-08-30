# What runs here, and what it can reach

This repository exists to run **other people's build scripts**. That is not incidental to it — it is
the whole job — so the boundary is written down rather than inferred.

## The one dangerous step, and what it is allowed to do

An import's `build` job checks out a third-party repository and runs its Gradle build. Arbitrary
code executes at that moment, and the design assumes it is hostile:

- **The job that runs the build holds no write scope.** The imported project's Gradle runs in the
  pipeline's `generate` job, which declares `contents: read`. It cannot push a branch, force-push a
  delivery ref, open a pull request, edit a workflow, or write a release. No other secret is passed
  to it.

  The calling job here declares `contents: **write**`, and that looks alarming until you see what
  it is: a **ceiling**, not a grant. A calling job must declare at least the maximum any job in the
  called workflow asks for, and that workflow's `publish-catalog` job asks for write — so anything
  less fails the run before a single job starts, whatever `publish: false` says. Permissions are
  static; the input only skips the job, it does not lower the requirement.

  Each called job then runs with **its own** declared permissions, capped by that ceiling. So the
  render gets read, and the write scope exists only in `publish-catalog`, which runs none of the
  imported code. The calling job itself is a `uses:` shim that executes nothing, so the ceiling it
  names is never a process the imported build is inside of.

  This was established by running it, not by reading the documentation: `contents: read` on the
  calling job fails at startup, `contents: write` starts and the render proceeds under read. An
  earlier version of this file claimed read was sufficient. It was not, and the reason it was not
  had nothing to do with what the render needs.
- **It cannot publish.** Its only output is an uploaded artifact. A separate `publish` job — which
  runs no third-party code — downloads that artifact and force-pushes it.
- **It is thrown away.** The runner is ephemeral and destroyed when the job ends.
- **It was read first.** The import's pull request names the repository, the ref and the modules.
  Review is the vouching step.

Keeping the write credential and the foreign code in **different jobs** is the part that matters.
`GITHUB_TOKEN` is already minted per-run and scoped to this repository — it cannot touch another
repo, and it expires with the job — but a token scoped to *this* repo is still a token an untrusted
build could use to push a branch *here*, including to `main` or to another project's delivery
branch. Separating the jobs means the two are never in the same process.

## Tokens

| Need | Credential |
| --- | --- |
| Clone a public upstream project | **None.** Public clones need no authentication, and the upstream fetch clears any credential helper so it cannot pick one up. |
| Force-push `design-artifacts/<slug>` | `GITHUB_TOKEN`, `contents: write`, in the publish job only. Repository-scoped and short-lived by construction. |
| Clone a **private** upstream project | A fine-grained PAT with `Contents: Read` on those named repositories only, stored as a repository secret and passed to the upstream checkout step's `token:` input — never exported to the build environment. |

No personal access token is used by any import today, because every import is a public repository.

## Recommended repository settings

These are not enforceable from a workflow file, so they belong in the repository's settings:

- **Settings → Actions → General → Workflow permissions**: *Read repository contents and packages
  permissions*. Every job here that needs more asks for it explicitly, so the default should be the
  floor.
- **Settings → Actions → General**: leave *Allow GitHub Actions to create and approve pull requests*
  **off**. Nothing here needs it.
- **Branch protection on `main`**: require a pull request. The registry is the review surface; an
  import that can be added without review is an import nobody read.
- Delivery branches (`design-artifacts/**`) are machine-written and force-pushed. Do **not** protect
  them, and do not treat their contents as reviewed — they are build output.

## What an imported catalog is trusted for

Nothing. Building a project here is a statement about this repository's willingness to run code, not
about the project. An imported catalog is served `unverified` by the preview server exactly as any
other unverified catalog is, and it becomes trusted only if its producer is added to that server's
trust store deliberately — which importing does not do and should not be taken to imply.
