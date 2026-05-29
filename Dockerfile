# syntax=docker/dockerfile:1

# -----------------------------------------------------------------------------
# ratomic local development image
# Installs Rust + Ruby and compiles the native extension for Linux testing.
# macOS contributors test natively; this image covers the Linux platform.
# -----------------------------------------------------------------------------

ARG RUBY_VERSION=3.4
FROM ruby:${RUBY_VERSION}-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    libclang-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Install Rust via rustup (non-interactive, stable toolchain)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app

RUN cargo install cbindgen

# Cache gems separately from source so bundle install
# only re-runs when Gemfile/gemspec changes
COPY Gemfile* *.gemspec ./
COPY lib/ratomic/version.rb lib/ratomic/version.rb
RUN bundle install

# Copy the rest of the source
COPY . .

# Default: compile the extension and run the full test suite
CMD ["bundle", "exec", "rake"]

