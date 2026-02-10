#!/bin/sh
# spec_helper.sh - ShellSpec 테스트 헬퍼
# uri 프로젝트의 전체 테스트에서 공통으로 사용하는 설정과 유틸리티

set -u

# 프로젝트 루트 경로
PROJECT_ROOT="${SHELLSPEC_PROJECT_ROOT}"
LIB_DIR="${PROJECT_ROOT}/lib"

# 외부 의존성 존재 여부 확인 함수
has_no_yq() { ! command -v yq >/dev/null 2>&1; }
has_no_git() { ! command -v git >/dev/null 2>&1; }
has_no_tsort() { ! command -v tsort >/dev/null 2>&1; }

spec_helper_precheck() {
  minimum_version "0.28.0"
}

spec_helper_configure() {
  # 각 테스트 파일에서 사용할 tmpdir 헬퍼
  before_each 'setup_test_tmpdir'
  after_each 'cleanup_test_tmpdir'
}

# 테스트용 임시 디렉터리 생성
setup_test_tmpdir() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
}

# 테스트용 임시 디렉터리 정리
cleanup_test_tmpdir() {
  if [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

# 테스트용 패치 세트 구조 생성 (yq 필요)
# 사용법: create_test_patchset "$TEST_TMPDIR"
create_test_patchset() {
  _dir="$1"

  # 루트 manifest
  cat > "${_dir}/manifest.yaml" <<'EOF'
upstream: https://github.com/mastodon/mastodon.git
EOF

  # versions 디렉터리
  mkdir -p "${_dir}/versions/v4.3.0/patches/uri1.0"

  # uri 버전 manifest
  cat > "${_dir}/versions/v4.3.0/patches/uri1.0/manifest.yaml" <<'EOF'
features:
  base:
    name: "기본 패치"
    description: "기본 설정 변경"
    dependencies: []
  custom_emoji:
    name: "커스텀 이모지"
    description: "이모지 기능 확장"
    dependencies:
      - base
  theme:
    name: "테마"
    description: "커스텀 테마"
    dependencies: []
EOF

  # 빈 패치 파일
  : > "${_dir}/versions/v4.3.0/patches/uri1.0/base.patch"
  : > "${_dir}/versions/v4.3.0/patches/uri1.0/custom_emoji.patch"
  : > "${_dir}/versions/v4.3.0/patches/uri1.0/theme.patch"
}

# 테스트용 Git 리포지토리 생성
# 사용법: create_test_git_repo "$TEST_TMPDIR/repo"
create_test_git_repo() {
  _repo_dir="$1"
  mkdir -p "$_repo_dir"
  git -C "$_repo_dir" init -b main >/dev/null 2>&1
  git -C "$_repo_dir" config user.email "test@example.com" >/dev/null 2>&1
  git -C "$_repo_dir" config user.name "Test" >/dev/null 2>&1
  git -C "$_repo_dir" config tag.gpgSign false >/dev/null 2>&1
  git -C "$_repo_dir" config commit.gpgSign false >/dev/null 2>&1
  echo "initial" > "${_repo_dir}/README.md"
  git -C "$_repo_dir" add . >/dev/null 2>&1
  git -C "$_repo_dir" commit -m "Initial commit" >/dev/null 2>&1
}

# 상속 구조를 가진 패치 세트 생성 (yq 필요)
# 사용법: create_test_inherited_patchset "$TEST_TMPDIR"
create_test_inherited_patchset() {
  _dir="$1"

  # 루트 manifest
  cat > "${_dir}/manifest.yaml" <<'EOF'
upstream: https://github.com/mastodon/mastodon.git
EOF

  # 부모 버전
  mkdir -p "${_dir}/versions/v4.3.0/patches/uri1.0"
  cat > "${_dir}/versions/v4.3.0/patches/uri1.0/manifest.yaml" <<'EOF'
features:
  base:
    name: "기본 패치"
    description: "기본 설정"
    dependencies: []
  theme:
    name: "테마"
    description: "커스텀 테마"
    dependencies: []
EOF
  echo "parent-base-patch" > "${_dir}/versions/v4.3.0/patches/uri1.0/base.patch"
  echo "parent-theme-patch" > "${_dir}/versions/v4.3.0/patches/uri1.0/theme.patch"

  # 자식 버전 (uri1.0을 상속)
  mkdir -p "${_dir}/versions/v4.3.0/patches/uri1.1"
  cat > "${_dir}/versions/v4.3.0/patches/uri1.1/manifest.yaml" <<'EOF'
inherits: "uri1.0"

features:
  extra:
    name: "추가 기능"
    description: "uri1.1에서 추가된 기능"
    dependencies:
      - base
EOF
  : > "${_dir}/versions/v4.3.0/patches/uri1.1/extra.patch"
}
