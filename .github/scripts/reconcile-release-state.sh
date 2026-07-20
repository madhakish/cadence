#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_SHA:?GITHUB_SHA is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

semantic_release_outcome="${SEMANTIC_RELEASE_OUTCOME:-unknown}"

# The release checkout uses fetch-depth: 0, so retries already contain remote
# tags; a tag created during this run also exists locally. Avoid another fetch
# here so reconciliation does not depend on persisted checkout credentials.

tag="$(git tag --points-at "$GITHUB_SHA" --list 'v[0-9]*' --sort=-version:refname | head -n 1)"
if [[ -n "$tag" ]]; then
  version="${tag#v}"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]; then
    echo "Release tag at $GITHUB_SHA is not a supported semantic version: $tag" >&2
    exit 1
  fi
  {
    echo "published=true"
    echo "version=$version"
  } >> "$GITHUB_OUTPUT"
  echo "Release $tag is ready for downstream publishing."
  exit 0
fi

echo "published=false" >> "$GITHUB_OUTPUT"
if [[ "$semantic_release_outcome" != "success" ]]; then
  echo "semantic-release failed before publishing a tag for $GITHUB_SHA" >&2
  exit 1
fi

echo "No release-producing commit at $GITHUB_SHA."
