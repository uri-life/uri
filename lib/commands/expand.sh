#!/bin/sh
# expand.sh - expand 명령 구현
# POSIX 호환 셸 스크립트

# expand 명령 사용법 출력
expand_usage() {
    cat <<EOF
사용법: uri expand <mastodon_version> <uri_version> <feature> <destination> [옵션]
       uri expand <destination> --continue
       uri expand <destination> --abort

feature를 Mastodon 소스에 적용합니다.

인자:
  mastodon_version   Mastodon 버전 (예: v4.3.2)
  uri_version        uri 버전 (예: uri1.23)
  feature            feature 이름 (예: custom_emoji)
  destination        Mastodon Git 리포지토리 경로

옵션:
  -h, --help         이 도움말을 출력합니다
  --continue         충돌 해결 후 계속 진행
  --abort            진행 중인 작업 중단 및 원복

예시:
  uri expand v4.3.2 uri1.23 custom_emoji /path/to/mastodon
  uri expand /path/to/mastodon --continue
  uri expand /path/to/mastodon --abort
EOF
}

# expand 명령 메인 함수
cmd_expand() {
    _mastodon_ver=""
    _uri_ver=""
    _feature=""
    _destination=""
    _continue=false
    _abort=false

    # 옵션 파싱
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                expand_usage
                exit 0
                ;;
            --continue)
                _continue=true
                ;;
            --abort)
                _abort=true
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
                elif [ -z "$_destination" ]; then
                    _destination="$1"
                else
                    die "인자가 너무 많습니다: $1"
                fi
                ;;
        esac
        shift
    done

    # destination 필수 확인
    if [ -z "$_destination" ]; then
        die "destination이 필요합니다. 'uri expand --help'를 참조하세요."
    fi

    _destination=$(resolve_path "$_destination")

    # Git 리포지토리 확인
    git_require_repo "$_destination"

    # --continue 처리
    if [ "$_continue" = true ]; then
        _expand_continue "$_destination"
        return
    fi

    # --abort 처리
    if [ "$_abort" = true ]; then
        _expand_abort "$_destination"
        return
    fi

    # 일반 expand 실행
    require_uri_root

    # 필수 인자 확인
    if [ -z "$_mastodon_ver" ] || [ -z "$_uri_ver" ] || [ -z "$_feature" ]; then
        die "mastodon_version, uri_version, feature가 모두 필요합니다. 'uri expand --help'를 참조하세요."
    fi

    # 진행 중인 작업 확인
    if state_in_progress "$_destination"; then
        state_show "$_destination"
        die "진행 중인 작업이 있습니다."
    fi

    # 워킹 트리 깨끗한지 확인
    git_ensure_clean "$_destination"

    _expand_feature "$_mastodon_ver" "$_uri_ver" "$_feature" "$_destination"
}

# feature 확장 메인 로직 (내부 함수)
_expand_feature() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _feature="$3"
    _dest="$4"

    # manifest 확인
    _manifest=$(resolve_manifest_path "$_mastodon_ver" "$_uri_ver")
    require_file "$_manifest" "manifest를 찾을 수 없습니다: $_manifest"

    # 상속 해석하여 병합된 manifest 생성
    _merged=$(resolve_inheritance "$_mastodon_ver" "$_uri_ver")

    # feature 존재 확인
    if ! yaml_has "$_merged" ".features.$_feature"; then
        die "feature를 찾을 수 없습니다: $_feature"
    fi

    # 의존성 포함하여 정렬된 feature 목록 생성
    _sorted_features=$(get_feature_with_deps "$_merged" "$_feature")

    if [ -z "$_sorted_features" ]; then
        die "feature 정렬 실패"
    fi

    info "적용할 feature 목록 (의존성 순서):"
    for _f in $_sorted_features; do
        echo "  - $_f"
    done

    # 브랜치 존재 여부 확인 (이미 expand된 상태인지)
    for _f in $_sorted_features; do
        _branch=$(uri_branch_name "$_mastodon_ver" "$_uri_ver" "$_f")
        if git_branch_exists "$_dest" "$_branch"; then
            die "브랜치 '$_branch'가 이미 존재합니다. 이전 expand 작업이 collapse되지 않았습니다."
        fi
    done

    # Mastodon 태그로 체크아웃 (detached HEAD)
    git_checkout_tag "$_dest" "$_mastodon_ver"

    # feature 목록을 공백 구분 문자열로 변환
    _features_str=""
    for _f in $_sorted_features; do
        _features_str="$_features_str $_f"
    done
    _features_str=$(echo "$_features_str" | sed 's/^ *//')

    # 상태 저장
    state_save_expand "$_dest" "$_mastodon_ver" "$_uri_ver" "$_features_str" "0"

    # 순서대로 적용
    _apply_features "$_dest" "$_mastodon_ver" "$_uri_ver" "$_features_str" "0"
}

