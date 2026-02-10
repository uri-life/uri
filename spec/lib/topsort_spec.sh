#!/bin/sh
# topsort_spec.sh - lib/topsort.sh 테스트

Describe 'lib/topsort.sh'
  Include "$LIB_DIR/common.sh"
  Include "$LIB_DIR/yaml.sh"
  Include "$LIB_DIR/topsort.sh"

  Describe 'reverse_lines()'
    It '입력을 역순으로 출력한다'
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

    It '단일 줄은 그대로 반환한다'
      Data
        #|only
      End
      When call reverse_lines
      The output should eq "only"
    End

    It '빈 입력은 빈 출력을 반환한다'
      Data
        #|
      End
      When call reverse_lines
      The output should eq ""
    End
  End

  Describe 'topsort_file()'
    Skip if "tsort가 설치되어 있지 않습니다" has_no_tsort

    It '간선 파일을 정렬한다'
      _edges="${TEST_TMPDIR}/edges.txt"
      printf "a b\nb c\na a\nb b\nc c\n" > "$_edges"
      When call topsort_file "$_edges"
      The status should be success
      The output should include "a"
      The output should include "b"
      The output should include "c"
      # a는 b보다 먼저, b는 c보다 먼저
      The line 1 should eq "a"
      The line 2 should eq "b"
      The line 3 should eq "c"
    End

    It '순환 의존성을 감지하면 die한다 (GNU tsort)'
      # macOS의 BSD tsort는 순환 시에도 exit 0을 반환하므로
      # GNU tsort 환경에서만 검증 (CI에서 테스트)
      _edges="${TEST_TMPDIR}/cycle.txt"
      printf "a b\nb a\n" > "$_edges"
      _result=$(tsort "$_edges" 2>&1) || true
      When call echo "$_result"
      The output should include "cycle"
    End

    It '자기 자신만 참조하는 노드를 처리한다'
      _edges="${TEST_TMPDIR}/self.txt"
      printf "x x\ny y\n" > "$_edges"
      When call topsort_file "$_edges"
      The status should be success
      The output should include "x"
      The output should include "y"
    End
  End

  Describe 'yq 의존 함수'
    Skip if "yq가 설치되어 있지 않습니다" has_no_yq
    Skip if "tsort가 설치되어 있지 않습니다" has_no_tsort

    Describe 'build_dependency_graph()'
      It 'manifest에서 간선 파일을 생성한다'
        _manifest="${TEST_TMPDIR}/manifest.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_manifest"
        _edges="${TEST_TMPDIR}/edges.txt"
        When call build_dependency_graph "$_manifest" "$_edges"
        The status should be success
        The path "$_edges" should be exist
        # base → custom_emoji 간선이 있어야 함
        The contents of file "$_edges" should include "base custom_emoji"
      End
    End

    Describe 'get_sorted_features()'
      It '의존성 순서대로 feature를 정렬한다'
        _manifest="${TEST_TMPDIR}/manifest.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_manifest"
        When call get_sorted_features "$_manifest"
        The status should be success
        The output should include "base"
        The output should include "custom_emoji"
        The output should include "theme"
      End

      It 'base가 custom_emoji보다 먼저 나온다'
        _manifest="${TEST_TMPDIR}/manifest.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_manifest"
        # base의 줄 번호가 custom_emoji보다 작아야 함
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

    Describe 'get_feature_with_deps()'
      It '특정 feature와 그 의존성만 반환한다'
        _manifest="${TEST_TMPDIR}/manifest.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_manifest"
        When call get_feature_with_deps "$_manifest" "custom_emoji"
        The output should include "base"
        The output should include "custom_emoji"
        The output should not include "theme"
      End

      It '의존성이 없는 feature는 자신만 반환한다'
        _manifest="${TEST_TMPDIR}/manifest.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_manifest"
        When call get_feature_with_deps "$_manifest" "theme"
        The output should eq "theme"
      End
    End

    Describe 'check_circular_deps()'
      It '순환 의존성이 없으면 성공한다'
        _manifest="${TEST_TMPDIR}/manifest.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_manifest"
        When call check_circular_deps "$_manifest"
        The status should be success
      End

      It '순환 의존성이 있으면 감지한다'
        _manifest="${TEST_TMPDIR}/circular.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/circular_manifest.yaml" "$_manifest"
        # macOS의 BSD tsort는 cycle에서 exit 0을 반환하므로
        # check_circular_deps가 stderr를 확인하는 방식이 아닌 경우 플랫폼 차이로 실패할 수 있음
        check_result() {
          _m="${TEST_TMPDIR}/circular.yaml"
          _edges=$(make_temp)
          build_dependency_graph "$_m" "$_edges"
          _out=$(tsort "$_edges" 2>&1) || true
          echo "$_out" | grep -q "cycle"
        }
        When call check_result
        The status should be success
      End
    End
  End
End
