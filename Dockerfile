# Zephyr RTOS Build Environment Dockerfile
# Usage: docker build --build-arg ZEPHYR_VERSION=v3.7.0 -t zephyr:v3.7.0 .
# Multi-arch: see docker-bake.hcl.

# --- J-Link unpack stage -----------------------------------------------------
# Runs on the BUILD platform, never emulated. GNU tar fails with ENOSYS on
# symlink/mkdir when running under amd64 emulation on an arm64 host, so the
# tarball is unpacked natively here and the result copied into the final image.
#
# jlink/amd64/ and jlink/arm64/ each hold SEGGER tarballs for that architecture.
# To bump: drop JLink_Linux_<ver>_x86_64.tgz and JLink_Linux_<ver>_arm64.tgz in the
# matching directories and change JLINK_VERSION (or pass --build-arg JLINK_VERSION=...).
FROM --platform=$BUILDPLATFORM ubuntu:latest AS jlink
ARG TARGETARCH
ARG JLINK_VERSION=V970
COPY jlink/${TARGETARCH}/JLink_Linux_${JLINK_VERSION}_*.tgz /tmp/jlink/
RUN set -eux; \
    mkdir -p /opt/SEGGER/JLink; \
    cd /tmp/jlink; \
    TARBALL="$(ls -1 JLink_Linux_*.tgz 2>/dev/null | head -1 || true)"; \
    if [ -z "${TARBALL}" ]; then \
        echo "No J-Link tarball for ${TARGETARCH} in jlink/${TARGETARCH}/ - skipping J-Link install" >&2; \
    else \
        tar -xzf "${TARBALL}"; \
        cp -a "$(basename "${TARBALL}" .tgz)"/. /opt/SEGGER/JLink/; \
    fi
# -----------------------------------------------------------------------------

FROM ubuntu:latest

# Set default Zephyr version (can be overridden with --build-arg)
ARG ZEPHYR_VERSION=v3.7.0
ARG ZEPHYR_SDK_VERSION=0.17.4

# Populated automatically by buildx: amd64 or arm64
ARG TARGETARCH

# Add labels for version tracking
LABEL org.label-schema.name="Zephyr RTOS Build Environment"
LABEL org.label-schema.description="Complete build environment for Zephyr RTOS development"
LABEL org.label-schema.version="${ZEPHYR_VERSION}"
LABEL zephyr.version="${ZEPHYR_VERSION}"
LABEL zephyr.sdk.version="${ZEPHYR_SDK_VERSION}"

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

