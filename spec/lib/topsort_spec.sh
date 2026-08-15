#!/bin/sh
# topsort_spec.sh - Tests for lib/topsort.sh

Describe 'lib/topsort.sh'
  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"
  Include "$LIB_DIR/topsort.sh"

  Describe 'reverse_lines()'
    It 'prints input in reverse order'
      Data
        #|alpha
        #|beta
        #|gamma
      End
      When call reverse_lines
      The line 1 should eq "gamma"
      The line 2 should eq "beta"
      The line 3 should eq "alpha"
    End

    It 'returns a single line unchanged'
      Data
        #|only
      End
      When call reverse_lines
      The output should eq "only"
    End

    It 'returns empty output for empty input'
      Data
        #|
      End
      When call reverse_lines
      The output should eq ""
    End
  End

  Describe '_select_uritsort_binary()'
    It 'maps Darwin arm64 to the macos-arm64 binary'
      select_binary() {
        _select_uritsort_binary Darwin arm64
        printf '%s\n' "$_URITSORT_BINARY"
      }
      When call select_binary
      The output should eq "${PROJECT_ROOT}/libexec/uritsort/macos-arm64/uritsort"
    End

    It 'maps Darwin x86_64 to the macos-x86_64 binary'
      select_binary() {
        _select_uritsort_binary Darwin x86_64
        printf '%s\n' "$_URITSORT_BINARY"
      }
      When call select_binary
      The output should eq "${PROJECT_ROOT}/libexec/uritsort/macos-x86_64/uritsort"
    End

    It 'maps Linux aarch64 to the linux-arm64 binary'
      select_binary() {
        _select_uritsort_binary Linux aarch64
        printf '%s\n' "$_URITSORT_BINARY"
      }
      When call select_binary
      The output should eq "${PROJECT_ROOT}/libexec/uritsort/linux-arm64/uritsort"
    End

    It 'maps Linux x86_64 to the linux-x86_64 binary'
      select_binary() {
        _select_uritsort_binary Linux x86_64
        printf '%s\n' "$_URITSORT_BINARY"
      }
      When call select_binary
      The output should eq "${PROJECT_ROOT}/libexec/uritsort/linux-x86_64/uritsort"
    End

    It 'normalizes amd64 to x86_64'
      select_binary() {
        _select_uritsort_binary Linux amd64
        printf '%s\n' "$_URITSORT_BINARY"
      }
      When call select_binary
      The output should eq "${PROJECT_ROOT}/libexec/uritsort/linux-x86_64/uritsort"
    End

    It 'rejects an unsupported OS with the detected values'
      When run script -e -c "
        . '$LIB_DIR/common.sh'
        . '$LIB_DIR/topsort.sh'
        _select_uritsort_binary FreeBSD x86_64
      "
      The status should be failure
      The stderr should include "FreeBSD/x86_64"
    End

    It 'rejects an unsupported architecture with the detected values'
      When run script -e -c "
        . '$LIB_DIR/common.sh'
        . '$LIB_DIR/topsort.sh'
        _select_uritsort_binary Linux riscv64
      "
      The status should be failure
      The stderr should include "Linux/riscv64"
    End

    It 'fails explicitly when the bundled binary is missing'
      _missing_root="${TEST_TMPDIR}/missing"
      mkdir -p "${_missing_root}/lib"
      When run script -e -c "
        LIB_DIR='${_missing_root}/lib'
        . '$LIB_DIR/common.sh'
        . '$LIB_DIR/topsort.sh'
        _select_uritsort_binary Darwin arm64
      "
      The status should be failure
      The stderr should include "Bundled uritsort binary not found"
      The stderr should include "Darwin/arm64"
    End

    It 'fails explicitly when the bundled binary is not executable'
      _nonexec_root="${TEST_TMPDIR}/nonexec"
      mkdir -p "${_nonexec_root}/lib"
      mkdir -p "${_nonexec_root}/libexec/uritsort/linux-x86_64"
      printf '#!/bin/sh\nexit 0\n' > "${_nonexec_root}/libexec/uritsort/linux-x86_64/uritsort"
      chmod 644 "${_nonexec_root}/libexec/uritsort/linux-x86_64/uritsort"
      When run script -e -c "
        LIB_DIR='${_nonexec_root}/lib'
        . '$LIB_DIR/common.sh'
        . '$LIB_DIR/topsort.sh'
        _select_uritsort_binary Linux x86_64
      "
      The status should be failure
      The stderr should include "Bundled uritsort binary is not executable"
      The stderr should include "Linux/x86_64"
    End
  End

  Describe '_prepare_uritsort_input()'
    It 'removes self-edges and deduplicates dependencies for each node'
      _edges="${TEST_TMPDIR}/edges.txt"
      _input="${TEST_TMPDIR}/uritsort.txt"
      printf "b b\na c\na c\nb c\nc c\n" > "$_edges"
      When call _prepare_uritsort_input "$_edges" "$_input"
      The status should be success
      The contents of file "$_input" should eq "b
