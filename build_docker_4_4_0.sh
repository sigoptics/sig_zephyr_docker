#!/usr/bin/env bash
# Convenience wrapper; the build definition lives in docker-bake.hcl.
#   ./build_docker_4_4_0.sh            -> local, native arch
#   ./build_docker_4_4_0.sh --push     -> multi-arch manifest to Docker Hub
#
# Both paths use the same builder on purpose: BuildKit cache is per-builder, so
# sharing it lets --push reuse whatever the local build already produced.
set -euo pipefail
cd "$(dirname "$0")"

BUILDER="${BUILDER:-sig-zephyr}"
docker buildx inspect "$BUILDER" >/dev/null 2>&1 ||
    docker buildx create --name "$BUILDER" --driver docker-container --bootstrap

if [ "${1:-}" = "--push" ]; then
    exec docker buildx bake --builder "$BUILDER" v4_4_0 --push
fi
exec docker buildx bake --builder "$BUILDER" v4_4_0_local --load
