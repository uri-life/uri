#!/bin/sh
# inherit_spec.sh - lib/inherit.sh 테스트

Describe 'lib/inherit.sh'
  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"
  Include "$LIB_DIR/git.sh"
  Include "$LIB_DIR/topsort.sh"
  Include "$LIB_DIR/inherit.sh"

  Describe 'parse_uri_version()'
    It '"v4.3.2+uri1.23" 형식을 파싱한다'
      When call parse_uri_version "v4.3.2+uri1.23"
      The output should eq "v4.3.2 uri1.23"
    End

    It '"v4.3.0+uri1.0" 형식을 파싱한다'
      When call parse_uri_version "v4.3.0+uri1.0"
      The output should eq "v4.3.0 uri1.0"
    End

    It '"uri1.23" 형식은 mastodon_ver가 비어있다'
      When call parse_uri_version "uri1.23"
      The output should eq " uri1.23"
    End

    It '"uri1.0" 형식도 처리한다'
      When call parse_uri_version "uri1.0"
      The output should eq " uri1.0"
    End
  End

  Describe '경로 계산 함수'
    BeforeEach 'URI_ROOT="/tmp/test_uri"'

    Describe 'resolve_manifest_path()'
      It 'manifest 경로를 반환한다'
        When call resolve_manifest_path "v4.3.0" "uri1.0"
        The output should eq "/tmp/test_uri/versions/v4.3.0/patches/uri1.0/manifest.yaml"
      End
    End

    Describe 'resolve_patch_dir()'
      It '패치 디렉터리 경로를 반환한다'
        When call resolve_patch_dir "v4.3.0" "uri1.0"
        The output should eq "/tmp/test_uri/versions/v4.3.0/patches/uri1.0"
      End
    End

    Describe 'resolve_patch_path()'
      It '패치 파일 경로를 반환한다'
        When call resolve_patch_path "v4.3.0" "uri1.0" "custom_emoji"
        The output should eq "/tmp/test_uri/versions/v4.3.0/patches/uri1.0/custom_emoji.patch"
      End
    End
  End

  Describe '상속 관련 함수'
    Skip if "yq가 설치되어 있지 않습니다" has_no_yq

    setup_inherited() {
      URI_ROOT="$TEST_TMPDIR"
      export URI_ROOT
      create_test_inherited_patchset "$TEST_TMPDIR"
    }
    BeforeEach 'setup_inherited'

    Describe 'get_inheritance_chain()'
      It '자식→조상 순으로 manifest 경로를 반환한다'
        When call get_inheritance_chain "v4.3.0" "uri1.1"
        The line 1 should include "uri1.1/manifest.yaml"
        The line 2 should include "uri1.0/manifest.yaml"
      End

      It '상속이 없는 버전은 자신만 반환한다'
        When call get_inheritance_chain "v4.3.0" "uri1.0"
        The lines of output should eq 1
        The output should include "uri1.0/manifest.yaml"
      End
    End

    Describe 'resolve_inheritance()'
      It '부모 features를 자식에 병합한다'
        _merged=$(resolve_inheritance "v4.3.0" "uri1.1")
        When call yaml_list_features "$_merged"
        # 부모의 base, theme + 자식의 extra
        The output should include "base"
        The output should include "theme"
        The output should include "extra"
      End

      It '자식이 부모를 덮어쓴다'
        _merged=$(resolve_inheritance "v4.3.0" "uri1.1")
        When call yaml_get_feature_dependencies "$_merged" "extra"
        The output should include "base"
      End

      It '자식의 excludes가 상속 feature를 제거한다'
        _child="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
        yaml_set_raw "$_child" ".excludes" '["theme"]'
        _merged=$(resolve_inheritance "v4.3.0" "uri1.1")
        When call yaml_list_features "$_merged"
        The output should include "base"
        The output should include "extra"
        The output should not include "theme"
      End

      It '복수 상속 feature를 제외한다'
        _child="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
        yaml_set_raw "$_child" ".features.extra.dependencies" '[]'
        yaml_set_raw "$_child" ".excludes" '["base", "theme"]'
        _merged=$(resolve_inheritance "v4.3.0" "uri1.1")
        When call yaml_list_features "$_merged"
        The output should eq "extra"
      End

      It '하위 manifest의 직접 선언이 조상에서 제외한 feature를 재도입한다'
        _child="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
        yaml_set_raw "$_child" ".excludes" '["theme"]'
        _grandchild_dir="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.2"
        mkdir -p "$_grandchild_dir"
        cat > "${_grandchild_dir}/manifest.yaml" <<'EOF'
inherits: uri1.1
features:
  theme:
    name: "다시 도입한 테마"
    description: ""
    dependencies: []