a
c a b"
    End
  End

  Describe 'topsort_file()'
    It 'sorts a linear graph'
      _edges="${TEST_TMPDIR}/edges.txt"
      printf "a b\nb c\na a\nb b\nc c\n" > "$_edges"
      When call topsort_file "$_edges"
      The status should be success
      The output should eq "a
b
c"
    End

    It 'sorts a branching graph and independent nodes lexicographically'
      _edges="${TEST_TMPDIR}/branch.txt"
      printf "root second\nalpha alpha\nroot first\nroot root\nfirst first\nsecond second\n" > "$_edges"
      When call topsort_file "$_edges"
      The status should be success
      The output should eq "alpha
root
first
second"
    End

    It 'calls die when a circular dependency is detected'
      _edges="${TEST_TMPDIR}/cycle.txt"
      printf "a b\nb a\n" > "$_edges"
      When run script -e -c "
        LIB_DIR='$LIB_DIR'
        . '$LIB_DIR/common.sh'
        . '$LIB_DIR/topsort.sh'
        topsort_file '$_edges'
      "
      The status should be failure
      The stderr should include "Circular dependency"
    End

    It 'handles a node that references only itself'
      _edges="${TEST_TMPDIR}/self.txt"
      printf "y y\nx x\n" > "$_edges"
      When call topsort_file "$_edges"
      The status should be success
      The output should eq "x
y"
    End

    It 'counts duplicate edges only once'
      _edges="${TEST_TMPDIR}/duplicate.txt"
      printf "a c\na c\nb c\nb c\na a\nb b\nc c\n" > "$_edges"
      When call topsort_file "$_edges"
      The status should be success
      The output should eq "a
b
c"
    End

    It 'returns the same result for different input orders of the same graph'
      _first="${TEST_TMPDIR}/first.txt"
      _second="${TEST_TMPDIR}/second.txt"
      printf "root beta\nroot alpha\nroot root\nalpha alpha\nbeta beta\n" > "$_first"
      printf "beta beta\nalpha alpha\nroot root\nroot alpha\nroot beta\n" > "$_second"
      compare_orders() {
        _first_result=$(topsort_file "$_first")
        _second_result=$(topsort_file "$_second")
        [ "$_first_result" = "$_second_result" ]
        printf '%s\n' "$_first_result"
      }
      When call compare_orders
      The status should be success
      The output should eq "root
