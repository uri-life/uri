#!/bin/sh
# inherit_spec.sh - Tests for lib/inherit.sh

Describe 'lib/inherit.sh'
  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"
  Include "$LIB_DIR/git.sh"
  Include "$LIB_DIR/topsort.sh"
  Include "$LIB_DIR/inherit.sh"

  Describe 'parse_legacy_inherits()'
    It 'parses upstream+patchset format'
      When call parse_legacy_inherits "v4.3.2+stack1.23"
      The output should eq "v4.3.2|stack1.23"
    End

    It 'parses another upstream+patchset format'
      When call parse_legacy_inherits "v4.3.0+stack1.0"
      The output should eq "v4.3.0|stack1.0"
    End

    It 'returns an empty upstream version when only a patchset is present'
      When call parse_legacy_inherits "stack1.23"
      The output should eq "|stack1.23"
    End

    It 'handles another patchset-only format'
      When call parse_legacy_inherits "stack1.0"
      The output should eq "|stack1.0"
    End
  End

  Describe 'path construction functions'
    BeforeEach 'URI_ROOT="/tmp/test_uri"'

    Describe 'resolve_manifest_path()'
      It 'returns the manifest path'
        When call resolve_manifest_path "v4.3.0" "uri1.0"
        The output should eq "/tmp/test_uri/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      End
    End

    Describe 'resolve_patch_dir()'
      It 'returns the patch directory path'
        When call resolve_patch_dir "v4.3.0" "uri1.0"
        The output should eq "/tmp/test_uri/versions/v4.3.0/patches/uri1.0"
      End
    End

    Describe 'resolve_patch_path()'
      It 'returns the patch file path'
        When call resolve_patch_path "v4.3.0" "uri1.0" "custom_emoji"
        The output should eq "/tmp/test_uri/versions/v4.3.0/patches/uri1.0/custom_emoji.patch"
      End
    End
  End

  Describe 'inheritance functions'
    Skip if "yq is not installed" has_no_yq

    setup_inherited() {
      URI_ROOT="$TEST_TMPDIR"
      export URI_ROOT
      create_test_inherited_patchset "$TEST_TMPDIR"
    }
    BeforeEach 'setup_inherited'

    Describe 'get_inheritance_chain()'
      It 'unambiguously reads versions containing + from structured inheritance'
        _parent_dir="${TEST_TMPDIR}/versions/release+meta/patches/patch+base"
        _child_dir="${TEST_TMPDIR}/versions/v1.2.4/patches/patch1.1"
        mkdir -p "$_parent_dir" "$_child_dir"
        printf '%s\n' 'features: {base: {name: Base, description: "", dependencies: []}}' > "$_parent_dir/manifest.yaml"
        cat > "$_child_dir/manifest.yaml" <<'EOF'
inherits:
  upstream-version: release+meta
  patchset-version: patch+base
features: {}
EOF
        When call get_inheritance_chain "v1.2.4" "patch1.1"
        The line 1 should include "v1.2.4/patches/patch1.1"
        The line 2 should include "release+meta/patches/patch+base"
      End

      It 'returns manifest paths from child to ancestor'
        When call get_inheritance_chain "v4.3.0" "uri1.1"
        The line 1 should include "uri1.1/manifest.yaml"
        The line 2 should include "uri1.0/manifest.yaml"
      End

      It 'returns only the current version when there is no inheritance'
        When call get_inheritance_chain "v4.3.0" "uri1.0"
        The lines of output should eq 1
        The output should include "uri1.0/manifest.yaml"
      End
    End

    Describe 'resolve_inheritance()'
      It 'merges parent features into the child'
        _merged=$(resolve_inheritance "v4.3.0" "uri1.1")
        When call yaml_list_features "$_merged"
        # Parent base and theme plus child extra
        The output should include "base"
        The output should include "theme"
        The output should include "extra"
      End

      It 'allows the child to override the parent'
        _merged=$(resolve_inheritance "v4.3.0" "uri1.1")
        When call yaml_get_feature_dependencies "$_merged" "extra"
        The output should include "base"
      End

      It 'removes an inherited feature with child excludes'
        _child="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
        yaml_set_raw "$_child" ".excludes" '["theme"]'
        _merged=$(resolve_inheritance "v4.3.0" "uri1.1")
        When call yaml_list_features "$_merged"
        The output should include "base"
        The output should include "extra"
        The output should not include "theme"
      End

      It 'excludes multiple inherited features'
        _child="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
        yaml_set_raw "$_child" ".features.extra.dependencies" '[]'
        yaml_set_raw "$_child" ".excludes" '["base", "theme"]'
        _merged=$(resolve_inheritance "v4.3.0" "uri1.1")
        When call yaml_list_features "$_merged"
        The output should eq "extra"
      End

      It 'reintroduces an ancestor-excluded feature with a direct declaration in a descendant manifest'
        _child="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
        yaml_set_raw "$_child" ".excludes" '["theme"]'
        _grandchild_dir="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.2"
        mkdir -p "$_grandchild_dir"
        cat > "${_grandchild_dir}/manifest.yaml" <<'EOF'
inherits: uri1.1
features:
  theme:
    name: "Reintroduced Theme"
    description: ""
    dependencies: []
EOF
        _merged=$(resolve_inheritance "v4.3.0" "uri1.2")
        When call yaml_get_feature_name "$_merged" "theme"
        The output should eq "Reintroduced Theme"
      End

      It 'propagates ancestor excludes to deeper descendant manifests'
        _child="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
        yaml_set_raw "$_child" ".excludes" '["theme"]'
        _grandchild_dir="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.2"
        mkdir -p "$_grandchild_dir"
        cat > "${_grandchild_dir}/manifest.yaml" <<'EOF'
