# Uri Reconstruction Instrument

`uri` is a POSIX shell CLI for managing versioned Git patch sets as independent
features. It stores feature patches, dependencies, inheritance, and application
order in a dedicated repository, then reconstructs them against an upstream Git
project.

> [!CAUTION]
> The code in this repository was written with the assistance of AI tools,
> including large language models (LLMs). It has received only partial code
> review. Use it with caution.

## What it does

- Organizes patches by upstream version, patchset version, and feature.
- Resolves inherited features, exclusions, and development-only dependencies.
- Expands a feature into a working Git repository and collapses changes back
  into patch files.
- Applies a complete patchset in deterministic topological order.
- Preserves conflict state so interrupted `expand` and `apply` operations can
  be continued or aborted.

The product and executable are both named `uri`. Repository discovery uses
`URI_ROOT`, operation state can be redirected with `URI_STATE_DIR`, and
dependency ordering uses the bundled `uritsort` executable.

## Requirements

- POSIX `sh`
- Git
- [mikefarah/yq](https://github.com/mikefarah/yq) 4 or later
- A bundled `libexec/uritsort/` executable for the current platform

Bundled `uritsort` executables support ARM64 and x86-64 on macOS and Linux.
Unsupported combinations fail instead of falling back to the system `tsort`
or another executable on `PATH`.

### Running from source

The executable loads its libraries relative to the repository checkout:

```sh
./bin/uri --help
```

The remaining examples assume that `bin/uri` is available on `PATH` as
`uri`.

## Quick start

```sh
uri init --upstream https://example.com/project.git v1.2.3+build
uri add v1.2.3+build stack-a
uri add v1.2.3+build stack-a feature-a \
  --name "Feature A" \
  --description "First change"

# Edit feature-a.patch, then apply the complete patchset to a new full clone
uri apply v1.2.3+build stack-a
```

When the destination is omitted from `apply` or `expand`, `uri` creates and
preserves a full clone at
`${TMPDIR:-/tmp}/uri-clone.XXXXXX/<repository-name>`. The reported path can
later be used with `--continue`, `--abort`, or `collapse`.

## Concepts

| Term | Meaning | Example |
|------|---------|---------|
| upstream version | The upstream tag or version to which patches apply | `v1.2.3+build` |
| patchset version | A collection of patches for one upstream version | `stack-a` |
| feature | One independently managed change or capability | `custom-theme` |

## Repository layout

```text
patches/
├── manifest.yaml
└── versions/
    └── v1.2.3+build/
        └── patches/
            ├── stack-a/
            │   ├── manifest.yaml
            │   └── feature-a.patch
            └── next-stack/
                └── manifest.yaml
```

## Manifests

### Root manifest

A newly initialized root records the upstream repository, generated branch
prefix, and committer policy:

```yaml
upstream: https://example.com/project.git
branch-prefix: uri
committer:
  mode: repository
```

In `repository` mode, `uri` reads `git config user.name` and
`git config user.email` from the target repository before starting an
operation. If either value is missing, it fails before changing any checkout,
branch, patch, or state file.

An explicit identity can instead be supplied during initialization:

```sh
uri init \
  --upstream https://example.com/project.git \
  --committer-name "Patch Bot" \
  --committer-email patch@example.com
```

This writes the following object:

```yaml
committer:
  mode: explicit
  name: Patch Bot
  email: patch@example.com
```

Existing root manifests remain compatible:

- A missing `branch-prefix` defaults to `uri`.
- A missing `committer` defaults to `URI <uri@uri.life>`.

After a root has been initialized, `uri init UPSTREAM_VERSION` can add only a
version directory without repeating `--upstream`. If stored configuration
options are supplied again, they must exactly match the existing values;
configuration changes are rejected.

### Patchset manifest and inheritance

New manifests store both axes of an inherited patchset:

```yaml
inherits:
  upstream-version: v1.2.3+build
  patchset-version: stack-a

excludes: []

features:
  feature-b:
    name: Feature B
    description: Second change
    dependencies:
      - feature-a
    dev-dependencies: []
```

Both values are recorded even when the parent patchset uses the same upstream
version:

```sh
uri add v1.2.3+build next-stack --inherits stack-a
uri add v1.2.4 next-stack \
  --inherits stack-a \
  --inherits-upstream v1.2.3+build
```

Legacy string values such as `inherits: uri3.1` and
`inherits: v4.5.16+uri3.1` are still accepted. When inheriting a patchset
version that contains `+`, use `--inherits-upstream` to remove ambiguity.

Inherited features and the current `features` map are merged, with child
declarations overriding parent declarations. `excludes` can remove only an
inherited feature that the current manifest does not declare directly. If a
final active feature refers to a missing `dependencies` or
`dev-dependencies` entry, the command fails without changing the manifest.

## Command reference

Run `uri <command> --help` for complete command-specific help.

### Initialize and edit a patchset

```sh
uri init --upstream https://example.com/project.git [upstream_version]
uri init --upstream URL --branch-prefix custom [upstream_version]
uri init [upstream_version] # Add a version to an existing root
```

`--upstream` is required when creating a new root.

```sh
uri add v1.2.3+build stack-a
uri add v1.2.3+build stack-a feature-a --dependencies base
uri remove v1.2.3+build stack-a feature-a
uri exclude v1.2.3+build next-stack legacy-feature
uri include v1.2.3+build next-stack legacy-feature
```

`remove` deletes a directly declared feature and its patch file. Use
`exclude` to disable an inherited feature. `remove -f` skips the confirmation
prompt.

### Inspect a patchset

```sh
uri list                                  # List upstream versions
uri list v1.2.3+build                     # List patchset directories
uri list v1.2.3+build stack-a             # List final active features
uri graph v1.2.3+build stack-a
uri graph v1.2.3+build stack-a --include-dev --format dot
```

Patchset names do not depend on the `uri` prefix. `list` reports every valid
directory containing `patches/<patchset>/manifest.yaml`.

### Expand a feature

```sh
# Omit destination to create and preserve a full clone
uri expand v1.2.3+build stack-a feature-a

# Use an existing repository
uri expand v1.2.3+build stack-a feature-a /path/to/project
uri expand v1.2.3+build stack-a feature-a /path/to/project --no-dev

# A destination is required for conflict recovery
uri expand /path/to/project --continue
uri expand /path/to/project --abort
```

`expand` applies the feature and its dependencies, creating
`<branch-prefix>/<upstream-version>/<patchset-version>/<feature>` at each
feature boundary. It includes `dev-dependencies` by default and excludes them
when `--no-dev` is supplied.

### Collapse a feature

```sh
uri collapse v1.2.3+build stack-a feature-a /path/to/project
uri collapse v1.2.3+build stack-a feature-a /path/to/project --recursive
```

`collapse` extracts patches from the requested feature branch in the specified
source. In a temporary clone, it reconstructs each feature on top of its
declared dependencies and validates the result. In the default mode, dependent
feature candidates must match their current patches before only the requested
patch is saved. `--recursive` also updates patches for recursive dependencies.
If candidate generation or validation fails, neither the patches nor the
original branches are changed.

### Apply a complete patchset

```sh
uri apply v1.2.3+build stack-a
uri apply v1.2.3+build stack-a /path/to/project
uri apply /path/to/project --continue
uri apply /path/to/project --abort
```

`apply` applies every final active feature in topological order without
`dev-dependencies`. The completed branch is
`<branch-prefix>/<upstream-version>/<patchset-version>`.

## Conflict resolution patches

An `apply` operation can use conventionally named resolution patches stored
next to a feature patch:

| File name | When it is applied |
|-----------|--------------------|
| `<feature>~ANTE.patch` | Immediately before the main feature patch |
| `<feature>~POST.patch` | Immediately after the main feature patch |
| `<current>~<completed>.patch` | When `current` conflicts after `completed` has been applied |

A pair resolution patch is applied to the worktree with the active conflict.
`uri` then stages the affected files and attempts `git am --continue`.
Resolution patches are also resolved through the inheritance chain.

## Safety contract

Before changing any checkout, branch, patch, or state file, normal `apply`,
`expand`, and `collapse` operations compare the root manifest's upstream
with the target repository's `origin`.

The comparison:

- Normalizes SSH, SCP, and HTTP(S) forms as well as URL credentials.
- Compares hosts case-insensitively while preserving repository path case.
- Ignores trailing slashes and a trailing `.git`.
- Resolves relative paths and `file://` paths against the patchset root.
- Fails when `origin` is missing or does not match; there is no bypass.

During recovery, `--continue` and `--abort` use the branch prefix and
committer identity captured in the state file when the operation began. They do
not validate `origin` again. New state files use `upstream_version` and
`patchset_version`; the legacy `mastodon_version` and `uri_version` keys
remain readable as fallbacks.

Upstream versions, patchset versions, features, and branch prefixes must begin
with an ASCII letter or digit. Remaining characters are limited to ASCII
letters, digits, and `+._-`. Slashes, spaces, `..`, `.lock`, control
characters, and characters forbidden in Git refs are rejected. The final branch
name is also checked with `git check-ref-format`.

An explicitly supplied destination or source must be an existing Git
repository. Normal operations require a clean tracked worktree. State files are
stored under `${TMPDIR:-/tmp}/uri/state` unless `URI_STATE_DIR` is set.

## Shell completion

Completion files for Bash, Zsh, and Fish are included at:

- `share/bash-completion/completions/uri`
- `share/zsh/site-functions/_uri`
- `share/fish/vendor_completions.d/uri.fish`

The completion scripts discover all upstream and patchset directories
dynamically. Feature completion uses `yq` and `uri list`. The scripts also
support the `init` configuration options and `--inherits-upstream`.

## License

This project is released into the public domain under the terms of
[The Unlicense](UNLICENSE).
