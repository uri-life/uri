#!/bin/sh
# migrate.sh - migrate 명령 구현
# 기존 브랜치 기반 패치 세트에서 uri 구조로 마이그레이션
# POSIX 호환 셸 스크립트

# migrate 명령 사용법 출력
migrate_usage() {
    cat <<EOF
사용법: uri migrate <old_repo> <branch_prefix> <uri_minor> <new_repo>

기존 브랜치 기반 패치 세트에서 uri 구조로 마이그레이션합니다.

인자:
  old_repo        기존 리포지토리 경로 (예: /path/to/old_mastodon)
  branch_prefix   브랜치 접두사 (예: v4.3.2/uri1)
  uri_minor       uri 버전 소수 부분 (예: 23)
  new_repo        새 리포지토리 경로 (예: /path/to/new_mastodon)

브랜치 접두사 형식:
  {mastodon_version}/{uri_major}
  예: v4.3.2/uri1 -> mastodon_version=v4.3.2, uri_major=uri1

동작:
  1. old_repo에서 {branch_prefix}/*로 시작하는 모든 브랜치를 탐색합니다.
  2. 각 브랜치에서 접두사를 제거하여 feature 이름을 추출합니다.
     예: v4.3.2/uri1/custom_emoji -> custom_emoji
  3. new_repo에서 uri 패치 세트를 초기화합니다.
  4. 각 feature에 대해:
     - add로 feature 추가
     - expand로 브랜치 생성
     - old_repo의 커밋들을 cherry-pick
     - collapse로 패치 파일 생성
  5. apply를 실행하여 모든 패치가 올바르게 적용되는지 확인합니다.

옵션:
  -h, --help       이 도움말을 출력합니다

예시:
  uri migrate /old/mastodon v4.3.2/uri1 23 /new/mastodon
EOF
}

# migrate 명령 메인 함수
cmd_migrate() {
    _old_repo=""
    _branch_prefix=""
    _uri_minor=""
    _new_repo=""

    # 옵션 파싱
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                migrate_usage
                exit 0
                ;;
            -*)
                die "알 수 없는 옵션: $1"
                ;;
            *)
                # 위치 인자
                if [ -z "$_old_repo" ]; then
                    _old_repo="$1"
                elif [ -z "$_branch_prefix" ]; then
                    _branch_prefix="$1"
                elif [ -z "$_uri_minor" ]; then
                    _uri_minor="$1"
                elif [ -z "$_new_repo" ]; then
                    _new_repo="$1"
                else
                    die "인자가 너무 많습니다: $1"
                fi
                ;;
        esac
        shift
    done

    # 필수 인자 확인
    if [ -z "$_old_repo" ] || [ -z "$_branch_prefix" ] || [ -z "$_uri_minor" ] || [ -z "$_new_repo" ]; then
        die "old_repo, branch_prefix, uri_minor, new_repo가 모두 필요합니다. 'uri migrate --help'를 참조하세요."
    fi

    # 경로 해석
    _old_repo=$(resolve_path "$_old_repo")
    _new_repo=$(resolve_path "$_new_repo")

    # Git 리포지토리 확인
    git_require_repo "$_old_repo"
    git_require_repo "$_new_repo"

    # 워킹 트리 깨끗한지 확인
    git_ensure_clean "$_old_repo"
    git_ensure_clean "$_new_repo"

    # 브랜치 접두사에서 mastodon_version과 uri_major 추출
    # 형식: v4.3.2/uri1 -> mastodon_version=v4.3.2, uri_major=uri1
    _mastodon_ver=$(echo "$_branch_prefix" | cut -d'/' -f1)
    _uri_major=$(echo "$_branch_prefix" | cut -d'/' -f2)

    if [ -z "$_mastodon_ver" ] || [ -z "$_uri_major" ]; then
        die "브랜치 접두사 형식이 올바르지 않습니다. '{mastodon_version}/{uri_major}' 형식이어야 합니다."
    fi

    # uri 버전 조합
    _uri_ver="${_uri_major}.${_uri_minor}"

    info "마이그레이션 시작"
    info "  기존 리포지토리: $_old_repo"
    info "  새 리포지토리: $_new_repo"
    info "  Mastodon 버전: $_mastodon_ver"
    info "  uri 버전: $_uri_ver"
    info "  브랜치 접두사: $_branch_prefix"

    # 브랜치 탐색
    _features=$(_find_branches_by_prefix "$_old_repo" "$_branch_prefix")

    if [ -z "$_features" ]; then
        die "접두사 '$_branch_prefix/'로 시작하는 브랜치를 찾을 수 없습니다."
    fi

    info "발견된 feature 목록:"
    for _f in $_features; do
        echo "  - $_f"
    done

    # 새 리포지토리에서 uri 패치 세트 초기화
    _init_migrate_patchset "$_new_repo" "$_mastodon_ver" "$_uri_ver"

    # old_repo를 new_repo의 remote로 추가 (cherry-pick을 위해)
    _remote_name="_migrate_source"
    info "기존 리포지토리를 remote로 추가합니다..."
    git -C "$_new_repo" remote add "$_remote_name" "$_old_repo" 2>/dev/null || \
        git -C "$_new_repo" remote set-url "$_remote_name" "$_old_repo"
    git -C "$_new_repo" fetch "$_remote_name" --quiet

    # 각 feature에 대해 마이그레이션 수행
    for _feature in $_features; do
        _migrate_single_feature "$_old_repo" "$_new_repo" "$_branch_prefix" "$_mastodon_ver" "$_uri_ver" "$_feature" "$_remote_name"
    done

    # remote 정리
    info "임시 remote를 제거합니다..."
    git -C "$_new_repo" remote remove "$_remote_name"

    # apply로 검증
    info "apply로 패치 적용을 검증합니다..."
    _verify_with_apply "$_new_repo" "$_mastodon_ver" "$_uri_ver"

    success "마이그레이션 완료!"
    success "  패치 세트 위치: ${URI_ROOT}/versions/${_mastodon_ver}/patches/${_uri_ver}"
    success "  총 ${_feature_count:-0}개의 feature가 마이그레이션되었습니다."
}

# 접두사로 시작하는 브랜치 찾기 (내부 함수)
# 반환: feature 이름들 (공백 구분)
_find_branches_by_prefix() {
    _repo="$1"
    _prefix="$2"

    # 브랜치 목록에서 접두사로 시작하는 것만 필터링
    # 예: v4.3.2/uri1/custom_emoji -> custom_emoji
    _branches=$(git -C "$_repo" branch --list "${_prefix}/*" --format='%(refname:short)')

    _result=""
    for _branch in $_branches; do
        # 접두사와 슬래시 제거하여 feature 이름 추출
        _feature=$(echo "$_branch" | sed "s|^${_prefix}/||")
        if [ -n "$_feature" ]; then
            _result="$_result $_feature"
        fi
    done

    echo "$_result" | sed 's/^ *//'
}

