# q2-container

A reusable Docker image that bakes a `q2` binary built from the
[quarto-dev/q2](https://github.com/quarto-dev/q2) source, plus a host wrapper
so you can run `q2` against files in your working directory without a Rust
toolchain on the host.

The source is fetched inside the Docker build, so you do not need a q2
checkout of your own.

## Prerequisites

- Docker with BuildKit (default in current Docker; the scripts export
  `DOCKER_BUILDKIT=1` regardless).
- `git` on the host, used to resolve which upstream revision to build.

## Build

```bash
git clone https://github.com/mcanouil/q2-container.git
cd q2-container
./q2-image build
```

This fetches `quarto-dev/q2` at its newest release tag, compiles `q2`, and
tags the image `quarto-dev/q2:<version>` and `quarto-dev/q2:latest`. The first
build compiles the whole workspace; later builds reuse BuildKit cargo/target
cache mounts, so only changed crates recompile.

## Pin a different source

`Q2_REF` takes any branch, tag, or full commit SHA:

```bash
Q2_REF=v0.20.0 ./q2-image build     # a specific release
Q2_REF=main ./q2-image build        # the development tip
```

A release tag produces a version-tagged image (`quarto-dev/q2:0.20.0`);
anything else is tagged with the short commit (`quarto-dev/q2:3ac596e0c85e`).
Use `Q2_REPO_URL` to build from a fork.

## Use it from anywhere

Put the wrapper on your `PATH`:

```bash
./q2-image install          # symlinks ~/.local/bin/q2 -> ./q2
```

Then, from any directory:

```bash
q2 --version
q2 render doc.qmd           # reads/writes host files in the current directory
```

The current directory is bind-mounted at `/work` and commands run as your
uid/gid, so generated files are owned by you, not root.

## Update when upstream q2 moves

Rebuild at any time:

```bash
./q2-image build            # or: ./q2-image update
```

You do not have to remember to do this: when you run `q2` interactively and
upstream has moved past the revision baked into the image, the wrapper prints

```text
q2: upstream q2 changed since image build. Rebuild now? [y/N]
```

Answer `y` to rebuild before running, or `N` (default) to run the existing
image. The remote lookup behind that prompt is cached for a day, so it does
not add a network round trip to every command. The check is skipped for
non-interactive runs (pipes, scripts) and can be disabled entirely with
`Q2_NO_UPDATE_CHECK=1`. It compares the commit baked into the image against
the commit the configured ref currently points at; `./q2-image check` reports
the same status (exit 0 fresh, 3 stale, 4 upstream unreachable).

## Commands

| Command                  | Purpose                                                       |
| ------------------------ | ------------------------------------------------------------- |
| `./q2-image build`       | Build/rebuild the image from `quarto-dev/q2`.                 |
| `./q2-image update`      | Alias for `build`.                                            |
| `./q2-image check`       | Exit 0 if the image matches upstream, 3 if stale, 4 if down.  |
| `./q2-image version`     | Print the image tag that would be built.                      |
| `./q2-image shell`       | Open a shell in the image (cwd mounted at `/work`).           |
| `./q2-image install DIR` | Symlink the `q2` wrapper into `DIR` (default `~/.local/bin`). |

Environment overrides: `Q2_REPO_URL`, `Q2_REF`, `Q2_IMAGE_REPO`,
`Q2_UPDATE_CHECK_TTL` (for `q2-image`); `Q2_IMAGE` (for the `q2` wrapper, e.g.
to pin a version tag); `Q2_NO_UPDATE_CHECK=1` (skip the wrapper's stale-image
prompt).

## Scope and caveats

- **Lean CLI build.** `q2 render` / `pampa` / `convert` and other non-preview,
  non-mcp commands work.
- **`q2 preview` and `q2 mcp` are placeholders** in this image; they need the
  full build (Node 24, clang/LLVM, WASM/SPA/MCP payloads), which is out of
  scope here.
- **Pandoc is not installed.** q2 produces Pandoc AST natively and `render`
  does not shell out to it. If you hit a command that needs a system `pandoc`,
  add `pandoc` to the runtime stage's `apt-get install` line in the
  `Dockerfile` and rebuild.

## Licence

MIT, see [LICENSE](LICENSE).