alpha
beta"
    End

    It 'distinguishes an executor error from a circular dependency'
      _edges="${TEST_TMPDIR}/runner-error.txt"
      _runner="${TEST_TMPDIR}/failing-uritsort"
      printf "a a\n" > "$_edges"
      printf '#!/bin/sh\nprintf "runner failed\\n" >&2\nexit 70\n' > "$_runner"
      chmod 755 "$_runner"
      When run script -e -c "
        . '$LIB_DIR/common.sh'
        . '$LIB_DIR/topsort.sh'
        _topsort_file_with_binary '$_edges' '$_runner'
      "
      The status should be failure
      The stderr should include "Topological sort failed"
      The stderr should include "runner failed"
      The stderr should not include "Circular dependency"
    End
  End

  Describe 'functions that depend on yq'
    Skip if "yq is not installed" has_no_yq

    Describe 'build_dependency_graph()'
      It 'creates an edge file from a manifest'
        _manifest="${TEST_TMPDIR}/manifest.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_manifest"
        _edges="${TEST_TMPDIR}/edges.txt"
        When call build_dependency_graph "$_manifest" "$_edges"
        The status should be success
        The path "$_edges" should be exist
        # The base to custom_emoji edge must exist
        The contents of file "$_edges" should include "base custom_emoji"
      End

      It 'excludes development dependency edges by default'
        _manifest="${TEST_TMPDIR}/dev-manifest.yaml"
        cat > "$_manifest" <<'EOF'
features:
  dev_base:
    dependencies: []
  feature:
    dependencies: []
    dev-dependencies:
      - dev_base
EOF
        _edges="${TEST_TMPDIR}/edges.txt"
        build_dependency_graph "$_manifest" "$_edges"
        The contents of file "$_edges" should not include "dev_base feature"
      End

      It 'includes development dependency edges when include-dev is true'
        _manifest="${TEST_TMPDIR}/dev-manifest.yaml"
        cat > "$_manifest" <<'EOF'
features:
  dev_base:
    dependencies: []
  feature:
    dependencies: []
    dev-dependencies:
      - dev_base
EOF
        _edges="${TEST_TMPDIR}/edges.txt"
        build_dependency_graph "$_manifest" "$_edges" "true"
        The contents of file "$_edges" should include "dev_base feature"
      End
    End

    Describe 'get_sorted_features()'
      It 'sorts features in dependency order'
        _manifest="${TEST_TMPDIR}/manifest.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_manifest"
        When call get_sorted_features "$_manifest"
        The status should be success
        The output should include "base"
        The output should include "custom_emoji"
        The output should include "theme"
      End

      It 'places base before custom_emoji'
        _manifest="${TEST_TMPDIR}/manifest.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_manifest"
        # The line number for base must be lower than the one for custom_emoji
        check_order() {
          _result=$(get_sorted_features "$_manifest")
          _base_line=$(echo "$_result" | grep -n "^base$" | cut -d: -f1)
          _emoji_line=$(echo "$_result" | grep -n "^custom_emoji$" | cut -d: -f1)
          [ "$_base_line" -lt "$_emoji_line" ]
        }
        When call check_order
        The status should be success
      End
    End

    Describe 'render_dependency_graph_tree()'
      It 'prints the dependency graph in tree format'
        _manifest="${TEST_TMPDIR}/manifest.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_manifest"
        When call render_dependency_graph_tree "$_manifest"
        The status should be success
        The output should include "base"
        The output should include "└─ custom_emoji"
        The output should include "theme"
      End

      It 'prints development dependencies when include-dev is true'
        _manifest="${TEST_TMPDIR}/dev-manifest.yaml"
        cat > "$_manifest" <<'EOF'
features:
  dev_base:
    dependencies: []
  feature:
    dependencies: []
    dev-dependencies:
      - dev_base
EOF
        When call render_dependency_graph_tree "$_manifest" "true"
        The output should include "dev_base"
        The output should include "└─ feature"
      End

      It 'does not indent sibling features beneath a previous child'
        _manifest="${TEST_TMPDIR}/sibling-manifest.yaml"
        cat > "$_manifest" <<'EOF'
features:
  root:
    dependencies: []
  first:
    dependencies:
      - root
  first_child:
    dependencies:
      - first
  second:
    dependencies:
      - root
