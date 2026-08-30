# What runs here, and what it can reach

This repository exists to run **other people's build scripts**. That is not incidental to it — it is
the whole job — so the boundary is written down rather than inferred.

## The one dangerous step, and what it is allowed to do

An import's `build` job checks out a third-party repository and runs its Gradle build. Arbitrary
code executes at that moment, and the design assumes it is hostile:

- **It holds nothing that can write.** The job declares `permissions: contents: read`, so the
  `GITHUB_TOKEN` in its environment is read-only: it cannot push a branch, force-push a delivery
  ref, open a pull request, edit a workflow, or write a release. No other secret is passed to it.

  It is `contents: read` rather than `{}` because a called workflow cannot be granted more than the
  calling job holds, and the pipeline's jobs ask for `contents: read` to check anything out — `{}`
  fails the run at startup, before any job exists.

  Read being *enough* is not automatic, and for a while it was not true. `design-artifacts-reusable.yml`'s
  `generate` job both rendered — running the imported project's Gradle — and force-pushed the
  delivery branch, so calling it required granting `contents: write` to the very job running that
  build. No arrangement on this side could have fixed that: permissions are static, and `publish:
  false` stops the push from executing without removing the scope. It was corrected upstream in
  [compose-ai-tools#4856](https://github.com/yschimke/compose-ai-tools/pull/4856), which moved
  publishing into a job that runs none of the rendered code. Until that landed, an import could not
  start at all.

  What the boundary rests on is that the untrusted build holds no *write* scope — now true on both
  sides of the call.
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
