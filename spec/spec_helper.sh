#!/bin/sh
# spec_helper.sh - ShellSpec test helpers
# Settings and utilities shared by all tests in the uri project

set -u

# Project root path
PROJECT_ROOT="${SHELLSPEC_PROJECT_ROOT}"
LIB_DIR="${PROJECT_ROOT}/lib"

# Helpers for checking external dependencies
has_no_yq() { ! command -v yq >/dev/null 2>&1; }
has_no_git() { ! command -v git >/dev/null 2>&1; }

spec_helper_precheck() {
  minimum_version "0.28.0"
}

spec_helper_configure() {
  # tmpdir helper for each test file
  before_each 'setup_test_tmpdir'
  after_each 'cleanup_test_tmpdir'
}

# Create a temporary directory for tests
setup_test_tmpdir() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
}

# Clean up the temporary test directory
cleanup_test_tmpdir() {
  if [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

# Create a patch set structure for tests; requires yq
# Usage: create_test_patchset "$TEST_TMPDIR"
create_test_patchset() {
  _dir="$1"

  # Root manifest
  cat > "${_dir}/manifest.yaml" <<'EOF'
upstream: https://github.com/mastodon/mastodon.git
EOF

  # versions directory
  mkdir -p "${_dir}/versions/v4.3.0/patches/uri1.0"

  # Patchset version manifest
  cat > "${_dir}/versions/v4.3.0/patches/uri1.0/manifest.yaml" <<'EOF'
features:
  base:
    name: "Base Patch"
    description: "Basic configuration changes"
    dependencies: []
  custom_emoji:
    name: "Custom Emoji"
    description: "Extended emoji support"
    dependencies:
      - base
  theme:
    name: "Theme"
    description: "Custom theme"
    dependencies: []
EOF

  # Empty patch files
  : > "${_dir}/versions/v4.3.0/patches/uri1.0/base.patch"
  : > "${_dir}/versions/v4.3.0/patches/uri1.0/custom_emoji.patch"
  : > "${_dir}/versions/v4.3.0/patches/uri1.0/theme.patch"
}

# Create a Git repository for tests
# Usage: create_test_git_repo "$TEST_TMPDIR/repo"
create_test_git_repo() {
  _repo_dir="$1"
  mkdir -p "$_repo_dir"
  git -C "$_repo_dir" init -b main >/dev/null 2>&1
  git -C "$_repo_dir" config user.email "test@example.com" >/dev/null 2>&1
  git -C "$_repo_dir" config user.name "Test" >/dev/null 2>&1
  git -C "$_repo_dir" config tag.gpgSign false >/dev/null 2>&1
  git -C "$_repo_dir" config commit.gpgSign false >/dev/null 2>&1
  git -C "$_repo_dir" remote add origin "https://github.com/mastodon/mastodon.git" >/dev/null 2>&1
  echo "initial" > "${_repo_dir}/README.md"
  git -C "$_repo_dir" add . >/dev/null 2>&1
  git -C "$_repo_dir" commit -m "Initial commit" >/dev/null 2>&1
}

# Create a patch set with inheritance for tests; requires yq
# Usage: create_test_inherited_patchset "$TEST_TMPDIR"
create_test_inherited_patchset() {
  _dir="$1"

  # Root manifest
  cat > "${_dir}/manifest.yaml" <<'EOF'
upstream: https://github.com/mastodon/mastodon.git
EOF

  # Parent version
  mkdir -p "${_dir}/versions/v4.3.0/patches/uri1.0"
  cat > "${_dir}/versions/v4.3.0/patches/uri1.0/manifest.yaml" <<'EOF'
features:
  base:
    name: "Base Patch"
    description: "Basic configuration"
    dependencies: []
  theme:
    name: "Theme"
    description: "Custom theme"
    dependencies: []
EOF
  echo "parent-base-patch" > "${_dir}/versions/v4.3.0/patches/uri1.0/base.patch"
  echo "parent-theme-patch" > "${_dir}/versions/v4.3.0/patches/uri1.0/theme.patch"

  # Child version inheriting uri1.0
  mkdir -p "${_dir}/versions/v4.3.0/patches/uri1.1"
  cat > "${_dir}/versions/v4.3.0/patches/uri1.1/manifest.yaml" <<'EOF'
inherits: "uri1.0"

features:
  extra:
    name: "Additional Feature"
    description: "Feature added in uri1.1"
    dependencies:
      - base
EOF
  : > "${_dir}/versions/v4.3.0/patches/uri1.1/extra.patch"
}