EOF
        When call render_dependency_graph_tree "$_manifest"
        The output should include "├─ first"
        The output should include "│  └─ first_child"
        The output should include "└─ second"
        The output should not include "   └─ first_child"
      End
    End

    Describe 'render_dependency_graph_dot()'
      It 'prints the dependency graph in DOT format'
        _manifest="${TEST_TMPDIR}/manifest.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_manifest"
        When call render_dependency_graph_dot "$_manifest"
        The status should be success
        The output should include "digraph dependencies"
        The output should include '"base" -> "custom_emoji";'
        The output should include '"theme";'
      End
    End

    Describe 'get_feature_with_deps()'
      It 'returns only a specific feature and its dependencies'
        _manifest="${TEST_TMPDIR}/manifest.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_manifest"
        When call get_feature_with_deps "$_manifest" "custom_emoji"
        The output should include "base"
        The output should include "custom_emoji"
        The output should not include "theme"
      End

      It 'returns only the feature itself when it has no dependencies'
        _manifest="${TEST_TMPDIR}/manifest.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_manifest"
        When call get_feature_with_deps "$_manifest" "theme"
        The output should eq "theme"
      End

      It 'excludes development dependencies by default'
        _manifest="${TEST_TMPDIR}/dev-manifest.yaml"
        cat > "$_manifest" <<'EOF'
features:
  dev_base:
    dependencies: []
  feature:
    dependencies: []
    dev-dependencies:
      - dev_base
EOF
        When call get_feature_with_deps "$_manifest" "feature"
        The output should include "feature"
        The output should not include "dev_base"
      End

      It 'recursively includes development dependencies when include-dev is true'
        _manifest="${TEST_TMPDIR}/dev-manifest.yaml"
        cat > "$_manifest" <<'EOF'
features:
  dev_base:
    dependencies: []
  dev_mid:
    dependencies:
      - dev_base
  feature:
    dependencies: []
    dev-dependencies:
      - dev_mid
EOF
        When call get_feature_with_deps "$_manifest" "feature" "true"
        The output should include "dev_base"
        The output should include "dev_mid"
        The output should include "feature"
      End
    End

    Describe 'get_sorted_apply_features()'
      It 'excludes development-only features from the apply list'
        _manifest="${TEST_TMPDIR}/apply-manifest.yaml"
        cat > "$_manifest" <<'EOF'
features:
  dev_base:
    dependencies: []
  feature:
    dependencies: []
    dev-dependencies:
      - dev_base
EOF
        When call get_sorted_apply_features "$_manifest"
        The output should include "feature"
        The output should not include "dev_base"
      End

      It 'includes a feature in the apply list when it is also a regular dependency'
        _manifest="${TEST_TMPDIR}/apply-manifest.yaml"
        cat > "$_manifest" <<'EOF'
features:
  base:
    dependencies: []
  dev_helper:
    dependencies:
      - base
  feature:
    dependencies:
      - base
    dev-dependencies:
      - dev_helper
EOF
        When call get_sorted_apply_features "$_manifest"
        The output should include "base"
        The output should include "feature"
        The output should not include "dev_helper"
      End
    End

    Describe 'check_circular_deps()'
      It 'succeeds when there is no circular dependency'
        _manifest="${TEST_TMPDIR}/manifest.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_manifest"
        When call check_circular_deps "$_manifest"
        The status should be success
      End

      It 'detects a circular dependency'
        _manifest="${TEST_TMPDIR}/circular.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/circular_manifest.yaml" "$_manifest"
        When call check_circular_deps "$_manifest"
        The status should be failure
      End

      It 'calls die without misclassifying an executor error as circular'
        _manifest="${TEST_TMPDIR}/manifest.yaml"
        _runner="${TEST_TMPDIR}/failing-uritsort"
        cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_manifest"
        printf '#!/bin/sh\nprintf "runner failed\\n" >&2\nexit 70\n' > "$_runner"
        chmod 755 "$_runner"
        When run script -e -c "
          LIB_DIR='$LIB_DIR'
          . '$LIB_DIR/common.sh'
          . '$LIB_DIR/yaml.sh'
          . '$LIB_DIR/topsort.sh'
          _select_uritsort_binary() {
            _URITSORT_BINARY='$_runner'
          }
          check_circular_deps '$_manifest'
        "
        The status should be failure
        The stderr should include "Topological sort failed"
        The stderr should include "runner failed"
        The stderr should not include "Circular dependency"
      End
    End
  End
End
