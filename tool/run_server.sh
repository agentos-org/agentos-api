#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

PORT="${PORT:-20261}"
AGENTOS_BASEURL="${AGENTOS_BASEURL:-http://127.0.0.1:20261}"

export PORT
export AGENTOS_BASEURL

dart run bin/server.dart "$@"
