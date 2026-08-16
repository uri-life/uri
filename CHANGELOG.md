# Changelog

All notable user-facing changes to Uri Reconstruction Instrument are documented
in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Added the complete URI 2.0 command set for patchset authoring, inspection, and
  Git workflows: `init`, `add`, `remove`, `exclude`, `include`, `list`, `graph`,
  `expand`, `apply`, `collapse`, and `vanish`.
- Added local, public static HTTP, and Git patchset sources. Local sources can be
  discovered from the current directory, while remote sources are fixed to a
  per-operation snapshot.
- Added explicit managed workspaces through the final `--ephemeral [ID]` target
  selector, including workspace listing, path lookup, safe removal, automatic
  IDs, and optional TTY selection.
- Added recoverable `expand` and `apply` conflicts through `--continue` and
  `--abort`, plus state-driven patch reconstruction with `collapse`.
- Added Bash, Zsh, and Fish completion generation through
  `--generate-completion-script`.
- Added `uri --version`, reporting `2.0.0` for an exact `v2.0.0` release tag and
  `dev+<short-commit>` for development builds.

### Changed

- **Breaking:** Omitting `TARGET` now selects the current Git worktree and
  errors when no worktree can be found. Managed clones must be requested
  explicitly with final `--ephemeral [ID]`.
- **Breaking:** `collapse` now reads `SOURCE`, `VERSION`, `PATCHSET`, and
  `FEATURE` from expansion state and accepts only an optional `TARGET` or final
  `--ephemeral [ID]` selector.
- `expand` requires one `FEATURE` and includes development dependencies by
  default; `apply` processes the complete regular dependency graph without
  development-only features.
- Plain `http://` and `https://` sources now identify static patchset trees;
  HTTPS Git repositories use the explicit `git+https://` form.
- Existing targets must have a clean tracked and untracked worktree and an
  `origin` matching the patchset upstream before URI changes them.
- Git authentication now uses existing SSH agents and credential helpers
  without terminal prompts. Static HTTP sources remain unauthenticated, and
  authoring commands remain local-only.
- `init` now initializes only an existing directory and does not create a
  directory or Git repository automatically.
- Manifest and patch files remain compatible with 1.x, but active 1.x expansion
  and conflict state is not migrated and must be completed with 1.x.

### Removed

- **Breaking:** Removed the public `URIPatchset` Swift package product. URI 2.0
  is distributed as an executable only.

### Fixed

- Restored 1.x root manifest compatibility for the `branch-prefix` wire key and
  the legacy `uri` branch prefix and `URI <uri@uri.life>` committer defaults.

[Unreleased]: https://github.com/uri-life/uri/commits/next
