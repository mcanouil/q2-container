# syntax=docker/dockerfile:1
#
# Lean, source-built `q2` (the `quarto` crate binary from quarto-dev/q2).
#
# The source is fetched inside the builder stage, so the build context is
# empty and the host needs neither a q2 checkout nor a Rust toolchain.
#
# Build scope: `cargo build --release -p quarto --features vendored-openssl`.
# `q2 render` / `pampa` / `convert` and all non-preview/non-mcp CLI work.
# `q2 preview` and `q2 mcp` embed placeholder payloads (a fresh-clone build
# does not compile the WASM/SPA/MCP web payloads); see q2 CLAUDE.md.
#
# The toolchain is driven by the fetched rust-toolchain.toml: rustup gets the
# pinned nightly, its components, and the wasm32 target on the first cargo
# call, so the base image only needs rustup + a stable Rust.
ARG RUST_IMAGE=rust:1-bookworm
ARG RUNTIME_IMAGE=debian:bookworm-slim

FROM ${RUST_IMAGE} AS builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake pkg-config perl git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
ARG Q2_REPO_URL=https://github.com/quarto-dev/q2
ARG Q2_REF
ARG Q2_SOURCE_REV
# Shallow-fetch the requested ref. Mentioning ${Q2_SOURCE_REV} in the command
# is what invalidates the layer when upstream moves; the final test catches a
# ref that moved between resolution on the host and this fetch, rather than
# baking a binary the image label misdescribes.
RUN git init -q . \
    && git remote add origin "${Q2_REPO_URL}" \
    && git fetch --depth 1 origin "${Q2_REF}" \
    && git checkout -q --detach FETCH_HEAD \
    && test "$(git rev-parse HEAD)" = "${Q2_SOURCE_REV}"
# Cache mounts keep the cargo registry + target dir warm across rebuilds. The
# binary is copied OUT of the cache-mounted target because cache mounts are not
# persisted into the image layers.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/src/target \
    cargo build --release -p quarto --features vendored-openssl \
    && cp target/release/q2 /usr/local/bin/q2

FROM ${RUNTIME_IMAGE} AS runtime
# vendored-openssl means no runtime libssl dependency; only TLS roots are needed.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /usr/local/bin/q2 /usr/local/bin/q2
# Upstream commit baked in so the host wrapper can detect a stale image and
# offer to rebuild. ARGs do not cross stages, hence the redeclaration.
ARG Q2_SOURCE_REV
LABEL org.quarto.q2.source-rev="${Q2_SOURCE_REV}"
WORKDIR /work
ENTRYPOINT ["q2"]
