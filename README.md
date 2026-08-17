# Uri Reconstruction Instrument

`uri` 2.0 is a Swift command-line tool for authoring, expanding, collapsing,
and deploying versioned Git patchsets. A patchset stays a directory tree of
YAML manifests and `git format-patch` files; there is no registry-specific
database or second manifest format.

> [!CAUTION]
> The code in this repository was written with the assistance of AI tools,
> including large language models (LLMs). It has received only partial code
> review. Use it with caution.

## Requirements and installation

Choose the release archive that matches the operating system and architecture:

| Archive | Minimum runtime |
| --- | --- |
| `uri-macos-arm64` | macOS 13 or later on Apple silicon |
| `uri-macos-x86_64` | macOS 13 or later on an Intel Mac |
| `uri-linux-arm64` | ARM64 GNU/Linux with glibc 2.38 or later and `GLIBCXX_3.4.32` or later |
| `uri-linux-x86_64` | x86-64 GNU/Linux with glibc 2.38 or later and `GLIBCXX_3.4.32` or later |

All platforms require a `git` executable on `PATH`. SSH Git remotes also require
an OpenSSH client. HTTPS sources and remotes require a system CA certificate
store; minimal Debian and Ubuntu installations may need the `ca-certificates`
package.

Terminal credential prompts are disabled. Windows, static HTTP authentication,
and interactive Git credential prompts are not supported.

To build from source, install Swift 6.3.3 and run:

```sh
swift build -c release
swift test
```

Releases contain only the `uri` executable. Linux release archives use the
static Swift standard library. Every platform archive is accompanied by a
SHA-256 file.

## Patchset layout and compatibility

```text
patches/
├── manifest.yaml
└── versions/
    └── v1.2.3/
        └── patches/
            └── patch1.0/
                ├── manifest.yaml
                ├── feature-a.patch
                ├── feature-a~ANTE.patch
                ├── feature-a~POST.patch
                └── feature-b~feature-a.patch
```

The root manifest uses the existing 1.x wire keys:

```yaml
upstream: https://example.com/project.git
branch-prefix: uri
committer:
  mode: repository
```

An explicit committer has `mode: explicit`, `name`, and `email`. Legacy roots
without `branch-prefix` or `committer` use `uri` and
`URI <uri@uri.life>`. Patchset manifests retain `inherits`, `excludes`, the
ID-keyed `features` map, `dependencies`, and `dev-dependencies`. Unknown keys
and incorrect scalar types are rejected before an operation changes Git or a
patch file.

## SOURCE and TARGET

Commands that read a patchset accept a leading optional `[SOURCE]`:

- `/absolute/path`, `./relative/path`, `../relative/path`, and `~/path` select
  a local patchset. Without SOURCE, `uri` searches ancestors of the current
  directory for the root `manifest.yaml`.
- `http://` and `https://` select a public static patchset root. `uri` reads
  `manifest.yaml` and the required `versions/...` files below that URL.
- `git+https://`, `git+ssh://`, `ssh://`, `git://`, and SCP syntax select a Git
  patchset. The repository's default HEAD is shallow-cloned and fixed for the
  operation.

Authoring commands (`init`, `add`, `remove`, `exclude`, and `include`) require a
local SOURCE. Static HTTP sources have no version index, so only
`uri list HTTP_SOURCE VERSION PATCHSET` is supported; version and patchset
enumeration is rejected explicitly.

`expand` and `apply` accept an optional existing Git `[TARGET]`. Without one,
the current Git worktree is used. There is no implicit temporary clone. Before
changing an existing target, `uri` requires its `origin` to match the root
manifest's `upstream` and requires both tracked and untracked files to be clean.
Only the requested VERSION tag is fetched.

## Command overview

```sh
# Create a root in an existing directory and add an upstream version
uri init ./patches --upstream https://example.com/project.git v1.2.3

# Author patchsets and features
uri add ./patches v1.2.3 patch1.0
uri add ./patches v1.2.3 patch1.0 feature-a \
  --name "Feature A" --dependencies base --dev-dependencies test-helper
uri exclude ./patches v1.2.3 patch1.1 inherited-feature
uri include ./patches v1.2.3 patch1.1 inherited-feature
uri remove --force ./patches v1.2.3 patch1.0 feature-a

# Inspect
uri list ./patches
uri list ./patches v1.2.3
uri list ./patches v1.2.3 patch1.0
uri graph --include-dev --format dot ./patches v1.2.3 patch1.0

# Expand one feature (FEATURE is required)
uri expand ./patches v1.2.3 patch1.0 feature-a /work/project
uri expand --no-dev ./patches v1.2.3 patch1.0 feature-a /work/project

# Apply the complete regular dependency graph
uri apply ./patches v1.2.3 patch1.0 /work/project
```