# 패치 세트 초기화 (내부 함수)
_init_migrate_patchset() {
    _repo="$1"
    _mastodon_ver="$2"
    _uri_ver="$3"

    # 패치 세트는 현재 작업 디렉터리에 생성
    # (두 리포지토리 디렉터리 중 어느 것에도 포함되지 않은 별도의 위치)
    _patches_dir="$PWD"

    # URI_ROOT 설정
    URI_ROOT="$_patches_dir"
    export URI_ROOT

    if [ ! -f "${_patches_dir}/manifest.yaml" ]; then
        info "패치 세트를 초기화합니다..."
        # 루트 manifest 생성 (yaml.sh 함수 재사용)
        yaml_create_empty "${_patches_dir}/manifest.yaml"
        yq -i '. head_comment="Uri Reconstruction Instrument 패치 세트\n마이그레이션으로 생성됨"' "${_patches_dir}/manifest.yaml"
        yaml_set "${_patches_dir}/manifest.yaml" ".upstream" "https://github.com/mastodon/mastodon.git"

        # versions 디렉터리 생성
        mkdir -p "${_patches_dir}/versions"
    fi

    # Mastodon 버전 디렉터리 생성
    _ver_dir="${_patches_dir}/versions/${_mastodon_ver}"
    if [ ! -d "$_ver_dir" ]; then
        mkdir -p "${_ver_dir}/patches"
    fi

    # uri 버전 디렉터리 생성
    _uri_dir="${_ver_dir}/patches/${_uri_ver}"
    _manifest="${_uri_dir}/manifest.yaml"
    if [ ! -d "$_uri_dir" ]; then
        mkdir -p "$_uri_dir"
        # uri 버전 manifest 생성 (yaml.sh 함수 재사용)
        yaml_create_empty "$_manifest"
        # 주석 및 features 섹션 추가
        yq -i '. head_comment="uri 버전: '"${_mastodon_ver}+${_uri_ver}"'\n마이그레이션으로 생성됨"' "$_manifest"
        yaml_set_raw "$_manifest" ".features" "{}"
        info "uri 버전 ${_uri_ver} 를 생성했습니다."
    fi
}