#SHELL ["/bin/bash", "-c"]

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # Basic build tools
    build-essential \
    cmake \
    ninja-build \
    git \
    wget \
    curl \
    unzip \
    zsh \
    gdb-multiarch \
    # Python and pip
    python3 \
    python3-pip \
    python3-venv \
    # Additional tools for Zephyr
    file \
    gperf \
    pkg-config \
    libncurses5-dev \
    libncursesw5-dev \
    xz-utils \
    # Device tree compiler
    device-tree-compiler \
    # For USB device support
    libusb-1.0-0-dev \
    libudev-dev \
    udev \
    # Additional utilities
    sudo \
    locales \
    srecord \
    && rm -rf /var/lib/apt/lists/*

# RUN ["apt-get", "install", "-y", "zsh"]
# RUN wget https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh || true

# Default powerline10k theme, no plugins installed
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v1.2.1/zsh-in-docker.sh)"
CMD ["/usr/bin/zsh"]

#CMD ["zsh"]


# Set up locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Create a non-root user for development
RUN useradd -m -s /bin/bash -G sudo zephyr && \
    echo "zephyr ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Switch to zephyr user
USER zephyr
WORKDIR /home/zephyr

# Install Python dependencies for Zephyr
# RUN python3 -m pip install --user -U pip && \
#     python3 -m pip install --user wheel setuptools

# Set up Python path
ENV PATH="/home/zephyr/.local/bin:${PATH}"

# Download and install Zephyr SDK with better error handling
# The SDK host arch follows the image arch: amd64 -> x86_64, arm64 -> aarch64
ARG TARGETARCH
RUN set -eux; \
    case "${TARGETARCH}" in \
    amd64) SDK_HOST_ARCH=x86_64 ;; \
    arm64) SDK_HOST_ARCH=aarch64 ;; \
    *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    TARBALL="zephyr-sdk-${ZEPHYR_SDK_VERSION}_linux-${SDK_HOST_ARCH}_minimal.tar.xz"; \
    wget --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 -t 3 \
    "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${ZEPHYR_SDK_VERSION}/${TARBALL}"; \
    tar xf "${TARBALL}"; \
    rm "${TARBALL}"; \
    mv "zephyr-sdk-${ZEPHYR_SDK_VERSION}" zephyr-sdk; \
    cd zephyr-sdk; \
    ./setup.sh -c

# Install specific toolchains (install arm toolchain separately for better reliability)
RUN cd ~/zephyr-sdk && \
    ./setup.sh -t arm-zephyr-eabi

# Create Virtual Environmenet for compatiblity with current setup
RUN python3 -m venv ~/zephyrproject/.venv && . ~/zephyrproject/.venv/bin/activate && pip install west \
    && west init -m https://github.com/zephyrproject-rtos/zephyr --mr ${ZEPHYR_VERSION} zephyrproject && \
    cd zephyrproject && \
    for i in 1 2 3; do west update --fetch-opt=--filter=blob:none && break || (echo "west update attempt $i failed, retrying in 15s..." && sleep 15); done && \
    west zephyr-export

# Install dependencies in venv
RUN cd ~/zephyrproject && \
    . ~/zephyrproject/.venv/bin/activate && \
    pip install -r zephyr/scripts/requirements.txt

# Install Python dependencies for the specific Zephyr version
# RUN cd zephyrproject && \
#     python3 -m pip install --user -r zephyr/scripts/requirements.txt

# Download and install Zephyr SDK - Doesn't work with v3.7.0
#RUN cd ~/zephyrproject/zephyr && west sdk install

# Set environment variables
ENV ZEPHYR_TOOLCHAIN_VARIANT=zephyr
ENV ZEPHYR_SDK_INSTALL_DIR=/home/zephyr/zephyr-sdk
ENV ZEPHYR_BASE=/home/zephyr/zephyrproject/zephyr


# Download and install J-Link Software
# Unpacked in the `jlink` stage above; see the comment there for how to bump it.
COPY --from=jlink /opt/SEGGER/JLink /opt/SEGGER/JLink
RUN if [ -x /opt/SEGGER/JLink/JLinkExe ]; then \
        sudo ln -sf /opt/SEGGER/JLink/JLinkExe /usr/local/bin/JLinkExe; \
    fi

#RUN cp /opt/SEGGER/JLink/99-jlink.rules /usr/lib/udev/rules.d/99-jlink.rules


# RUN cd /tmp && \
#     wget --post-data 'accept_license_agreement=accepted&non_emb_ctr=confirmed&submit=Download+software' \
#     https://www.segger.com/downloads/jlink/JLink_Linux_x86_64.deb -O JLink.deb && \
#     sudo dpkg -i JLink.deb && \
#     rm JLink.deb

# Create a workspace directory for user projects
RUN mkdir -p /home/zephyr/workspace

# Set working directory relative to zephyr west installation
WORKDIR /home/zephyr/zephyrproject

ENV ZEPHY_PATH="~/zephyrproject"

## Install Oh My Zsh (non-interactive via git clone) and create a clean .zshrc
# Clone Oh My Zsh into the user's home and copy the template zshrc.
# Run as the `zephyr` user (current USER is zephyr) so files are owned correctly.
RUN if [ ! -d "$HOME/.oh-my-zsh" ]; then \
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git $HOME/.oh-my-zsh && \
    cp $HOME/.oh-my-zsh/templates/zshrc.zsh-template $HOME/.zshrc ; \
    fi && \
    # Add helpful alias to .zshrc (idempotent)
    grep -qxF "alias source_zephyr_mgo=\"source ~/zephyrproject/zephyr/zephyr-env.sh\"" $HOME/.zshrc || \
    echo 'alias source_zephyr_mgo="source ~/zephyrproject/zephyr/zephyr-env.sh"' >> $HOME/.zshrc

#ENTRYPOINT ["zsh"]
