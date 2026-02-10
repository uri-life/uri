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
  End
End
