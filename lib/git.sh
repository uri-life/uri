#!/bin/sh
# git.sh - Git 유틸리티 함수
# POSIX 호환 셸 스크립트

# 커밋 생성 시 사용할 신원 정보
URI_GIT_NAME="URI"
URI_GIT_EMAIL="uri@uri.life"

# Git 리포지토리인지 확인
# 사용법: git_is_repo "/path/to/dir"
git_is_repo() {
    _dir="$1"
    git -C "$_dir" rev-parse --git-dir >/dev/null 2>&1
}

# Git 리포지토리 확인 (필수)
# 사용법: git_require_repo "/path/to/dir"
git_require_repo() {
    _dir="$1"
    if ! git_is_repo "$_dir"; then
        die "$_dir 는 Git 리포지토리가 아닙니다."
    fi
}

# 워킹 트리가 깨끗한지 확인 (staged/modified 파일만 체크, untracked 무시)
# 사용법: if git_is_clean "/path/to/repo"; then ...
git_is_clean() {
    _dir="$1"
    _status=$(git -C "$_dir" status --porcelain --untracked-files=no 2>/dev/null)
    [ -z "$_status" ]
}

# 워킹 트리 깨끗함 필수 확인
# 사용법: git_ensure_clean "/path/to/repo"
git_ensure_clean() {
    _dir="$1"
    if ! git_is_clean "$_dir"; then
        die "워킹 트리에 커밋되지 않은 변경 사항이 있습니다. 먼저 커밋하거나 스태시하세요."
    fi
}

# 태그로 체크아웃
# 사용법: git_checkout_tag "/path/to/repo" "v4.3.2"
git_checkout_tag() {
    _dir="$1"
    _tag="$2"
    info "태그 $_tag 로 체크아웃합니다..."
    git -C "$_dir" checkout "$_tag" >/dev/null 2>&1 || die "태그 $_tag 를 찾을 수 없습니다."
}

# 브랜치 생성하고 체크아웃
# 사용법: git_create_branch "/path/to/repo" "branch-name"
git_create_branch() {
    _dir="$1"
    _branch="$2"
    git -C "$_dir" checkout -b "$_branch" >/dev/null 2>&1 || die "브랜치 $_branch 생성 실패"
}

# 브랜치 생성 (체크아웃 없이)
# 사용법: git_create_branch_at "/path/to/repo" "branch-name" ["commit"]
git_create_branch_at() {
    _dir="$1"
    _branch="$2"
    _commit="${3:-HEAD}"
    git -C "$_dir" branch "$_branch" "$_commit" >/dev/null 2>&1 || die "브랜치 $_branch 생성 실패"
}

# 브랜치로 체크아웃
# 사용법: git_checkout_branch "/path/to/repo" "branch-name"
git_checkout_branch() {
    _dir="$1"
    _branch="$2"
    git -C "$_dir" checkout "$_branch" >/dev/null 2>&1 || die "브랜치 $_branch 로 체크아웃 실패"
}

# 브랜치 존재 확인
# 사용법: if git_branch_exists "/path/to/repo" "branch-name"; then ...
git_branch_exists() {
    _dir="$1"
    _branch="$2"
    git -C "$_dir" show-ref --verify --quiet "refs/heads/$_branch"
}

# 현재 브랜치 이름 반환
# 사용법: git_current_branch "/path/to/repo"
git_current_branch() {
    _dir="$1"
    git -C "$_dir" rev-parse --abbrev-ref HEAD 2>/dev/null
}

# 현재 커밋 해시 반환
# 사용법: git_current_commit "/path/to/repo"
git_current_commit() {
    _dir="$1"
    git -C "$_dir" rev-parse HEAD 2>/dev/null
}