`expand` creates
`<branch-prefix>/<VERSION>/<PATCHSET>/<FEATURE>` at every feature boundary and
includes development dependencies by default. `apply` excludes
development-only features and creates `<branch-prefix>/<VERSION>/<PATCHSET>`.
Both workflows apply each feature in `ANTE`, main, pair-resolution, and `POST`
order using `git am --3way`.

If a mailbox patch conflicts, resolve and stage the files, then continue or
abort against the same target:

```sh
uri expand --continue /work/project
uri expand --abort /work/project
uri apply --continue /work/project
uri apply --abort /work/project
```

After a completed local expansion, collapse reads SOURCE, VERSION, PATCHSET,
and FEATURE from Git-local state:

```sh
uri collapse /work/project
uri collapse --recursive /work/project
uri collapse --discard /work/project
```

Collapse reconstructs each feature's unique commits on its declared
dependencies in a separate clone. It validates every candidate before replacing
patches transactionally. Failure preserves the patch files, feature branches,
operation state, and temporary remote snapshot. `--recursive` updates the
selected feature and its dependency candidates. `--discard` only closes the
expansion and cannot be combined with `--recursive`. Expansions from remote
sources are read-only and therefore permit only `collapse --discard`.

Run `uri <command> --help` for every option.

## Ephemeral workspaces

An ephemeral target is created only when `--ephemeral [ID]` is the final target
selector. Other options must precede it:

```sh
uri expand ./patches v1.2.3 patch1.0 feature-a --ephemeral peach
uri apply ./patches v1.2.3 patch1.0 --ephemeral
uri collapse --discard --ephemeral peach
```

The optional ID matches `[A-Za-z_][A-Za-z0-9_-]*`. Automatic IDs use a system
word list when one is available and a bundled fallback otherwise. Workspaces
live under `~/.uri/ephemeral/<ID>/repository` and clone exactly VERSION with
`--depth 1 --single-branch --branch VERSION`.

```sh
uri list --ephemeral
uri list --ephemeral peach
uri list --ephemeral peach --path
uri vanish peach
uri vanish peach --force
```

With no ID, `vanish` chooses the only workspace, prompts when several exist on
a TTY, and errors in non-interactive use. A normal vanish requires a clean
worktree at the recorded HEAD. `--force` bypasses only those two change checks;
canonical path, symlink, ID, metadata, and managed-root validation always run.
An ephemeral `apply` cannot be collapsed and is closed with `vanish`. Successful
ephemeral collapse, discard, or abort removes its workspace and operation
snapshot; failures preserve them.

## State and remote snapshots

Normal target state is versioned JSON below the path returned by:

```sh
git rev-parse --git-path uri/state.json
```

Ephemeral state is `~/.uri/ephemeral/<ID>/state.json`. It records the operation
mode and phase, original source and fixed snapshot, VERSION/PATCHSET/FEATURE,
application order and index, target, starting and upstream baseline commits,
branch policy, committer, and ephemeral ID. There is no global "last
repository" pointer.

HTTP and Git sources get one fixed snapshot per operation under
`~/.uri/cache/operations/`. HTTP redirects are followed, required 404s are
reported, and missing optional patch files are allowed. A shared URL cache and
Git ref selection are intentionally not implemented.

## Shell completion and versioning

Swift Argument Parser generates completion scripts through its official entry
point:

```sh
uri --generate-completion-script bash
uri --generate-completion-script zsh
uri --generate-completion-script fish
```

An exact `v2.0.0` release tag reports `2.0.0`; development builds report
`dev+<short-commit>`.

## Migrating from 1.x

- Manifest and patch wire formats remain compatible.
- Omitted TARGET now means the current Git worktree, not a persistent temporary
  clone. Use final `--ephemeral [ID]` when a managed clone is desired.
- `collapse` no longer repeats SOURCE, VERSION, PATCHSET, and FEATURE; it reads
  the expansion's JSON state and accepts only `[TARGET]` or final
  `--ephemeral [ID]`.
- Static HTTPS and explicit Git sources have different syntax: plain HTTP(S) is
  a static tree, while an HTTPS Git repository begins with `git+https://`.
- Active 1.x expansion and conflict state is not migrated. Finish that work
  with 1.x before starting a 2.0 operation.

Deferred features include `doctor`, shared remote caching, Git source ref
selection, a static HTTP listing index, HTTP authentication, interactive Git
credentials, Windows, and a public Swift library product.

## License

`uri` is released into the public domain under the [Unlicense](UNLICENSE).
