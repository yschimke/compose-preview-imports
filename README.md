# compose-preview-imports

The staging repository that builds **other people's** Compose projects so
[preview.coo.ee](https://preview.coo.ee) can serve their `@Preview` composables — without forking
those projects, opening pull requests against them, or asking their maintainers to apply a Gradle
plugin.

Nothing here is a fork. An *import* is a small description of somebody else's repository, held on a
branch of this one; a GitHub Actions runner checks that project out, injects the Compose Preview
plugin at build time, renders its previews, and force-pushes the result to a `design-artifacts/<slug>`
branch **of this repository**. The preview server then onboards that branch exactly as it onboards a
catalog a project published for itself.

## Why the builds happen here and not on the preview box

Building an arbitrary repository means running its build scripts. The preview server
([compose-preview-server](https://github.com/yschimke/compose-preview-server)) deliberately has no
route that does that: it serves traffic, and a box that serves traffic is the wrong place to execute
code from a project nobody has vouched for.

A GitHub Actions runner is a better place in every dimension that matters:

| | preview box | Actions runner |
| --- | --- | --- |
| Isolation | long-lived, serves the public | ephemeral, destroyed after the run |
| Toolchain | needs a JDK + Android SDK installed and kept current | already has them |
| Bounds | a concurrency budget and timeouts we write and maintain | GitHub's, enforced for us |
| Review | an admin token holder pasted a URL | **a pull request a human read** |

That last row is the real gain. The import's pull request *is* the vouching step: someone reads
which repository, which ref and which modules are about to be built before any of it runs.

## Importing a project

1. **Find out what is in it.** Ask a preview server to scan the repository — this reads a shallow
   clone and runs nothing:

   ```bash
   curl -sX POST -H "X-Compose-Preview-Admin-Token: $TOKEN" \
     -d '{"url":"https://github.com/joreilly/PeopleInSpace"}' \
     https://preview.coo.ee/admin/onboard/scan
   ```

   The response names each Gradle module, its `@Preview` count, and whether the preview plugin can
   be injected into it. That is what you write the import down from.

2. **Open the import as a pull request.** Create the branch `import/<slug>` adding
   `imports/<slug>/import.json` (below), `imports/<slug>/catalog.spec.json`, and the slug in
   [`imports.json`](imports.json). Open it against `main`: the pull request is the review, and its
   diff says exactly which third-party code this repository is about to start building.

   The branch is long-lived and is what the build reads, so it is not deleted on merge; merging is
   what adds the import to the registry the scheduled refresh walks.

3. **When it lands, it builds.** Merging runs the import and publishes
   `design-artifacts/<slug>`. Re-run it any time from the Actions tab —
   **Import a project** → *Run workflow* → the slug — and every import is refreshed on a schedule.

## What an import looks like

`imports/<slug>/import.json`, on the branch `import/<slug>`:

```json
{
  "slug": "joreilly-peopleinspace",
  "upstream": "joreilly/PeopleInSpace",
  "ref": "main",
  "modules": ["shared"],
  "notes": "KMP sample; previews live in :shared (commonMain)."
}
```

| Field | Meaning |
| --- | --- |
| `slug` | The catalog id, the delivery branch suffix (`design-artifacts/<slug>`) and the route the server serves it at. Must match the branch name after `import/`. |
| `upstream` | The `owner/repo` being imported. Never modified by anything here. |
| `ref` | Branch or tag of the upstream project to build. Pinning a tag makes an import reproducible; `main` follows the project. |
| `modules` | Gradle paths to render, from the scan. Empty means every module the plugin applies to. |
| `notes` | Free text for the reviewer — why this project, and anything odd about its build. |

`modules` names **at most one** Gradle path: the pipeline renders one module, or every previewable
module when the field is omitted. Naming two is refused, with a message saying to split the import
or drop the field.

Beside it, `imports/<slug>/catalog.spec.json` is the catalog's cover sheet — `system`, `title`,
`module`, `modes`. It carries no per-component inventory: that comes from the previews themselves,
and an imported project has none to declare.

The upstream project is **never** asked to change. The preview plugin is injected at build time via
the CLI's init script, which applies it to any module that already applies an Android or Compose
Multiplatform plugin.

## What this repository does not claim

Importing a project is not an endorsement of it, and building it here grants it no trust on the
preview server: an imported catalog badges `unverified` exactly as any unverified published catalog
does. It is also not a redistribution — the delivery branch carries rendered PNGs and the metadata
needed to browse them, and every catalog links back to the project it came from.

If you maintain a project imported here and would rather it were not, open an issue and it will be
removed.
