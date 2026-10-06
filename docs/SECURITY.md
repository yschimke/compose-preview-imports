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
  runs no third-party code — downloads that artifact and pushes it to the output repository,
  `yschimke/compose-preview-imports-out`.
- **It is thrown away.** The runner is ephemeral and destroyed when the job ends.
- **It was read first.** The import's pull request names the repository, the ref and the modules.
  Review is the vouching step.

Keeping the write credentials and the foreign code in **different jobs** is the part that matters.
Import publication uses `ARTIFACTS_TOKEN`, a fine-grained PAT scoped to the output repository
alone, in the two jobs that write there; the imported build never holds it — `import.yml`'s `publish` and `catalog-registry.yml`'s `sync`. Neither runs imported
code. Import jobs do not write to this repository. The separate `release-please.yml` workflow uses
`GITHUB_TOKEN` (or an optional `RELEASE_PLEASE_TOKEN`) to update a release PR and create a tag
and release. It executes no imported code and never receives `ARTIFACTS_TOKEN`. Its validation
job has read-only contents access and only inspects this repository's configuration.

The output repository is a boundary of its own. Before it existed the delivery branches were pushed
here with `GITHUB_TOKEN`, so the publish credential was one that could also have pushed to this
repository's branches or opened a pull request against `main`. `ARTIFACTS_TOKEN` reaches
none of that. A leak of it is still serious — a box that branch-trusts the output repository serves
what is there as verified, and with `--allow-render-trusted` executes its live bundles — but it
cannot change what this repository builds, or how.

## Tokens

| Need | Credential |
| --- | --- |
| Clone a public upstream project | **None.** Public clones need no authentication, and the upstream fetch clears any credential helper so it cannot pick one up. |
| Read the output repository's earlier branches during a render | **None.** It is public, and the render job is never handed a credential for it. |
| Push `design-artifacts/<slug>`, and the registry document, to `yschimke/compose-preview-imports-out` | `ARTIFACTS_TOKEN` — a fine-grained PAT with `Contents: Read and write` on that repository **only**, stored as a repository secret here. Used by `import.yml`'s `publish` and `catalog-registry.yml`'s `sync`; never exported to a job that runs imported code. |
| Clone a **private** upstream project | A fine-grained PAT with `Contents: Read` on those named repositories only, stored as a repository secret and passed to the upstream checkout step's `token:` input — never exported to the build environment. |

No credential is used to clone an upstream today, because every import is a public repository.

## Recommended repository settings

These are not enforceable from a workflow file, so they belong in the repository's settings:

- **Settings → Actions → General → Workflow permissions**: *Read repository contents and packages
  permissions*. Every job here that needs more asks for it explicitly, so the default should be the
  floor.
- **Settings → Actions → General**: leave *Allow GitHub Actions to create and approve pull requests*
  **on** so release-please can open release PRs. The workflow does not approve or merge them;
  imported-build jobs retain their existing permissions.
- **Branch protection on `main`**: require a pull request. The registry is the review surface; an
  import that can be added without review is an import nobody read.
- Delivery branches (`design-artifacts/**`, in the output repository) are machine-written and
  force-pushed. Do **not** protect them, and do not treat their contents as reviewed — they are build
  output. The output repository's `main` holds only the generated registry document; leave it
  without a ruleset so `catalog-registry.yml` can push it.

## What an imported catalog is trusted for

Nothing. Building a project here is a statement about this repository's willingness to run code, not
about the project. An imported catalog is served `unverified` by the preview server exactly as any
other unverified catalog is, and it becomes trusted only if its producer is added to that server's
trust store deliberately — which importing does not do and should not be taken to imply.
