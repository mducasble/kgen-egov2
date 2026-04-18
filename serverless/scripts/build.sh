#!/usr/bin/env bash
# Docker-free alternative to `sam build --use-container`.
#
# Installs the Lambda's Python dependencies with pip's cross-platform
# installer, targeting manylinux2014_aarch64 wheels so the bundle is
# deployable to our arm64 Lambda on any host architecture.
#
# Produces the same layout SAM expects under `.aws-sam/build/`, so
# `sam deploy` afterwards treats it as if SAM had built it.

set -euo pipefail

cd "$(dirname "$0")/.."

FUNCTION_NAME="McapBuilderFunction"
BUILD_DIR=".aws-sam/build/${FUNCTION_NAME}"
PYTHON_VERSION="3.12"
PLATFORM="manylinux2014_aarch64"

echo "→ cleaning ${BUILD_DIR}"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo "→ copying source"
rsync -a --exclude='__pycache__' --exclude='*.pyc' lambda/ "${BUILD_DIR}/"

# Use the system Python so we don't accidentally install from a venv with old pip.
# --python-version + --platform + --only-binary make the result host-independent.
PYTHON_BIN="${PYTHON_BIN:-/usr/bin/python3}"

echo "→ installing deps for ${PLATFORM} / python ${PYTHON_VERSION} (using ${PYTHON_BIN})"
"${PYTHON_BIN}" -m pip install \
  --platform "${PLATFORM}" \
  --target "${BUILD_DIR}" \
  --implementation cp \
  --python-version "${PYTHON_VERSION}" \
  --only-binary=:all: \
  --upgrade \
  --no-compile \
  --quiet \
  -r lambda/requirements.txt

# Strip bytecode caches and metadata that bloat the zip unnecessarily.
find "${BUILD_DIR}" -type d -name '__pycache__' -prune -exec rm -rf {} +
find "${BUILD_DIR}" -type d -name '*.dist-info' -prune -exec rm -rf {} +

# SAM convention: after a build, `.aws-sam/build/template.yaml` references each
# function's CodeUri by its logical id (the folder we just populated).
# Replace `CodeUri: lambda/` with `CodeUri: McapBuilderFunction` so deploy picks it up.
sed "s#CodeUri: lambda/#CodeUri: ${FUNCTION_NAME}#g" template.yaml > .aws-sam/build/template.yaml

echo "✓ built ${BUILD_DIR}"
du -sh "${BUILD_DIR}"
