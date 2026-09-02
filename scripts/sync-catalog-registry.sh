#!/usr/bin/env bash
# Regenerate `.compose-preview/catalogs.json` from the `imports/` directory.
#
# The registry used to be a hand-kept array in `imports.json`, and every import's pull request
# appended a line to it — so the first of several open imports to merge left every other one
# conflicting, on a file where nothing had actually disagreed. `imports/<slug>/import.json` already
# holds the same two facts (the slug, and the upstream it builds), one file per import, so the list
# is derived from the directory instead and an import's pull request touches only its own files.
#
# `.compose-preview/catalogs.json` is what a preview server reads: the document
# `--catalog-registry <owner>/<repo>` fetches from this repository's default branch to learn which
# catalogs it may serve from here. Its shape is the server's own `catalogs.json`, so it is validated
# by exactly the code a box's own config goes through. Each entry carries `importedFrom`, because an
# import is somebody else's project seen through this repository: a serving box groups its card under
# the upstream's owner and says so on the card, rather than filing every import under whoever happens
# to host the staging repo. No `groups` are declared for the same reason — the owner sections a box
# already derives are the right ones.
#
# The derived file is committed rather than generated at read time because the server fetches one raw
# URL and nothing else: there is no build step between this repository and the box. It is regenerated
# ON MAIN by `catalog-registry.yml` after an import lands, which is what keeps it out of the pull
# requests that would otherwise collide over it.
#
# Every registered import is listed, including one whose delivery branch has not been built yet: a
# server that cannot fetch `design-artifacts/<slug>` says so and retries on its next refresh, which is
# exactly the behaviour wanted while the first build is still running.
#
#   scripts/sync-catalog-registry.sh           # rewrite the file
#   scripts/sync-catalog-registry.sh --check   # fail if it is out of date (CI, on main)
#   scripts/sync-catalog-registry.sh --lint    # check the import descriptions themselves (CI, on PRs)
set -euo pipefail

cd "$(dirname "$0")/.."

derived=.compose-preview/catalogs.json

# Every import description, in directory order, so the generated document is stable.
import_files() {
  find imports -mindepth 2 -maxdepth 2 -name import.json -type f | sort
}

lint() {
  local status=0 file slug upstream dir
  while IFS= read -r file; do
    dir=$(basename "$(dirname "$file")")
    if ! jq -e . "$file" >/dev/null 2>&1; then
      echo "::error file=$file::not valid JSON" >&2
      status=1
      continue
    fi
    slug=$(jq -r '.slug // ""' "$file")
    upstream=$(jq -r '.upstream // ""' "$file")
    # The slug names the delivery branch and the route the server serves this at, and the import
    # branch is import/<slug>: a description disagreeing with its own directory would publish to
    # somewhere nobody is looking. `import.yml` catches it too, three jobs into a build; this catches
    # it in the pull request that is the review.
    [ "$slug" = "$dir" ] || { echo "::error file=$file::slug '$slug' does not match directory '$dir'" >&2; status=1; }
    echo "$upstream" | grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' \
      || { echo "::error file=$file::upstream '$upstream' is not an owner/repo" >&2; status=1; }
  done < <(import_files)
  if [ "$status" -eq 0 ]; then
    echo "$(import_files | wc -l | tr -d ' ') import description(s) are well-formed"
  fi
  return "$status"
}

generate() {
  import_files \
    | xargs -r jq -c '{ system: .slug, listed: true, importedFrom: .upstream }' \
    | jq -S -s '
        {
          "$comment": (
            "GENERATED from the imports/ directory by scripts/sync-catalog-registry.sh — do not edit " +
            "by hand. This is the document a preview server fetches when it nominates this repository " +
            "with --catalog-registry: every catalog listed here is served from this repository'"'"'s own " +
            "design-artifacts/<system> branch. Each carries importedFrom, so a serving box sections " +
            "the catalog under the UPSTREAM owner — beside that owner'"'"'s other catalogs rather " +
            "than under this staging repository — and badges the card with the project it came from."
          ),
          groups: [],
          catalogs: .
        }
      '
}

case "${1:-}" in
  --lint)
    lint
    ;;
  --check)
    if ! diff -u <(generate) "$derived"; then
      echo "::error::$derived is out of date — run scripts/sync-catalog-registry.sh and commit" >&2
      exit 1
    fi
    echo "$derived agrees with the imports/ directory"
    ;;
  "")
    generate > "$derived"
    echo "wrote $derived"
    ;;
  *)
    echo "usage: $0 [--check|--lint]" >&2
    exit 2
    ;;
esac
