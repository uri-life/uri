#!/bin/sh
# collapse.sh - collapse 명령 구현
# POSIX 호환 셸 스크립트

# collapse 명령 사용법 출력
collapse_usage() {
    cat <<EOF
사용법: uri collapse <mastodon_version> <uri_version> <feature> <source>

Mastodon 소스에서 feature와 그 의존성들을 패치 파일로 추출합니다.
추출 후 태그 위치로 체크아웃하고 관련 브랜치를 삭제합니다.

인자:
  mastodon_version   Mastodon 버전 (예: v4.3.2)
  uri_version        uri 버전 (예: uri1.23)
  feature            feature 이름 (예: custom_emoji)
  source             Mastodon Git 리포지토리 경로

옵션:
  -h, --help         이 도움말을 출력합니다

예시:
  uri collapse v4.3.2 uri1.23 custom_emoji /path/to/mastodon
EOF
}

# collapse 명령 메인 함수
cmd_collapse() {
    require_uri_root

    _mastodon_ver=""
    _uri_ver=""
    _feature=""
    _source=""

    # 옵션 파싱
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                collapse_usage
                exit 0
                ;;
            -*)
                die "알 수 없는 옵션: $1"
                ;;
            *)
                # 위치 인자
                if [ -z "$_mastodon_ver" ]; then
                    _mastodon_ver="$1"
                elif [ -z "$_uri_ver" ]; then
                    _uri_ver="$1"
                elif [ -z "$_feature" ]; then
                    _feature="$1"
                elif [ -z "$_source" ]; then
                    _source="$1"
                else
                    die "인자가 너무 많습니다: $1"
                fi
                ;;
        esac
        shift
    done

    # 필수 인자 확인
    if [ -z "$_mastodon_ver" ] || [ -z "$_uri_ver" ] || [ -z "$_feature" ] || [ -z "$_source" ]; then
        die "mastodon_version, uri_version, feature, source가 모두 필요합니다. 'uri collapse --help'를 참조하세요."
    fi

    _source=$(resolve_path "$_source")

    # Git 리포지토리 확인
    git_require_repo "$_source"

    # 워킹 트리 깨끗한지 확인
    git_ensure_clean "$_source"

    _collapse_all_features "$_mastodon_ver" "$_uri_ver" "$_feature" "$_source"
}

# 모든 feature 추출 메인 로직 (내부 함수)
_collapse_all_features() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _target_feature="$3"
    _src="$4"

    # uri 버전 디렉터리 확인
    _uri_dir=$(uri_version_dir "$_mastodon_ver" "$_uri_ver")
    if [ ! -d "$_uri_dir" ]; then
        die "uri 버전 디렉터리를 찾을 수 없습니다: $_uri_dir"
    fi

    # manifest 확인
    _manifest=$(resolve_manifest_path "$_mastodon_ver" "$_uri_ver")
    require_file "$_manifest" "manifest를 찾을 수 없습니다: $_manifest"

    # 상속 해석하여 병합된 manifest 생성
    _merged=$(resolve_inheritance "$_mastodon_ver" "$_uri_ver")

    # 의존성 포함하여 정렬된 feature 목록 (의존되는 것이 먼저)
    _sorted_features=$(get_feature_with_deps "$_merged" "$_target_feature")

    if [ -z "$_sorted_features" ]; then
        die "feature 목록을 가져올 수 없습니다."
    fi

    info "collapse할 feature 목록 (의존성 순서):"
    for _f in $_sorted_features; do
        echo "  - $_f"
    done

    # 역순으로 처리 (가장 마지막 feature부터 collapse)
    _reversed_features=$(echo "$_sorted_features" | tr ' ' '\n' | reverse_lines | tr '\n' ' ')

    # 삭제할 브랜치 목록
    _branches_to_delete=""

    for _feature in $_reversed_features; do
        _collapse_single_feature "$_mastodon_ver" "$_uri_ver" "$_feature" "$_src" "$_merged"

        # 브랜치 삭제 목록에 추가
        _branch=$(uri_branch_name "$_mastodon_ver" "$_uri_ver" "$_feature")
        _branches_to_delete="$_branches_to_delete $_branch"
    done

    # 태그로 체크아웃
    info "태그 $_mastodon_ver 로 체크아웃합니다..."
    git_checkout_tag "$_src" "$_mastodon_ver"

    # 브랜치 삭제
    info "브랜치를 정리합니다..."
    for _branch in $_branches_to_delete; do
        if git_branch_exists "$_src" "$_branch"; then
            git_delete_branch "$_src" "$_branch"
            info "  삭제됨: $_branch"
        fi
    done

    success "collapse 완료!"
}

# 단일 feature 추출 (내부 함수)
_collapse_single_feature() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _feature="$3"
    _src="$4"
    _merged="$5"

    _uri_dir=$(uri_version_dir "$_mastodon_ver" "$_uri_ver")

    # feature 브랜치 존재 확인
    _feature_branch=$(uri_branch_name "$_mastodon_ver" "$_uri_ver" "$_feature")
    if ! git_branch_exists "$_src" "$_feature_branch"; then
        warn "feature 브랜치를 찾을 수 없습니다: $_feature_branch (건너뜁니다)"
        return
    fi

    # 이전 feature 브랜치 찾기 (의존성 순서에서 바로 앞)
    _prev_branch=$(_find_prev_branch_from_merged "$_merged" "$_mastodon_ver" "$_uri_ver" "$_feature" "$_src")

    if [ -z "$_prev_branch" ]; then
        die "이전 브랜치를 결정할 수 없습니다."
    fi

    info "[$_feature] 패치 추출 중..."
    info "  범위: $_prev_branch..$_feature_branch"

    # 커밋 수 확인
    _commit_count=$(git_commit_count "$_src" "${_prev_branch}..${_feature_branch}")
    if [ "$_commit_count" -eq 0 ]; then
        warn "  추출할 커밋이 없습니다."
        return
    fi

    info "  커밋 수: $_commit_count"

    # 패치 파일 경로
    _patch_file="${_uri_dir}/${_feature}.patch"

    # 패치 추출
    git_format_patch "$_src" "${_prev_branch}..${_feature_branch}" "$_patch_file"

    if [ ! -s "$_patch_file" ]; then
        warn "  패치 파일이 비어있습니다."
        return
    fi

    success "  패치 추출 완료: $_patch_file"
}

# 병합된 manifest를 사용하여 이전 feature 브랜치 찾기 (내부 함수)
_find_prev_branch_from_merged() {
    _merged="$1"
    _mastodon_ver="$2"
    _uri_ver="$3"
    _target_feature="$4"
    _src="$5"

    # 의존성 포함하여 정렬된 feature 목록
    _sorted=$(get_feature_with_deps "$_merged" "$_target_feature")

    # target feature 바로 앞의 feature 찾기
    _prev=""
    for _f in $_sorted; do
        if [ "$_f" = "$_target_feature" ]; then
            break
        fi
        _prev="$_f"
    done

    # 이전 feature가 있으면 그 브랜치
    if [ -n "$_prev" ]; then
        _prev_branch=$(uri_branch_name "$_mastodon_ver" "$_uri_ver" "$_prev")
        if git_branch_exists "$_src" "$_prev_branch"; then
            echo "$_prev_branch"
            return
        fi
    fi

    # 이전 feature가 없으면 태그를 베이스로 사용
    echo "$_mastodon_ver"
}
