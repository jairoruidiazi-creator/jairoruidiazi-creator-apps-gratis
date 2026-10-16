#!/usr/bin/env bash
# Publica registros de la CI en una rama huérfana del repositorio, para poder
# leerlos con git cuando la descarga de registros de Actions no está disponible.
#
# Uso: publish_logs.sh <rama> <archivo>...
set -u
BRANCH="$1"
shift
TMP="$(mktemp -d)"
for f in "$@"; do
  if [ -f "$f" ]; then
    cp "$f" "$TMP/$(basename "$f")"
  fi
done
{
  echo "run_id=${GITHUB_RUN_ID:-}"
  echo "sha=${GITHUB_SHA:-}"
  echo "job=${GITHUB_JOB:-}"
  echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$TMP/RUN.txt"
cd "$TMP"
git init -q
git checkout -q -b "$BRANCH"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add -A
git commit -q -m "Registros ${GITHUB_JOB:-} run ${GITHUB_RUN_ID:-}"
git push -q -f "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "$BRANCH" && echo "Registros publicados en la rama $BRANCH"
