# Changelog

All notable user-facing changes to Uri Reconstruction Instrument are documented
in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [2.0.0-rc.4] - 2026-08-21

### Added

- `apply --dev` can now include development dependencies recursively when
  applying a patchset.

### Changed

- Help and usage output now colors commands, options, and placeholders
  individually for clearer syntax while preserving plain output when color is
  disabled.

## [2.0.0-rc.3] - 2026-08-19

### Added

- Active normal targets now have a global discovery index under `~/.uri` while
  their Git-local operation state remains authoritative for recovery.

## [2.0.0-rc.2] - 2026-08-18

### Changed

- Ephemeral clones now use the upstream repository name for their directory
  instead of the generic `repository` name.

## [2.0.0-rc.1] - 2026-08-18

### Added

- Commands can now read patchsets from an explicit local directory, a public
  static HTTP tree, or a Git repository. Remote operations use one consistent
  snapshot, while authoring commands remain local-only.
- Added explicit managed workspaces through the alternative `--ephemeral [ID]`
  TARGET form, with complete listing through `list --ephemeral`, automatic IDs,
  safe removal through `vanish`, and `collapse --discard`.
- Added TTY-aware colored help, status, prompts, warnings, and diagnostics with
  global `--color auto|always|never`; machine-readable output remains plain.

### Changed

- **Breaking:** URI is now distributed as a native executable instead of a
  POSIX shell program that requires `yq` and a bundled `uritsort`. Release
  archives target macOS 13 or later and GNU/Linux with glibc 2.38 or later and
  `GLIBCXX_3.4.32` or later, on ARM64 and x86-64.
- **Breaking:** Omitting `TARGET` now selects the current Git worktree and
  errors when no worktree can be found. Managed clones must be requested
  explicitly with the `--ephemeral [ID]` TARGET form.
- **Breaking:** `collapse` now reads `SOURCE`, `VERSION`, `PATCHSET`, and
  `FEATURE` from expansion state and accepts only an optional path or
  `--ephemeral [ID]` TARGET.
- **Breaking:** Active 1.x expansion and conflict state is not migrated and
  must be completed with 1.x. Manifest and patch file formats remain compatible.
- **Breaking:** Manifest loading now rejects unknown keys and incorrect scalar
  types before changing Git state or patch files.
- Plain `http://` and `https://` sources identify static patchset trees; HTTPS
  Git repositories use the explicit `git+https://` form.
- Existing targets now reject untracked files as well as tracked changes before
  URI modifies them.
- Git authentication now uses existing SSH agents and credential helpers
  without terminal prompts. Static HTTP sources remain unauthenticated, and
  interactive Git credential prompts are disabled.
- Bash, Zsh, and Fish completion scripts are now generated on demand with
  `--generate-completion-script` instead of being distributed as static files;
  they provide local, context-aware VERSION, PATCHSET, FEATURE, inheritance,
  dependency, TARGET, and ephemeral workspace candidates without contacting
  remote sources.

### Fixed

- Restored 1.x root manifest compatibility for the `branch-prefix` wire key and
  the legacy `uri` branch prefix and `URI <uri@uri.life>` committer defaults.

[Unreleased]: https://github.com/uri-life/uri/compare/v2.0.0-rc.4...HEAD
[2.0.0-rc.4]: https://github.com/uri-life/uri/releases/tag/v2.0.0-rc.4
[2.0.0-rc.3]: https://github.com/uri-life/uri/releases/tag/v2.0.0-rc.3
[2.0.0-rc.2]: https://github.com/uri-life/uri/releases/tag/v2.0.0-rc.2
[2.0.0-rc.1]: https://github.com/uri-life/uri/releases/tag/v2.0.0-rc.1
