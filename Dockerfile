FROM ubuntu:24.04

ENV NVIM_TAG=nightly

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    clang \
    git \
    curl \
    ca-certificates \
    wget \
    unzip \
    ripgrep \
    pandoc \
    file \
 && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs > install-rust.sh \
 && chmod u+x install-rust.sh \
 && ./install-rust.sh -y --default-toolchain 1.93.0 \
 && rm install-rust.sh \
 && /root/.cargo/bin/cargo install --git "https://github.com/tree-sitter/tree-sitter" --tag v0.26.5 --root "/usr/local" tree-sitter-cli \
 && rm -rf /root/.cargo/.rustup /root/.cargo/registry /root/.cargo/git

COPY scripts/ci-install.sh ci-install.sh
RUN sed -i 's/sudo //' ci-install.sh \
 && bash ci-install.sh

RUN curl -LO https://github.com/JohnnyMorganz/StyLua/releases/download/v2.3.1/stylua-linux-x86_64.zip \
 && unzip stylua-linux-x86_64.zip \
 && install stylua /usr/local/bin/stylua \
 && rm -f stylua stylua-linux-x86_64.zip
