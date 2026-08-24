# Toolchain image for Lightning CI.
#
# Built once, pushed to GHCR, then pulled by every sweep job (~30s) instead of
# rebuilding Verilator per run (~10 min).
#
# Two things this image exists to pin:
#   1. Verilator v5.048 compiled at -O1. Distro packages and default -O3 builds
#      segfault on this design during C++ header emission under GCC 13.3
#      (see config.mk / docs/porting-log.md 2026-07-07).
#   2. A riscv64-unknown-elf- toolchain with working rv32im/ilp32 multilib,
#      which matches the first entry in RISCV_TOOLCHAIN_CANDIDATES.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        git make cmake autoconf g++ flex bison ccache \
        libgoogle-perftools-dev numactl perl python3 python3-pip \
        libfl2 libfl-dev zlib1g zlib1g-dev help2man \
        curl xz-utils ca-certificates bc \
    && rm -rf /var/lib/apt/lists/*

# --- Verilator v5.048, built at -O1 -----------------------------------------
# NOTE: if your local -O1 recipe differs, make this match it exactly. The
# point is that Verilator's OWN binary is built at -O1; OPT_FAST (which
# controls the generated model's compile flags) is a separate knob.
ARG VERILATOR_TAG=v5.048
RUN git clone --depth 1 --branch ${VERILATOR_TAG} \
        https://github.com/verilator/verilator /tmp/verilator \
    && cd /tmp/verilator \
    && autoconf \
    && ./configure --prefix=/usr/local CXXFLAGS="-O1" CFLAGS="-O1" \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/verilator

# --- RISC-V bare-metal toolchain --------------------------------------------
# Prebuilt nightly from riscv-collab. This is the line most likely to rot;
# bump the tag/filename if the download 404s.
ARG RISCV_RELEASE=2024.09.03
ARG RISCV_TARBALL=riscv32-elf-ubuntu-24.04-gcc-nightly-${RISCV_RELEASE}-nightly.tar.gz
RUN curl -fsSL -o /tmp/rv.tar.gz \
        "https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/${RISCV_RELEASE}/${RISCV_TARBALL}" \
    && mkdir -p /opt/riscv \
    && tar -xzf /tmp/rv.tar.gz -C /opt/riscv --strip-components=1 \
    && rm /tmp/rv.tar.gz

ENV PATH="/opt/riscv/bin:${PATH}"

# The Makefile defaults VERILATOR to $(HOME)/.local/bin/verilator; in here it
# is on PATH, so jobs must export VERILATOR=verilator (the workflow does).
RUN verilator --version && riscv32-unknown-elf-gcc --version
