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

  Describe '_select_uritsort_binary()'
    It 'Darwin arm64를 macos-arm64 바이너리에 매핑한다'
      select_binary() {
        _select_uritsort_binary Darwin arm64
        printf '%s\n' "$_URITSORT_BINARY"
      }
      When call select_binary
      The output should eq "${PROJECT_ROOT}/libexec/uritsort/macos-arm64/uritsort"
    End

    It 'Darwin x86_64를 macos-x86_64 바이너리에 매핑한다'
      select_binary() {
        _select_uritsort_binary Darwin x86_64
        printf '%s\n' "$_URITSORT_BINARY"
      }
      When call select_binary
      The output should eq "${PROJECT_ROOT}/libexec/uritsort/macos-x86_64/uritsort"
    End

    It 'Linux aarch64를 linux-arm64 바이너리에 매핑한다'
      select_binary() {
        _select_uritsort_binary Linux aarch64
        printf '%s\n' "$_URITSORT_BINARY"
      }
      When call select_binary
      The output should eq "${PROJECT_ROOT}/libexec/uritsort/linux-arm64/uritsort"
    End

    It 'Linux x86_64를 linux-x86_64 바이너리에 매핑한다'
      select_binary() {
        _select_uritsort_binary Linux x86_64
        printf '%s\n' "$_URITSORT_BINARY"
      }
      When call select_binary
      The output should eq "${PROJECT_ROOT}/libexec/uritsort/linux-x86_64/uritsort"
    End

    It 'amd64를 x86_64로 정규화한다'
      select_binary() {
        _select_uritsort_binary Linux amd64
        printf '%s\n' "$_URITSORT_BINARY"
      }
      When call select_binary
      The output should eq "${PROJECT_ROOT}/libexec/uritsort/linux-x86_64/uritsort"
    End

    It '지원하지 않는 OS를 감지값과 함께 거부한다'
      When run script -e -c "
        . '$LIB_DIR/common.sh'
        . '$LIB_DIR/topsort.sh'
        _select_uritsort_binary FreeBSD x86_64
      "
      The status should be failure
      The stderr should include "FreeBSD/x86_64"
    End

    It '지원하지 않는 아키텍처를 감지값과 함께 거부한다'
      When run script -e -c "
        . '$LIB_DIR/common.sh'
        . '$LIB_DIR/topsort.sh'
        _select_uritsort_binary Linux riscv64
      "
      The status should be failure
      The stderr should include "Linux/riscv64"
    End

    It '번들 바이너리가 없으면 명시적으로 실패한다'
      _missing_root="${TEST_TMPDIR}/missing"
      mkdir -p "${_missing_root}/lib"
      When run script -e -c "
        LIB_DIR='${_missing_root}/lib'
        . '$LIB_DIR/common.sh'
        . '$LIB_DIR/topsort.sh'
        _select_uritsort_binary Darwin arm64
      "
      The status should be failure
      The stderr should include "번들 uritsort 바이너리가 없습니다"
      The stderr should include "Darwin/arm64"
    End

    It '번들 바이너리가 실행 불가능하면 명시적으로 실패한다'
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
      The stderr should include "번들 uritsort 바이너리를 실행할 수 없습니다"
      The stderr should include "Linux/x86_64"
    End
  End

  Describe '_prepare_uritsort_input()'
    It 'self-edge를 제거하고 노드별 의존성을 중복 없이 집계한다'
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
    It '선형 그래프를 정렬한다'
      _edges="${TEST_TMPDIR}/edges.txt"
      printf "a b\nb c\na a\nb b\nc c\n" > "$_edges"
      When call topsort_file "$_edges"
      The status should be success
      The output should eq "a
b
c"
    End

    It '분기 그래프와 독립 노드를 사전식으로 정렬한다'
      _edges="${TEST_TMPDIR}/branch.txt"
      printf "root second\nalpha alpha\nroot first\nroot root\nfirst first\nsecond second\n" > "$_edges"
      When call topsort_file "$_edges"
      The status should be success
      The output should eq "alpha
root
first
second"
    End

    It '순환 의존성을 감지하면 die한다'
      _edges="${TEST_TMPDIR}/cycle.txt"
      printf "a b\nb a\n" > "$_edges"
      When run script -e -c "
        LIB_DIR='$LIB_DIR'
        . '$LIB_DIR/common.sh'
        . '$LIB_DIR/topsort.sh'
        topsort_file '$_edges'
      "
      The status should be failure
      The stderr should include "순환 의존성"
    End

    It '자기 자신만 참조하는 노드를 처리한다'
      _edges="${TEST_TMPDIR}/self.txt"
      printf "y y\nx x\n" > "$_edges"
      When call topsort_file "$_edges"
      The status should be success
      The output should eq "x
y"
    End

    It '중복 간선을 한 번만 반영한다'
      _edges="${TEST_TMPDIR}/duplicate.txt"
      printf "a c\na c\nb c\nb c\na a\nb b\nc c\n" > "$_edges"
      When call topsort_file "$_edges"
      The status should be success
      The output should eq "a
b
c"
    End

    It '동일한 그래프의 입력 순서가 달라도 같은 결과를 반환한다'
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

    It '실행기 오류를 순환 오류와 구분한다'
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
      The stderr should include "위상 정렬 실패"
      The stderr should include "runner failed"
      The stderr should not include "순환 의존성"
    End
  End

  Describe 'yq 의존 함수'
    Skip if "yq가 설치되어 있지 않습니다" has_no_yq

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

      It '기본값으로 개발 의존성 간선을 제외한다'
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

      It 'include-dev가 true이면 개발 의존성 간선을 포함한다'
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

    Describe 'render_dependency_graph_tree()'
      It 'tree 형식으로 의존성 그래프를 출력한다'
        _manifest="${TEST_TMPDIR}/manifest.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_manifest"
        When call render_dependency_graph_tree "$_manifest"
        The status should be success
        The output should include "base"
        The output should include "└─ custom_emoji"
        The output should include "theme"
      End

      It 'include-dev가 true이면 개발 의존성을 출력한다'
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

      It '형제 feature를 이전 자식의 하위 항목으로 들여쓰지 않는다'
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
      It 'DOT 형식으로 의존성 그래프를 출력한다'
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

      It '기본값으로 개발 의존성을 제외한다'
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

      It 'include-dev가 true이면 개발 의존성을 재귀적으로 포함한다'
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
      It '개발 의존성 전용 feature를 apply 목록에서 제외한다'
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

      It '일반 의존성이기도 한 feature는 apply 목록에 포함한다'
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
      It '순환 의존성이 없으면 성공한다'
        _manifest="${TEST_TMPDIR}/manifest.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/sample_manifest.yaml" "$_manifest"
        When call check_circular_deps "$_manifest"
        The status should be success
      End

      It '순환 의존성이 있으면 감지한다'
        _manifest="${TEST_TMPDIR}/circular.yaml"
        cp "${PROJECT_ROOT}/spec/support/fixtures/circular_manifest.yaml" "$_manifest"
        When call check_circular_deps "$_manifest"
        The status should be failure
      End

      It '실행기 오류를 순환으로 오인하지 않고 die한다'
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
        The stderr should include "위상 정렬 실패"
        The stderr should include "runner failed"
        The stderr should not include "순환 의존성"
      End
    End
  End
End
