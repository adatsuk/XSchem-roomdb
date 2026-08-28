#!/usr/bin/env bash
# Install build dependencies on Ubuntu 24.04 (CI and local).
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  build-essential cmake git pkg-config curl patchelf \
  autoconf automake libtool zlib1g-dev \
  flex bison gawk \
  tcl tcl-dev tk tk-dev \
  libcairo2-dev libxpm-dev libxrender-dev libxcb1-dev libx11-dev \
  libjpeg-dev
