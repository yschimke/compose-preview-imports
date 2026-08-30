# Upstream preview patches

Ready-to-apply patches that add `@Preview` functions to the four upstream sample projects this
repository imports. They live here rather than in those projects because **this session could not
open pull requests against them** — see [Why they are patches](#why-they-are-patches).

Each patch is a single commit adding a single new file. None of them edits existing code.

| Patch | Repo | Module | New file | Previews |
| --- | --- | --- | --- | --- |
| `PeopleInSpace.patch` | [joreilly/PeopleInSpace](https://github.com/joreilly/PeopleInSpace) | `:app` | `…/peopleinspace/ui/PeopleInSpacePreviews.kt` | 16 |
| `ClimateTraceKMP.patch` | [joreilly/ClimateTraceKMP](https://github.com/joreilly/ClimateTraceKMP) | `:composeApp` | `…/climatetrace/ui/ClimateTracePreviews.kt` | 11 |
| `BikeShare.patch` | [joreilly/BikeShare](https://github.com/joreilly/BikeShare) | `:common` | `…/common/ui/BikeSharePreviews.kt` | 10 |
| `Confetti.patch` | [joreilly/Confetti](https://github.com/joreilly/Confetti) | `:shared` | `…/confetti/ui/component/ConfettiComponentPreviews.kt` | 10 |

## Applying one

```bash
git clone https://github.com/joreilly/PeopleInSpace && cd PeopleInSpace
git checkout -b add-previews
git am < /path/to/PeopleInSpace.patch
```

`git am` preserves the commit message; `git apply` works too if you would rather write your own.

## What was added, and why those three categories

Each patch covers the same three things.

**Key components used in more than one place.** `PersonView` (the row the list is built from),
BikeShare's `StationView` / `NetworkView` / `CountryView`, ClimateTrace's `CountryRow` and
`EmptyState`, and Confetti's `ConfettiHeader` / `ConfettiTab` / `ConfettiAlertDialog` /
`ConfettiSearch` — the last group had no previews at all despite being used from several screens
each.

**Stateless screens.** The clearest win is PeopleInSpace's `PersonListScreen`, which already takes a
`PersonListUiState` plus two lambdas rather than reaching for a ViewModel. That makes all three of
its states renderable from literal data — and `Loading` and `Error` are the states hardest to reach
by running the app and easiest to break unnoticed.

**Theme catalogs.** A colour-scheme swatch sheet and a typography specimen per project, in light and
dark where the theme takes a flag. Confetti already had `ThemeFoundationPreviews.kt`, so its patch
adds none — the gap there was components, not theme.

## Constraints these were written under

- **No I/O.** Every preview is driven by literal sample data. Image URLs are passed as `null`
  deliberately, which is the branch that draws the placeholder rather than the one that fetches, so
  these render the same offline, in the IDE and in a headless renderer.
- **No new dependencies.** Only APIs each project already uses. Confetti's previews use
  `Icons.Default.Bookmark` and `Icons.Default.Schedule`, both already imported elsewhere in
  `:shared`, which depends on `compose.materialIconsExtended`.
- **Each project's own conventions.** Confetti's previews are `internal` with sized `@Preview(name
  = …, showBackground = true)` annotations, matching the existing previews in that module. The
  others use the plain `@Preview` their projects already use — `androidx.compose.ui.tooling.preview`
  for the Android module, `org.jetbrains.compose.ui.tooling.preview` for the multiplatform ones.

## Not verified

**None of these has been compiled.** Building four Android/KMP projects was out of reach here, so
every signature, import path, package and model field was checked by reading the source instead —
`Assignment`, `Station`, `Network`, `Country`, `PersonListUiState` and each composable's parameter
list were read directly, not inferred. That is weaker evidence than a green build, and the honest
expectation is that a first compile may still turn up something.

`ConfettiSearch` is the one preview with a side effect: it calls `focusRequester.requestFocus()` in
a `DisposableEffect`. It is included because it is a genuinely reusable component, but it is the
first place to look if a preview misbehaves under a headless renderer.

## Why they are patches

The session that wrote them held `yschimke` repositories, and the tooling refuses to add a
repository from another owner to such a session:

```
add_repo joreilly/PeopleInSpace
→ cross-tier adds are not supported in v1: session already has repos from
  owner(s) [yschimke]. Start a new session with the requested repo as the
  initial source
```

Forking was refused for the same underlying reason (`Access denied: repository
"joreilly/peopleinspace" is not configured for this session`). Granting repository access does not
change it — it is a property of how the session was created, not of permissions. A session started
with one of those repositories as its initial source can push branches and open the pull requests
directly.