# 패치 적용 (git am)
# 사용법: git_am "/path/to/repo" "/path/to/patch.patch"
# 반환: 0=성공, 1=충돌 발생
git_am() {
    _dir="$1"
    _patch="$2"
    if GIT_COMMITTER_NAME="$URI_GIT_NAME" GIT_COMMITTER_EMAIL="$URI_GIT_EMAIL" \
       git -C "$_dir" am --3way --no-gpg-sign < "$_patch" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 패치 적용 계속 (충돌 해결 후)
# 사용법: git_am_continue "/path/to/repo"
git_am_continue() {
    _dir="$1"
    GIT_COMMITTER_NAME="$URI_GIT_NAME" GIT_COMMITTER_EMAIL="$URI_GIT_EMAIL" \
    git -C "$_dir" am --continue --no-gpg-sign
}

# 패치 적용 중단 및 원복
# 사용법: git_am_abort "/path/to/repo"
git_am_abort() {
    _dir="$1"
    git -C "$_dir" am --abort 2>/dev/null
}

# git am 진행 중인지 확인
# 사용법: if git_am_in_progress "/path/to/repo"; then ...
git_am_in_progress() {
    _dir="$1"
    [ -d "$_dir/.git/rebase-apply" ]
}

# 패치 추출 (git format-patch)
# 사용법: git_format_patch "/path/to/repo" "commit_range" "/path/to/output.patch"
# 참고: "From <hash>" 줄의 해시는 0으로 채워짐 (커밋 해시 변경으로 인한 불필요한 diff 방지)
git_format_patch() {
    _dir="$1"
    _range="$2"
    _output="$3"
    # --binary: 바이너리 파일을 base64로 인코딩하여 패치에 포함
    # --no-signature: Git 버전 정보를 제거하여 환경 간 일관된 출력 보장
    # --no-stat: diffstat 헤더 (파일 변경 요약) 제거하여 깔끔한 패치 생성
    # 패치 생성 후 "From <hash>" 줄의 해시를 같은 길이의 0으로 대체
    git -C "$_dir" format-patch --binary --no-signature --no-stat --stdout "$_range" | \
        awk '/^From [0-9a-f]+ Mon Sep 17 00:00:00 2001$/ {
            gsub(/[0-9a-f]/, "0", $2)
        } { print }' > "$_output"
}

# 커밋 범위의 커밋 수 반환
# 사용법: git_commit_count "/path/to/repo" "range"
git_commit_count() {
    _dir="$1"
    _range="$2"
    git -C "$_dir" rev-list --count "$_range" 2>/dev/null || echo "0"
}

# HEAD를 detach (현재 브랜치에서 분리)
# 사용법: git_detach_head "/path/to/repo"
git_detach_head() {
    _dir="$1"
    git -C "$_dir" checkout --detach HEAD >/dev/null 2>&1
}

# 브랜치 삭제
# 사용법: git_delete_branch "/path/to/repo" "branch-name"
git_delete_branch() {
    _dir="$1"
    _branch="$2"
    git -C "$_dir" branch -D "$_branch" >/dev/null 2>&1
}

# 원격 저장소 fetch
# 사용법: git_fetch "/path/to/repo"
git_fetch() {
    _dir="$1"
    git -C "$_dir" fetch --all --tags >/dev/null 2>&1
}

# 태그만 fetch (실패해도 무시)
# 사용법: git_fetch_tags_quiet "/path/to/repo"
git_fetch_tags_quiet() {
    _dir="$1"
    git -C "$_dir" fetch --tags >/dev/null 2>&1 || true
}

# uri feature 브랜치 이름 생성 (expand/collapse용)
# 사용법: uri_branch_name "v4.3.2" "uri1.23" "custom_emoji"
uri_branch_name() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _feature="$3"
    echo "uri/${_mastodon_ver}/${_uri_ver}/${_feature}"
}

# uri 버전 브랜치 이름 생성 (apply용)
# 사용법: uri_version_branch_name "v4.3.2" "uri1.23"
uri_version_branch_name() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    echo "uri/${_mastodon_ver}/${_uri_ver}"
}

# (base 브랜치는 더 이상 사용하지 않음 - 태그를 직접 베이스로 사용)

# 두 브랜치/커밋 사이의 diff 존재 확인
# 사용법: if git_has_diff "/path/to/repo" "ref1" "ref2"; then ...
git_has_diff() {
    _dir="$1"
    _ref1="$2"
    _ref2="$3"
    ! git -C "$_dir" diff --quiet "$_ref1" "$_ref2" 2>/dev/null
}