inherits: uri1.1
features: {}
EOF
        _merged=$(resolve_inheritance "v4.3.0" "uri1.2")
        When call yaml_list_features "$_merged"
        The output should include "base"
        The output should include "extra"
        The output should not include "theme"
      End

      It 'applies excludes when inheriting from another upstream version'
        _cross_dir="${TEST_TMPDIR}/versions/v4.4.0/patches/uri2.0"
        mkdir -p "$_cross_dir"
        cat > "${_cross_dir}/manifest.yaml" <<'EOF'
inherits: v4.3.0+uri1.0
excludes:
  - theme
features: {}
EOF
        _merged=$(resolve_inheritance "v4.4.0" "uri2.0")
        When call yaml_list_features "$_merged"
        The output should include "base"
        The output should not include "theme"
      End
    End

    Describe 'excludes validation'
      resolve_child() {
        (resolve_inheritance "v4.3.0" "uri1.1")
      }

      It 'rejects a nonexistent inherited feature'
        _child="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
        yaml_set_raw "$_child" ".excludes" '["missing"]'
        When call resolve_child
        The status should be failure
        The stderr should include 'Could not find inherited feature: missing'
      End

      It 'rejects a declaration and exclusion conflict in the same manifest'
        _child="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
        yaml_set_raw "$_child" ".excludes" '["extra"]'
        When call resolve_child
        The status should be failure
        The stderr should include 'cannot be declared and excluded in the same manifest: extra'
      End

      It 'lists affected features when a regular dependency is missing after exclusion'
        _child="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
        yaml_set_raw "$_child" ".excludes" '["base"]'
        When call resolve_child
        The status should be failure
        The stderr should include 'extra.dependencies -> base'
      End

      It 'lists affected features when a development dependency is missing after exclusion'
        _child="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
        yaml_set_raw "$_child" ".features.extra.dependencies" '[]'
        yaml_set_raw "$_child" '.features.extra."dev-dependencies"' '["theme"]'
        yaml_set_raw "$_child" ".excludes" '["theme"]'
        When call resolve_child
        The status should be failure
        The stderr should include 'extra.dev-dependencies -> theme'
      End

      It 'succeeds when both a dependency and its dependent feature are excluded'
        _grandchild_dir="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.2"
        mkdir -p "$_grandchild_dir"
        cat > "${_grandchild_dir}/manifest.yaml" <<'EOF'
inherits: uri1.1
excludes:
  - base
  - extra
features: {}
EOF
        When call resolve_inheritance "v4.3.0" "uri1.2"
        The status should be success
        The output should be present
      End


      It 'succeeds when a deeper descendant manifest reintroduces the missing dependency'
        _child="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
        yaml_set_raw "$_child" ".excludes" '["base"]'
        _grandchild_dir="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.2"
        mkdir -p "$_grandchild_dir"
        cat > "${_grandchild_dir}/manifest.yaml" <<'EOF'
inherits: uri1.1
features:
  base:
    name: "Restored Base Patch"
    description: ""
    dependencies: []
EOF
        When call resolve_inheritance "v4.3.0" "uri1.2"
        The status should be success
        The output should be present
      End
    End

    Describe 'get_all_features()'
      It 'returns the merged feature list'
        When call get_all_features "v4.3.0" "uri1.1"
        The output should include "base"
        The output should include "theme"
        The output should include "extra"
      End
    End

    Describe 'has_feature()'
      It 'returns true for an existing feature'
        When call has_feature "v4.3.0" "uri1.1" "base"
        The status should be success
      End

      It 'finds an inherited feature'
        When call has_feature "v4.3.0" "uri1.1" "theme"
        The status should be success
      End

      It 'returns false for a nonexistent feature'
        When call has_feature "v4.3.0" "uri1.1" "nonexistent"
        The status should be failure
      End
    End

    Describe 'find_patch_file()'
      It 'finds a patch file in the child'
        When call find_patch_file "v4.3.0" "uri1.1" "extra"
        The output should include "uri1.1/extra.patch"
      End

      It 'finds a patch file in the parent when absent from the child'
        When call find_patch_file "v4.3.0" "uri1.1" "base"
        The output should include "uri1.0/base.patch"
      End

      It 'fails when the patch file is nowhere in the chain'
        When call find_patch_file "v4.3.0" "uri1.1" "nonexistent"
        The status should be failure
      End
    End

    Describe 'apply resolution patch lookup'
      It 'finds an ANTE patch with child precedence'
        : > "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/base~ANTE.patch"
        : > "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/base~ANTE.patch"
        When call find_ante_patch "v4.3.0" "uri1.1" "base"
        The output should include "uri1.1/base~ANTE.patch"
      End

      It 'finds a POST patch in the inheritance chain'
        : > "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/base~POST.patch"
        When call find_post_patch "v4.3.0" "uri1.1" "base"
        The output should include "uri1.0/base~POST.patch"
      End

      It 'finds a pair patch'
        : > "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/extra~base.patch"
        When call find_pair_resolution_patch "v4.3.0" "uri1.1" "extra" "base"
        The output should include "uri1.0/extra~base.patch"
      End

      It 'checks completed features in reverse order'
        : > "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/extra~base.patch"
        : > "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/extra~theme.patch"
        When call find_applicable_pair_resolution_patch "v4.3.0" "uri1.1" "extra" "base theme extra" "2"
        The output should include "extra~theme.patch"
      End
    End
  End
End
