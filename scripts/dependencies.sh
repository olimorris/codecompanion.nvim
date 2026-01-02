#!/bin/bash

set -e

NVIM_TAG=${NVIM_TAG-nightly}
DEPENDENCIES=(
  ripgrep
)

os=$(uname -s)
if [[ $os == Linux ]]; then
  sudo apt-get update
  for dep in "${DEPENDENCIES[@]}"; do
    sudo apt-get install -y "$dep"
  done
elif [[ $os == Darwin ]]; then
  for dep in "${DEPENDENCIES[@]}"; do
    brew install "$dep"
  done
else
  for dep in "${DEPENDENCIES[@]}"; do
    choco install -y "$dep"
  done
fi
