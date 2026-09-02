# compose-preview-imports

The staging repository that builds **other people's** Compose projects so
[preview.coo.ee](https://preview.coo.ee) can serve their `@Preview` composables — without forking
those projects, opening pull requests against them, or asking their maintainers to apply a Gradle
plugin.

Nothing here is a fork. An *import* is a small description of somebody else's repository, held on a
branch of this one; a GitHub Actions runner checks that project out, injects the Compose Preview
plugin at build time, renders its previews, and force-pushes the result to a `design-artifacts/<slug>`
branch **of this repository**. A preview server that nominates this repository as a *catalog
registry* then serves that branch exactly as it serves a catalog a project published for itself —
with no second, manual step against the box, which is what makes merging the import's pull request
the whole import.

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
| Credential | the box's own, in-process | the build job's is read-only; only a separate job that runs none of the imported code can write |

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
   `imports/<slug>/import.json` (below) and `imports/<slug>/catalog.spec.json` — its own two files
   and nothing else. Open it against `main`: the pull request is the review, and its diff says
   exactly which third-party code this repository is about to start building.

   Nothing shared is edited on the way in, which is deliberate. The registry used to be a
   hand-kept array that every import appended to, so the first of several open imports to merge left
   all the others conflicting on a file where nothing had disagreed. The registry is now the
   `imports/` directory itself.

   The branch is long-lived and is what the build reads, so it is not deleted on merge; merging is
   what adds `imports/<slug>/` to `main`, which is the registry the scheduled refresh walks.

3. **When it lands, it builds.** Merging pushes `imports/<slug>/…` to `main`, and
   [`import-on-merge.yml`](.github/workflows/import-on-merge.yml) runs every import that push
   touched, publishing `design-artifacts/<slug>`. Re-run one any time from the Actions tab —
   **Import a project** → *Run workflow* → the slug — and every registered import is refreshed
   nightly by [`refresh-imports.yml`](.github/workflows/refresh-imports.yml).

4. **And it is served.** Nothing else to do: the merge also has
   [`catalog-registry.yml`](.github/workflows/catalog-registry.yml) regenerate
   [`.compose-preview/catalogs.json`](.compose-preview/catalogs.json) (below) on `main`, which is the
   document preview.coo.ee re-reads on its catalog-refresh cadence. The catalog appears there once
   its first build finishes.

## How the catalogs reach the preview server

Publishing a delivery branch and *serving* it were two unrelated acts for as long as the served set
was enumerated on the box: `design-artifacts/joreilly-peopleinspace` could be complete, verifiable
and reachable while `preview.coo.ee/joreilly-peopleinspace/` served a permanent 404, because nothing
had told the server it existed. For a repository whose entire model is "the pull request is the
import", that is the one gap that makes the model untrue.

[`.compose-preview/catalogs.json`](.compose-preview/catalogs.json) closes it. A preview server
started with

```
--catalog-registry yschimke/compose-preview-imports
```

fetches that file from this repository's default branch and serves every catalog it lists, from this
repository's own `design-artifacts/<slug>` branches. It re-reads it on the same cadence it polls
those branches, so a merged import is picked up without a restart, and an import whose directory is
removed is retired.

The file is **generated** from the `imports/` directory by
[`scripts/sync-catalog-registry.sh`](scripts/sync-catalog-registry.sh), and it is regenerated **after
a merge to `main`** by [`catalog-registry.yml`](.github/workflows/catalog-registry.yml) rather than in
the import's own pull request. `main` carries a ruleset — changes must arrive through a pull request —
so that job opens one (`chore/catalog-registry`, force-pushed, so a run of merges updates a single
pull request rather than a queue of them) and asks for auto-merge. **An import is not served until
that pull request lands**, which is the one manual step left when a repository requires review. That is what keeps concurrent imports from colliding: each one adds its own
`imports/<slug>/` and touches nothing shared, and the one shared, generated file is written once, by
the job that watches `main`. On a pull request that same workflow only lints the import descriptions
— that each `slug` matches its directory, and that each `upstream` is an owner/repo.

`imports/<slug>/import.json` is what a reviewer reads; `.compose-preview/catalogs.json` is the shape
a preview server already understands (it is the server's own `catalogs.json` document), so nothing
between here and the box has to translate. It is committed rather than derived at read time because
the server fetches one raw URL and nothing else.

The job that writes it runs no third-party code — `jq` over files already merged here — so the
boundary [`docs/SECURITY.md`](docs/SECURITY.md) draws is unchanged: nothing an imported project
controls ever executes in a job holding a writable token.

Nominating a registry does not hand this repository the box. An entry here may only be served from
this repository's own branches, its front-page grouping is claimed against the groups declared in
this same file, and the operator's own configuration wins any collision. A catalog served this way
still badges `unverified` until this repository's producer key is trusted on the box, exactly like
any other.

## What an import looks like

`imports/<slug>/import.json`, on the branch `import/<slug>`:

```json
{
  "slug": "joreilly-peopleinspace",
  "upstream": "joreilly/PeopleInSpace",
  "ref": "main",
  "modules": [":app"],
  "renderer": "android",
  "notes": "KMP sample; :app holds the @Preview functions and applies com.android.application."
}
```

| Field | Meaning |
| --- | --- |
| `slug` | The catalog id, the delivery branch suffix (`design-artifacts/<slug>`) and the route the server serves it at. Must match the branch name after `import/`. |
| `upstream` | The `owner/repo` being imported. Never modified by anything here. |
| `ref` | Branch or tag of the upstream project to build. Pinning a tag makes an import reproducible; `main` follows the project. |
| `modules` | Gradle paths to render, from the scan. Empty means every module the plugin applies to. |
| `renderer` | `android` (default) or `desktop`. Which lane the module's previews render in — see below. |
| `previewAnnotations` | Optional. Space-separated multipreview annotation names (e.g. `WearPreviewDevices WearPreviewFontScales`) that the spec pre-flight cannot see for itself. Wear catalogs always need this. |
| `excludePreviewIds` | Optional. Array of preview-id patterns this import cannot render, left unrendered instead of failing the run. See below. |
| `workingDirectory` | Optional. Repo-relative subdirectory of the upstream checkout holding the Gradle build, for a project whose build is not at its repository root. Omit for the usual case. |
| `javaVersion` | Optional. Major version of an extra JDK to install, when the upstream build's own Gradle toolchain asks for one the runner does not carry. Omit unless a build fails for the lack of it. |
| `notes` | Free text for the reviewer — why this project, and anything odd about its build. |

`previewAnnotations` exists because the spec pre-flight is a **source** scan: it reads the
upstream's `.kt` files and matches `@Preview` by name, before anything is built. A preview annotated
only with a multipreview declared in *another* module is invisible to it, so every spec entry naming
such a preview fails with *"matches no @Preview function in the scanned module"* even though the
render would have produced it. Naming the multipreview annotations makes those indirectly annotated
previews visible to the pre-flight.

`workingDirectory` exists because an upstream's repository root and its Gradle root are not always
the same directory. `mullvad/mullvadvpn-app` is a Rust repository whose Android client is a complete
Gradle build under `android/`, with no `settings.gradle.kts` at the root, so a render started at the
root has nothing to build. The reusable pipeline already renders in a named subdirectory of the
upstream checkout; naming it here is what reaches it. `catalog.spec.json` is unaffected — it is read
from this repository, and its path stays repo-root-relative.

`excludePreviewIds` exists because some previews only render inside their own application. One that
reads a `CompositionLocal` the host installs, resolves a Hilt entry point, or touches a process-wide
singleton is fine in the app and impossible standalone — there is nothing to fix upstream, and
nothing to fix here. Without a way to say so, a single such preview fails the entire import:
bitwarden rendered **55 of 56** and published nothing, `pocketcasts-wear` **24 of 28**, twine
**21 of 22**.

```json
"excludePreviewIds": ["*.BitwardenBasicDialog_preview"]
```

Named ids rather than the pipeline's `allow-incomplete`, and the distinction is the point. Allowing
incomplete renders would also swallow the *next* breakage — an upstream refactor that quietly stops
rendering half the catalog — and the nightly refresh would go on publishing a thinner catalog with
nothing to show for it. Listing the ids keeps every other render failure fatal, and the list is
reviewable: the pull request says exactly what this import gives up. Say why in `notes`. The patterns
are appended to the exclusions the pipeline always applies, so naming one here does not re-enable the
synthetic app-launching previews.

`javaVersion` exists because an imported project picks its own Gradle toolchain and this repository
does not get to choose it. ClimateTraceKMP's `:composeApp` requests Java 24, so on a runner holding
21 alone the render failed before resolving a single dependency — *"Cannot find a Java installation
on your machine matching: {languageVersion=24, …}. Toolchain download repositories have not been
configured."* Naming `"javaVersion": "24"` installs that JDK **alongside** 21 and points Gradle's
toolchain detection at it; `JAVA_HOME` stays 21, which is what the CLI itself runs on.

It is an explicit version rather than Gradle toolchain auto-provisioning on purpose: an import is
somebody else's build, and letting it download an arbitrary JDK mid-render is a larger grant than
letting it name one the pipeline then installs.

`modules` names **at most one** Gradle path: the pipeline renders one module, or every previewable
module when the field is omitted. Naming two is refused, with a message saying to split the import
or drop the field.

### Which renderer

`renderer` is not a preference; it is a fact about the upstream module, and getting it wrong fails
the render rather than producing a worse one.

| The module's `@Preview` comes from | `renderer` | Why |
| --- | --- | --- |
| `androidx.compose.ui.tooling.preview.Preview` | `android` | Renders under Robolectric, with the Android SDK ubuntu-latest already carries. |
| `org.jetbrains.compose.ui.tooling.preview.Preview`, in a `commonMain` source set | `desktop` | A Compose Multiplatform preview has no Android context to render in; it goes through the desktop/Skiko lane, which needs Mesa software GL, fonts and xvfb. |

Read the import line of the file the preview lives in — that is the whole test. Of the samples this
was built against, PeopleInSpace's `:app` and GalwayBus's `:androidApp` are `android`; BikeShare's
`:common` and ClimateTraceKMP's `:composeApp` are `desktop`.

### Activities are not rendered

An import renders **composables**. The activity and app-tour captures a first-party catalog gets —
the ones synthesised from the merged manifest, where the launcher activity's screenshot becomes the
app's hero image — are excluded, because rendering one launches the app: Robolectric instantiates
the manifest `Application` and runs `onCreate`, so the project's whole DI graph executes. That is
more of an unvouched-for build than this repository should run to draw a component, and the app's
own screen is not what an imported catalog is for. PeopleInSpace is the worked example: both its
`@Preview` functions render clean, while its activity tour dies in `initKoin()`.

Beside it, `imports/<slug>/catalog.spec.json` is the catalog's cover sheet — `system`, `title`,
`module`, `modes`. It carries no per-component inventory: that comes from the previews themselves,
and an imported project has none to declare.

The upstream project is **never** asked to change. The preview plugin is injected at build time via
the CLI's init script, which applies it to any module that already applies an Android or Compose
Multiplatform plugin.

## What this repository does not claim

Importing a project is not an endorsement of it.

Two things this section used to claim are no longer true, and saying so plainly matters more than
the sentence they replaced.

**An imported catalog is no longer inherently `unverified`.** preview.coo.ee branch-trusts this
repository's `design-artifacts/*`, so its imports badge as verified there. That trust is in the
import review — a pull request naming the upstream repository, ref and modules — and in the pipeline
that renders it, not in the upstream projects themselves. Another box grants or withholds it
independently.

**The delivery branch now carries more than pictures.** Since `publish-live-bundle`, it carries the
executable render bundle — the imported module's compiled classes — so a serve box can re-render the
previews live rather than replaying snapshots. On a box running `--allow-render-trusted` that also
branch-trusts this repository, that bundle is eligible for server-side execution. Two consequences
worth stating rather than discovering: a box's trust in this repository is now trust in the code it
renders, and publishing compiled output of someone else's project is closer to redistribution than
publishing screenshots of it was. Every import here is a permissively licensed public project and
every catalog links back to the project it came from, but that is a licence question each new import
should be read against, not a settled one.

If you maintain a project imported here and would rather it were not, open an issue and it will be
removed.
