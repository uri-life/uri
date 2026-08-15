#!/bin/sh
# yaml_spec.sh - Tests for lib/yaml.sh

Describe 'lib/yaml.sh'
  Skip if "yq is not installed" has_no_yq

  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"

  Describe 'load_uri_config()'
    load_config_safely() {
      (load_uri_config)
    }

    It 'applies the default prefix and URI committer to a legacy manifest'
      URI_ROOT="$TEST_TMPDIR"
      echo 'upstream: https://example.com/project.git' > "$TEST_TMPDIR/manifest.yaml"
      load_uri_config
      When call printf '%s:%s:%s <%s>' "$URI_BRANCH_PREFIX" "$URI_COMMITTER_MODE" "$URI_COMMITTER_NAME" "$URI_COMMITTER_EMAIL"
      The output should eq 'uri:legacy:URI <uri@uri.life>'
    End

    It 'reads new repository settings'
      URI_ROOT="$TEST_TMPDIR"
      printf '%s\n' 'upstream: https://example.com/project.git' 'branch-prefix: custom' 'committer:' '  mode: repository' > "$TEST_TMPDIR/manifest.yaml"
      load_uri_config
      When call printf '%s:%s' "$URI_BRANCH_PREFIX" "$URI_COMMITTER_MODE"
      The output should eq 'custom:repository'
    End

    It 'rejects an unknown root setting'
      URI_ROOT="$TEST_TMPDIR"
      printf '%s\n' 'upstream: https://example.com/project.git' 'unknown: true' > "$TEST_TMPDIR/manifest.yaml"
      When call load_config_safely
      The status should be failure
      The stderr should include 'Unknown root manifest setting'
    End

    It 'rejects an incomplete explicit committer'
      URI_ROOT="$TEST_TMPDIR"
      printf '%s\n' 'upstream: https://example.com/project.git' 'committer:' '  mode: explicit' '  name: User' > "$TEST_TMPDIR/manifest.yaml"
      When call load_config_safely
      The status should be failure
      The stderr should include 'requires non-empty name and email values'
    End
  End

  Describe 'yaml_create_empty()'
    It 'creates an empty YAML file'
      _file="${TEST_TMPDIR}/empty.yaml"
      When call yaml_create_empty "$_file"
      The contents of file "$_file" should eq "---"
    End
  End

  Describe 'yaml_create()'
    It 'creates a key-value YAML file'
      _file="${TEST_TMPDIR}/created.yaml"
      When call yaml_create "$_file" "name" "test"
      The contents of file "$_file" should eq "name: test"
    End
  End

  Describe 'yaml_set() / yaml_get()'
    setup() {
      _file="${TEST_TMPDIR}/test.yaml"
      echo "---" > "$_file"
    }
    BeforeEach 'setup'

    It 'writes and reads a value'
      yaml_set "$_file" ".key" "value"
      When call yaml_get "$_file" ".key"
      The output should eq "value"
    End

    It 'writes a value to a nested path'
      yaml_set "$_file" ".parent.child" "nested"
      When call yaml_get "$_file" ".parent.child"
      The output should eq "nested"
    End

    It 'overwrites a value'
      yaml_set "$_file" ".key" "old"
      yaml_set "$_file" ".key" "new"
      When call yaml_get "$_file" ".key"
      The output should eq "new"
    End
  End

  Describe 'yaml_set_raw()'
    It 'writes a raw unquoted value'
      _file="${TEST_TMPDIR}/raw.yaml"
      echo "---" > "$_file"
      yaml_set_raw "$_file" ".count" "42"
      When call yaml_get "$_file" ".count"
      The output should eq "42"
    End

    It 'sets an empty array as a raw value'
      _file="${TEST_TMPDIR}/raw.yaml"
      echo "---" > "$_file"
      yaml_set_raw "$_file" ".items" "[]"
      When call yaml_array_len "$_file" ".items"
      The output should eq "0"
    End
  End

  Describe 'yaml_append()'
    It 'appends a value to an array'
      _file="${TEST_TMPDIR}/arr.yaml"
      echo "items: []" > "$_file"
      yaml_append "$_file" ".items" "first"
      yaml_append "$_file" ".items" "second"
      When call yaml_array_len "$_file" ".items"
      The output should eq "2"
    End
  End

  Describe 'yaml_delete()'
    It 'deletes a path'
      _file="${TEST_TMPDIR}/del.yaml"
      echo "a: 1" > "$_file"
      echo "b: 2" >> "$_file"
      yaml_delete "$_file" ".a"
      When call yaml_has "$_file" ".a"
      The status should be failure
    End
  End

  Describe 'yaml_keys()'
    It 'returns the keys of an object'
      _file="${TEST_TMPDIR}/keys.yaml"
      printf "alpha: 1\nbeta: 2\ngamma: 3\n" > "$_file"
      When call yaml_keys "$_file" "."
      The line 1 should eq "alpha"
      The line 2 should eq "beta"
      The line 3 should eq "gamma"
    End
  End

  Describe 'yaml_has()'
    setup() {
      _file="${TEST_TMPDIR}/has.yaml"
      printf "existing: value\nnested:\n  child: yes\n" > "$_file"
    }
    BeforeEach 'setup'

    It 'returns true for an existing path'
      When call yaml_has "$_file" ".existing"
      The status should be success
    End

    It 'returns false for a nonexistent path'
      When call yaml_has "$_file" ".nonexistent"
      The status should be failure
    End

    It 'checks a nested path'
      When call yaml_has "$_file" ".nested.child"
      The status should be success
    End
  End

  Describe 'yaml_array_len()'
    It 'returns the array length'
      _file="${TEST_TMPDIR}/len.yaml"
      printf "items:\n  - a\n  - b\n  - c\n" > "$_file"
      When call yaml_array_len "$_file" ".items"
      The output should eq "3"
    End

    It 'returns 0 for an empty array'
      _file="${TEST_TMPDIR}/len.yaml"
      echo "items: []" > "$_file"
      When call yaml_array_len "$_file" ".items"
      The output should eq "0"
    End
  End

  Describe 'yaml_array_items()'
    It 'returns array elements separated by newlines'
      _file="${TEST_TMPDIR}/items.yaml"
      printf "items:\n  - alpha\n  - beta\n" > "$_file"
      When call yaml_array_items "$_file" ".items"
      The line 1 should eq "alpha"
      The line 2 should eq "beta"
    End
  End

  Describe 'yaml_merge()'
    It 'allows overlay to override base'
      _base="${TEST_TMPDIR}/base.yaml"
      _overlay="${TEST_TMPDIR}/overlay.yaml"
      printf "a: 1\nb: 2\n" > "$_base"
      printf "b: 99\nc: 3\n" > "$_overlay"
      When call yaml_merge "$_base" "$_overlay"
      The output should include "b: 99"
      The output should include "c: 3"
    End
  End

  Describe 'excludes helper functions'
    setup() {
      _file="${TEST_TMPDIR}/excludes.yaml"
      printf 'excludes:\n  - feature-a\nfeatures: {}\n' > "$_file"
    }
    BeforeEach 'setup'

    It 'reads the excludes list'
      When call yaml_list_excludes "$_file"
      The output should eq "feature-a"
    End

    It 'adds and removes a feature in excludes'
      yaml_append_exclude "$_file" "feature-b"
      yaml_remove_exclude "$_file" "feature-a"
      When call yaml_list_excludes "$_file"
      The output should eq "feature-b"
    End

    It 'checks whether excludes contains a feature'
      When call yaml_excludes_feature "$_file" "feature-a"
      The status should be success
    End

    It 'treats a missing excludes value as an empty array'
      _missing="${TEST_TMPDIR}/missing.yaml"
      echo 'features: {}' > "$_missing"
      When call yaml_validate_excludes "$_missing"
      The status should be success
    End

    It 'rejects a non-array excludes value'
      echo 'excludes: feature-a' > "$_file"
      When run script -e -c ". '$LIB_DIR/common.sh'; . '$LIB_DIR/yaml.sh'; yaml_validate_excludes '$_file'"
      The status should be failure
      The stderr should include 'array of strings'
      The stderr should include "$_file"
    End

    It 'rejects a non-string excludes item'
      printf 'excludes:\n  - 1\n' > "$_file"
      When run script -e -c ". '$LIB_DIR/common.sh'; . '$LIB_DIR/yaml.sh'; yaml_validate_excludes '$_file'"
      The status should be failure
      The stderr should include 'non-empty strings'
      The stderr should include 'feature 1'
      The stderr should include "$_file"
    End

    It 'rejects an empty excludes item'
      printf 'excludes:\n  - "   "\n' > "$_file"
      When run script -e -c ". '$LIB_DIR/common.sh'; . '$LIB_DIR/yaml.sh'; yaml_validate_excludes '$_file'"
      The status should be failure
      The stderr should include 'non-empty strings'
    End

    It 'rejects a duplicate excludes item'
      printf 'excludes:\n  - feature-a\n  - feature-a\n' > "$_file"
      When run script -e -c ". '$LIB_DIR/common.sh'; . '$LIB_DIR/yaml.sh'; yaml_validate_excludes '$_file'"
      The status should be failure
      The stderr should include 'duplicate'
      The stderr should include 'feature-a'
      The stderr should include "$_file"
    End
  End

  Describe 'feature helper functions'
    setup() {
      _file="${TEST_TMPDIR}/feat.yaml"
      cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_file"
    }
    BeforeEach 'setup'

    Describe 'yaml_list_features()'
      It 'returns the feature keys'
        When call yaml_list_features "$_file"
        The output should include "base"
        The output should include "custom_emoji"
        The output should include "theme"
      End
    End

    Describe 'yaml_get_feature_name()'
      It 'returns the feature name'
        When call yaml_get_feature_name "$_file" "custom_emoji"
        The output should eq "Custom Emoji"
      End
    End

    Describe 'yaml_get_feature_description()'
      It 'returns the feature description'
        When call yaml_get_feature_description "$_file" "custom_emoji"
        The output should eq "Extended emoji support"
      End
    End

    Describe 'yaml_get_feature_dependencies()'
      It 'returns the dependency list'
        When call yaml_get_feature_dependencies "$_file" "custom_emoji"
        The output should eq "base"
      End

      It 'returns an empty result when there are no dependencies'
        When call yaml_get_feature_dependencies "$_file" "theme"
        The status should be success
      End
    End

    Describe 'yaml_get_feature_dev_dependencies()'
      It 'returns the development dependency list'
        _dev_file="${TEST_TMPDIR}/dev-deps.yaml"
        cat > "$_dev_file" <<'EOF'
features:
  feature:
    dev-dependencies:
      - dev_base
EOF
        When call yaml_get_feature_dev_dependencies "$_dev_file" "feature"
        The output should eq "dev_base"
      End

      It 'returns an empty result when there are no development dependencies'
        When call yaml_get_feature_dev_dependencies "$_file" "theme"
        The status should be success
        The output should eq ""
      End
    End

    Describe 'yaml_get_inherits()'
      It 'returns the inherits value'
        _inh="${TEST_TMPDIR}/inh.yaml"
        printf "inherits: \"uri1.0\"\nfeatures: {}\n" > "$_inh"
        When call yaml_get_inherits "$_inh"
        The output should eq "uri1.0"
      End

      It 'returns an empty string when inherits is absent'
        When call yaml_get_inherits "$_file"
        The output should eq ""
      End
    End

    Describe 'yaml_get_features_json()'
      It 'prints features as JSON'
        When call yaml_get_features_json "$_file"
        The output should include "base"
        The output should include "custom_emoji"
      End
    End
  End
End
