# Multi-arch builds for the Zephyr image.
#
#   docker buildx bake v4_4_0 --push          # multi-arch manifest -> Docker Hub
#   docker buildx bake v4_4_0 --load          # local, native arch only (see NATIVE below)
#   docker buildx bake all --push             # every version
#   docker buildx bake --print                # show the resolved plan, build nothing
#
# --push needs a container builder (the default "docker" driver cannot emit two
# platforms in one build), once per machine:
#   docker buildx create --name sig-zephyr --driver docker-container --use
#
# Use that SAME builder for local builds too. BuildKit cache is per-builder, so a
# --load build on one builder is invisible to a --push build on another, and the
# push would rebuild everything from scratch. The build_docker_*.sh wrappers pass
# --builder for you.
#
# Even on a shared builder, only the architecture you already built is reused --
# every layer is arch-specific, so the other architecture always builds in full.
#
# Set CACHE=registry to also persist cache to Docker Hub, which survives builder
# pruning and lets another machine (or CI) reuse it.
#
# --load can only ever hold one architecture per tag with the classic image store,
# so the *_local targets below pin a single platform.

variable "REPO" { default = "lukecorb/sig_zephyr" }
variable "JLINK_VERSION" { default = "V970" }
variable "NATIVE" { default = "linux/arm64" }
variable "CACHE" { default = "" }

target "_common" {
  context    = "."
  dockerfile = "Dockerfile"
  platforms  = ["linux/amd64", "linux/arm64"]
  args = {
    JLINK_VERSION = JLINK_VERSION
  }
  cache-from = CACHE == "registry" ? ["type=registry,ref=${REPO}:buildcache"] : []
  cache-to   = CACHE == "registry" ? ["type=registry,ref=${REPO}:buildcache,mode=max"] : []
}

target "v4_4_0" {
  inherits = ["_common"]
  tags     = ["${REPO}:v4.4.0"]
  args = {
    ZEPHYR_VERSION     = "v4.4.0"
    ZEPHYR_SDK_VERSION = "1.0.1"
  }
}

target "v4_3_0" {
  inherits = ["_common"]
  tags     = ["${REPO}:v4.3.0"]
  args = {
    ZEPHYR_VERSION     = "v4.3.0"
    ZEPHYR_SDK_VERSION = "0.17.4"
  }
}

target "v3_7_1" {
  inherits = ["_common"]
  tags     = ["${REPO}:v3.7.1"]
  args = {
    ZEPHYR_VERSION     = "v3.7.1"
    ZEPHYR_SDK_VERSION = "0.16.8"
  }
}

target "v3_7_0" {
  inherits = ["_common"]
  tags     = ["${REPO}:v3.7.0"]
  args = {
    ZEPHYR_VERSION     = "v3.7.0"
    ZEPHYR_SDK_VERSION = "0.17.4"
  }
}

# SDK 0.16.5 ships no linux-aarch64 tarball, so v3.5.0 is amd64-only.
target "v3_5_0" {
  inherits  = ["_common"]
  platforms = ["linux/amd64"]
  tags      = ["${REPO}:v3.5.0"]
  args = {
    ZEPHYR_VERSION     = "v3.5.0"
    ZEPHYR_SDK_VERSION = "0.16.5"
  }
}

# Single-platform variants for `--load` into the local image store.
target "v4_4_0_local" {
  inherits  = ["v4_4_0"]
  platforms = [NATIVE]
}

target "v4_3_0_local" {
  inherits  = ["v4_3_0"]
  platforms = [NATIVE]
}

group "default" {
  targets = ["v4_4_0"]
}

group "all" {
  targets = ["v4_4_0", "v4_3_0", "v3_7_1", "v3_7_0", "v3_5_0"]
}
