FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

# Native arm64 toolchain plus an x86_64 cross compiler for `make x86_64`.
RUN apt-get update && apt-get install -y --no-install-recommends \
      bc bison flex make rsync pkg-config \
      gcc g++ gcc-aarch64-linux-gnu gcc-x86-64-linux-gnu \
      binutils binutils-aarch64-linux-gnu binutils-x86-64-linux-gnu \
      libelf-dev libssl-dev \
      python3 python-is-python3 \
      ca-certificates xz-utils tar \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