EOF
        _merged=$(resolve_inheritance "v4.3.0" "uri1.2")
        When call yaml_get_feature_name "$_merged" "theme"
        The output should eq "다시 도입한 테마"
      End

      It '조상의 excludes가 더 하위 manifest까지 전파된다'
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

      It '다른 Mastodon 버전을 상속해도 excludes를 적용한다'
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

    Describe 'excludes 검증'
      resolve_child() {
        (resolve_inheritance "v4.3.0" "uri1.1")
      }

      It '존재하지 않는 상속 feature를 거부한다'
        _child="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
        yaml_set_raw "$_child" ".excludes" '["missing"]'
        When call resolve_child
        The status should be failure
        The stderr should include '상속된 feature를 찾을 수 없습니다: missing'
      End

      It '같은 manifest의 선언과 제외 충돌을 거부한다'
        _child="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
        yaml_set_raw "$_child" ".excludes" '["extra"]'
        When call resolve_child
        The status should be failure
        The stderr should include '선언하고 제외할 수 없습니다: extra'
      End

      It '제외 후 일반 의존성이 누락되면 관련 feature를 나열한다'
        _child="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
        yaml_set_raw "$_child" ".excludes" '["base"]'
        When call resolve_child
        The status should be failure
        The stderr should include 'extra.dependencies -> base'
      End

      It '제외 후 개발 의존성이 누락되면 관련 feature를 나열한다'
        _child="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
        yaml_set_raw "$_child" ".features.extra.dependencies" '[]'
        yaml_set_raw "$_child" '.features.extra."dev-dependencies"' '["theme"]'
        yaml_set_raw "$_child" ".excludes" '["theme"]'
        When call resolve_child
        The status should be failure
        The stderr should include 'extra.dev-dependencies -> theme'
      End

      It '의존 feature와 종속 feature를 함께 제외하면 성공한다'
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


      It '더 하위 manifest가 누락된 의존 feature를 재도입하면 성공한다'
        _child="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/manifest.yaml"
        yaml_set_raw "$_child" ".excludes" '["base"]'
        _grandchild_dir="${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.2"
        mkdir -p "$_grandchild_dir"
        cat > "${_grandchild_dir}/manifest.yaml" <<'EOF'
inherits: uri1.1
features:
  base:
    name: "복구한 기본 패치"
    description: ""
    dependencies: []
EOF
        When call resolve_inheritance "v4.3.0" "uri1.2"
        The status should be success
        The output should be present
      End
    End

    Describe 'get_all_features()'
      It '병합된 feature 목록을 반환한다'
        When call get_all_features "v4.3.0" "uri1.1"
        The output should include "base"
        The output should include "theme"
        The output should include "extra"
      End
    End

    Describe 'has_feature()'
      It '존재하는 feature는 true를 반환한다'
        When call has_feature "v4.3.0" "uri1.1" "base"
        The status should be success
      End

      It '상속된 feature도 찾을 수 있다'
        When call has_feature "v4.3.0" "uri1.1" "theme"
        The status should be success
      End

      It '존재하지 않는 feature는 false를 반환한다'
        When call has_feature "v4.3.0" "uri1.1" "nonexistent"
        The status should be failure
      End
    End

    Describe 'find_patch_file()'
      It '자식에서 패치 파일을 찾는다'
        When call find_patch_file "v4.3.0" "uri1.1" "extra"
        The output should include "uri1.1/extra.patch"
      End

      It '자식에 없으면 부모에서 찾는다'
        When call find_patch_file "v4.3.0" "uri1.1" "base"
        The output should include "uri1.0/base.patch"
      End

      It '어디에도 없으면 실패한다'
        When call find_patch_file "v4.3.0" "uri1.1" "nonexistent"
        The status should be failure
      End
    End

    Describe 'apply resolution patch lookup'
      It 'ANTE 패치를 자식 우선으로 찾는다'
        : > "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/base~ANTE.patch"
        : > "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.1/base~ANTE.patch"
        When call find_ante_patch "v4.3.0" "uri1.1" "base"
        The output should include "uri1.1/base~ANTE.patch"
      End

      It 'POST 패치를 상속 체인에서 찾는다'
        : > "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/base~POST.patch"
        When call find_post_patch "v4.3.0" "uri1.1" "base"
        The output should include "uri1.0/base~POST.patch"
      End

      It 'pair 패치를 찾는다'
        : > "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/extra~base.patch"
        When call find_pair_resolution_patch "v4.3.0" "uri1.1" "extra" "base"
        The output should include "uri1.0/extra~base.patch"
      End

      It '완료 feature를 역순으로 검사한다'
        : > "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/extra~base.patch"
        : > "${TEST_TMPDIR}/versions/v4.3.0/patches/uri1.0/extra~theme.patch"
        When call find_applicable_pair_resolution_patch "v4.3.0" "uri1.1" "extra" "base theme extra" "2"
        The output should include "extra~theme.patch"
      End
    End
  End
End
