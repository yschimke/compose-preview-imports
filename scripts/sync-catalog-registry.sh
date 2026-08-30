#!/usr/bin/env bash
# Regenerate `.compose-preview/catalogs.json` from `imports.json`.
#
# Two files, one fact. `imports.json` is what a reviewer reads — the slug, the branch that carries
# the import's config, and the upstream project it builds. `.compose-preview/catalogs.json` is what
# a preview server reads: the document `--catalog-registry <owner>/<repo>` fetches from this
# repository's default branch to learn which catalogs it may serve from here. Its shape is the
# server's own `catalogs.json`, so it is validated by exactly the code a box's own config goes
# through.
#
# The derived file is committed rather than generated at read time because the server fetches one
# raw URL and nothing else: there is no build step between this repository and the box. So it is
# generated here and its agreement with `imports.json` is a CI gate (`--check`), which is the only
# way two files holding one fact stay honest.
#
# Every registered import is listed, including one whose delivery branch has not been built yet: a
# server that cannot fetch `design-artifacts/<slug>` says so and retries on its next refresh, which
# is exactly the behaviour wanted while the first build is still running.
#
#   scripts/sync-catalog-registry.sh          # rewrite the file
#   scripts/sync-catalog-registry.sh --check  # fail if it is out of date (CI)
set -euo pipefail

cd "$(dirname "$0")/.."

registry=imports.json
derived=.compose-preview/catalogs.json

generated=$(
  jq -S '
    {
      "$comment": (
        "GENERATED from imports.json by scripts/sync-catalog-registry.sh — do not edit by hand. " +
        "This is the document a preview server fetches when it nominates this repository with " +
        "--catalog-registry: every catalog listed here is served from this repository'"'"'s own " +
        "design-artifacts/<system> branch."
      ),
      groups: [
        {
          id: "imported-projects",
          heading: "Imported projects",
          noun: "project(s)",
          priority: 0
        }
      ],
      catalogs: [
        .imports[]
        | { system: .slug, group: "imported-projects", listed: true }
      ]
    }
  ' "$registry"
)

if [[ "${1:-}" == "--check" ]]; then
  if ! diff -u <(printf '%s\n' "$generated") "$derived"; then
    echo "::error::$derived is out of date — run scripts/sync-catalog-registry.sh and commit" >&2
    exit 1
  fi
  echo "$derived agrees with $registry"
  exit 0
fi

printf '%s\n' "$generated" > "$derived"
echo "wrote $derived"
