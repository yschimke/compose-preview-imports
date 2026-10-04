#!/usr/bin/env bash
# Generate the catalog registry document — `.compose-preview/catalogs.json` — from the `imports/`
# directory.
#
# The registry used to be a hand-kept array in `imports.json`, and every import's pull request
# appended a line to it — so the first of several open imports to merge left every other one
# conflicting, on a file where nothing had actually disagreed. `imports/<slug>/import.json` already
# holds the same two facts (the slug, and the upstream it builds), one file per import, so the list
# is derived from the directory instead and an import's pull request touches only its own files.
#
# The document is what a preview server reads: the file `--catalog-registry <owner>/<repo>` fetches
# from a repository's default branch to learn which catalogs it may serve from that repository's own
# `design-artifacts/<system>` branches. It is therefore published to the OUTPUT repository,
# `yschimke/compose-preview-imports-out`, beside the delivery branches it names — not to this one,
# which holds only sources and workflows. Its shape is the server's own `catalogs.json`, so it is
# validated by exactly the code a box's own config goes through. Each entry carries `importedFrom`,
# because an import is somebody else's project seen through this repository: a serving box groups its
# card under the upstream's owner and says so on the card, rather than filing every import under
# whoever happens to host the output repository. No `groups` are declared for the same reason — the
# owner sections a box already derives are the right ones.
#
# The document is committed (to the output repository's `main`) rather than generated at read time
# because the server fetches one raw URL and nothing else. `catalog-registry.yml` regenerates and
# pushes it after an import lands on this repository's `main`, which keeps it out of the pull
# requests that would otherwise collide over it.
#
# Every registered import is listed, including one whose delivery branch has not been built yet: a
# server that cannot fetch `design-artifacts/<slug>` says so and retries on its next refresh, which is
# exactly the behaviour wanted while the first build is still running.
#
#   scripts/sync-catalog-registry.sh <file>           # write the document to <file>
#   scripts/sync-catalog-registry.sh --check <file>   # fail if <file> is out of date
#   scripts/sync-catalog-registry.sh --lint           # check the import descriptions (CI, on PRs)
#   scripts/sync-catalog-registry.sh --print          # write the document to stdout
set -euo pipefail

# Resolve a destination before changing directory, so a relative path means what the caller meant.
abspath() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$PWD" "$1" ;;
  esac
}

usage() {
  echo "usage: $0 <file> | --check <file> | --lint | --print" >&2
  exit 2
}

mode="${1:-}"
target=""
case "$mode" in
  --check)
    [ -n "${2:-}" ] || usage
    target=$(abspath "$2")
    ;;
  --lint | --print) ;;
  "" | -*) usage ;;
  *)
    target=$(abspath "$mode")
    mode=write
    ;;
esac

cd "$(dirname "$0")/.."

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
    # The slug names the delivery branch and the route the server serves this at: a description
    # disagreeing with its own directory would publish to somewhere nobody is looking. `import.yml` catches it too, three jobs into a build; this catches
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
            "GENERATED from the imports/ directory of yschimke/compose-preview-imports by " +
            "scripts/sync-catalog-registry.sh — do not edit by hand; change the import there. This is " +
            "the document a preview server fetches when it nominates this repository with " +
            "--catalog-registry: every catalog listed here is served from this repository'"'"'s own " +
            "design-artifacts/<system> branch. Each carries importedFrom, so a serving box sections " +
            "the catalog under the UPSTREAM owner — beside that owner'"'"'s other catalogs rather " +
            "than under this staging repository — and badges the card with the project it came from."
          ),
          groups: [],
          catalogs: .
        }
      '
}

case "$mode" in
  --lint)
    lint
    ;;
  --print)
    generate
    ;;
  --check)
    if ! diff -u <(generate) "$target"; then
      echo "::error::$target is out of date — run scripts/sync-catalog-registry.sh <file>" >&2
      exit 1
    fi
    echo "$target agrees with the imports/ directory"
    ;;
  write)
    mkdir -p "$(dirname "$target")"
    generate > "$target"
    echo "wrote $target"
    ;;
esac