# 단일 feature 마이그레이션 (내부 함수)
_migrate_single_feature() {
    _old_repo="$1"
    _new_repo="$2"
    _branch_prefix="$3"
    _mastodon_ver="$4"
    _uri_ver="$5"
    _feature="$6"
    _remote_name="$7"

    info "feature '$_feature' 마이그레이션 중..."

    _old_branch="${_branch_prefix}/${_feature}"

    # 1. feature 추가 (manifest에 등록 + 빈 패치 파일)
    _add_migrate_feature "$_mastodon_ver" "$_uri_ver" "$_feature"

    # 2. 새 리포지토리에서 태그로 체크아웃하고 브랜치 생성
    # feature 카운터 초기화 (set -u 호환)
    : "${_feature_count:=0}"

    info "  태그 ${_mastodon_ver}에서 브랜치 생성..."
    git_checkout_tag "$_new_repo" "$_mastodon_ver"

    _new_branch=$(uri_branch_name "$_mastodon_ver" "$_uri_ver" "$_feature")
    # git.sh의 git_create_branch 재사용
    git_create_branch "$_new_repo" "$_new_branch"

    # 3. 기존 브랜치의 커밋 목록 가져오기 (태그 이후)
    _commits=$(git -C "$_old_repo" log "${_mastodon_ver}..${_old_branch}" --reverse --format='%H')

    if [ -z "$_commits" ]; then
        warn "  '$_old_branch' 브랜치에 태그 이후 커밋이 없습니다."
    else
        # 4. cherry-pick (git.sh의 git_commit_count 재사용)
        _commit_count=$(git_commit_count "$_old_repo" "${_mastodon_ver}..${_old_branch}")
        info "  ${_commit_count}개 커밋을 cherry-pick합니다..."

        for _commit in $_commits; do
            GIT_COMMITTER_NAME="$URI_GIT_NAME" GIT_COMMITTER_EMAIL="$URI_GIT_EMAIL" \
            git -C "$_new_repo" cherry-pick --no-gpg-sign "$_commit" >/dev/null 2>&1 || \
                die "cherry-pick 실패 (commit: $_commit). 충돌이 발생했습니다."
        done
    fi

    # 5. collapse로 패치 파일 생성
    info "  패치 파일 생성 중..."
    _collapse_migrate_feature "$_new_repo" "$_mastodon_ver" "$_uri_ver" "$_feature"

    _feature_count=$((_feature_count + 1))
}

# feature 추가 (마이그레이션용 - 내부 함수)
# yaml.sh의 함수들을 재사용
_add_migrate_feature() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _feature="$3"

    _uri_dir=$(uri_version_dir "$_mastodon_ver" "$_uri_ver")
    _manifest="${_uri_dir}/manifest.yaml"
    _patch_file="${_uri_dir}/${_feature}.patch"

    # manifest에 feature 추가 (yaml.sh의 yaml_has 및 yaml_set_raw 재사용)
    if ! yaml_has "$_manifest" ".features.$_feature"; then
        yaml_set_raw "$_manifest" ".features.$_feature" "{}"
    fi

    # 빈 패치 파일 생성 (collapse에서 덮어씀)
    if [ ! -f "$_patch_file" ]; then
        touch "$_patch_file"
    fi
}

# feature collapse (마이그레이션용 - 내부 함수)
_collapse_migrate_feature() {
    _repo="$1"
    _mastodon_ver="$2"
    _uri_ver="$3"
    _feature="$4"

    _uri_dir=$(uri_version_dir "$_mastodon_ver" "$_uri_ver")
    _patch_file="${_uri_dir}/${_feature}.patch"
    _branch=$(uri_branch_name "$_mastodon_ver" "$_uri_ver" "$_feature")

    # 태그와 브랜치 사이의 커밋을 패치로 추출
    # git.sh의 git_format_patch 함수 재사용
    if git_branch_exists "$_repo" "$_branch"; then
        git_format_patch "$_repo" "${_mastodon_ver}..${_branch}" "$_patch_file"

        # 태그로 체크아웃하고 브랜치 삭제
        git_checkout_tag "$_repo" "$_mastodon_ver"
        git_delete_branch "$_repo" "$_branch"
    fi
}

# apply로 검증 (내부 함수)
_verify_with_apply() {
    _repo="$1"
    _mastodon_ver="$2"
    _uri_ver="$3"

    # 워킹 트리 깨끗한지 확인
    git_ensure_clean "$_repo"

    # 태그로 체크아웃
    git_checkout_tag "$_repo" "$_mastodon_ver"

    # 상속 해석하여 병합된 manifest 생성
    _merged=$(resolve_inheritance "$_mastodon_ver" "$_uri_ver")

    # 모든 feature 목록
    _all_features=$(get_sorted_features "$_merged")

    if [ -z "$_all_features" ]; then
        info "적용할 feature가 없습니다."
        return 0
    fi

    info "검증할 feature 목록:"
    for _f in $_all_features; do
        echo "  - $_f"
    done

    # 버전 브랜치 이름
    _version_branch=$(uri_version_branch_name "$_mastodon_ver" "$_uri_ver")

    # 브랜치가 이미 있으면 삭제
    if git_branch_exists "$_repo" "$_version_branch"; then
        git_delete_branch "$_repo" "$_version_branch"
    fi

    # 새 브랜치 생성
    git_create_branch "$_repo" "$_version_branch"

    # 각 feature 패치 적용
    for _feature in $_all_features; do
        info "  검증 중: $_feature"
        _patch_file=$(find_patch_file "$_mastodon_ver" "$_uri_ver" "$_feature")

        if [ -z "$_patch_file" ] || [ ! -f "$_patch_file" ]; then
            warn "  패치 파일을 찾을 수 없습니다: $_feature"
            continue
        fi

        # 빈 패치 파일 스킵
        if [ ! -s "$_patch_file" ]; then
            continue
        fi

        if ! git_am "$_repo" "$_patch_file"; then
            git_am_abort "$_repo" 2>/dev/null
            die "패치 적용 실패: $_feature"
        fi
    done

    success "모든 패치가 성공적으로 적용되었습니다."
    info "검증 브랜치: $_version_branch"
}