# feature들을 순서대로 적용 (내부 함수)
_apply_features() {
    _dest="$1"
    _mastodon_ver="$2"
    _uri_ver="$3"
    _features_str="$4"
    _start_index="$5"

    _index=0
    _prev_branch=""

    for _feature in $_features_str; do
        # 시작 인덱스 이전은 스킵
        if [ "$_index" -lt "$_start_index" ]; then
            # 이전 브랜치 기록
            _prev_branch=$(uri_branch_name "$_mastodon_ver" "$_uri_ver" "$_feature")
            _index=$((_index + 1))
            continue
        fi

        info "[$_index] feature '$_feature' 적용 중..."

        # 현재 인덱스 저장
        state_save "$_dest" "current_index" "$_index"
        state_save "$_dest" "current_feature" "$_feature"

        # 패치 파일 찾기
        _patch_file=$(find_patch_file "$_mastodon_ver" "$_uri_ver" "$_feature")

        if [ -z "$_patch_file" ] || [ ! -f "$_patch_file" ]; then
            warn "패치 파일을 찾을 수 없습니다: $_feature (건너뜁니다)"
            _index=$((_index + 1))
            continue
        fi

        # 패치가 비어있으면 브랜치만 생성
        if [ ! -s "$_patch_file" ]; then
            warn "패치 파일이 비어있습니다: $_feature (빈 브랜치 생성)"
            _branch=$(uri_branch_name "$_mastodon_ver" "$_uri_ver" "$_feature")
            if git_branch_exists "$_dest" "$_branch"; then
                git_delete_branch "$_dest" "$_branch"
            fi
            git_create_branch_at "$_dest" "$_branch"
            _last_branch="$_branch"
            _index=$((_index + 1))
            continue
        fi

        # 패치 적용
        if ! git_am "$_dest" "$_patch_file"; then
            # 충돌 발생
            warn "충돌이 발생했습니다!"
            echo ""
            echo "충돌을 해결한 후:"
            echo "  1. 충돌 파일을 수정하세요"
            echo "  2. git add <파일> 로 스테이징하세요"
            echo "  3. 'uri expand --continue -d $_dest' 로 계속하세요"
            echo ""
            echo "작업을 중단하려면: 'uri expand --abort -d $_dest'"
            exit 1
        fi

        # 브랜치 생성 (현재 HEAD 위치에, 체크아웃 없이)
        _branch=$(uri_branch_name "$_mastodon_ver" "$_uri_ver" "$_feature")
        if git_branch_exists "$_dest" "$_branch"; then
            git_delete_branch "$_dest" "$_branch"
        fi
        git_create_branch_at "$_dest" "$_branch"

        success "feature '$_feature' 적용 완료"

        _last_branch="$_branch"
        _index=$((_index + 1))
    done

    # 마지막 feature 브랜치로 체크아웃
    if [ -n "$_last_branch" ]; then
        git_checkout_branch "$_dest" "$_last_branch"
    fi

    # 완료 - 상태 정리
    state_clear "$_dest"
    success "모든 feature 적용 완료!"
}

# --continue 처리 (내부 함수)
_expand_continue() {
    _dest="$1"

    # 상태 확인
    if ! state_in_progress "$_dest"; then
        die "진행 중인 작업이 없습니다."
    fi

    _operation=$(state_get "$_dest" "operation")
    if [ "$_operation" != "expand" ]; then
        die "expand 작업이 아닙니다. 현재 작업: $_operation"
    fi

    require_uri_root

    # git am이 진행 중이면 continue
    if git_am_in_progress "$_dest"; then
        info "git am을 계속합니다..."
        if ! git_am_continue "$_dest"; then
            die "git am --continue 실패. 충돌을 먼저 해결하세요."
        fi
    fi

    # 현재 feature 브랜치 생성
    _mastodon_ver=$(state_get "$_dest" "mastodon_version")
    _uri_ver=$(state_get "$_dest" "uri_version")
    _current_feature=$(state_get "$_dest" "current_feature")

    _branch=$(uri_branch_name "$_mastodon_ver" "$_uri_ver" "$_current_feature")
    if git_branch_exists "$_dest" "$_branch"; then
        git_delete_branch "$_dest" "$_branch"
    fi
    git_create_branch_at "$_dest" "$_branch"

    success "feature '$_current_feature' 적용 완료"

    # 다음 feature로 진행
    _features_str=$(state_get "$_dest" "features")
    _current_index=$(state_get "$_dest" "current_index")
    _next_index=$((_current_index + 1))

    # 남은 feature 적용
    _apply_features "$_dest" "$_mastodon_ver" "$_uri_ver" "$_features_str" "$_next_index"
}

# --abort 처리 (내부 함수)
_expand_abort() {
    _dest="$1"

    # 상태 확인
    if ! state_in_progress "$_dest"; then
        die "진행 중인 작업이 없습니다."
    fi

    _operation=$(state_get "$_dest" "operation")
    if [ "$_operation" != "expand" ]; then
        die "expand 작업이 아닙니다. 현재 작업: $_operation"
    fi

    info "expand 작업을 중단합니다..."

    # git am 중이면 abort
    if git_am_in_progress "$_dest"; then
        git_am_abort "$_dest"
    fi

    # 시작 커밋으로 복귀
    _start_commit=$(state_get "$_dest" "start_commit")
    if [ -n "$_start_commit" ]; then
        git -C "$_dest" reset --hard "$_start_commit" >/dev/null 2>&1
    fi

    # 상태 정리
    state_clear "$_dest"

    success "expand 작업이 중단되었습니다."
}
