#!/bin/sh
# collapse.sh - collapse 명령 구현
# POSIX 호환 셸 스크립트

# collapse 명령 사용법 출력
collapse_usage() {
    cat <<EOF
사용법: uri collapse <mastodon_version> <uri_version> <feature> <source> [옵션]

Mastodon 소스에서 지정한 feature를 패치 파일로 추출합니다.
기본 모드는 의존 feature를 각자의 선언된 의존성 위에서 재구성해 변경 여부를 검증합니다.
추출 후 태그 위치로 체크아웃하고 관련 브랜치를 삭제합니다.

인자:
  mastodon_version   Mastodon 버전 (예: v4.3.2)
  uri_version        uri 버전 (예: uri1.23)
  feature            feature 이름 (예: custom_emoji)
  source             Mastodon Git 리포지토리 경로

옵션:
  --recursive        지정 feature와 모든 재귀 의존 feature의 패치를 함께 갱신합니다
  -h, --help         이 도움말을 출력합니다

예시:
  uri collapse v4.3.2 uri1.23 custom_emoji /path/to/mastodon
  uri collapse v4.3.2 uri1.23 custom_emoji /path/to/mastodon --recursive
EOF
}

# collapse 명령 메인 함수
cmd_collapse() {
    require_uri_root

    _mastodon_ver=""
    _uri_ver=""
    _feature=""
    _source=""
    _recursive=false

    # 옵션 파싱
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                collapse_usage
                exit 0
                ;;
            --recursive)
                _recursive=true
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

    _collapse_features "$_mastodon_ver" "$_uri_ver" "$_feature" "$_source" "$_recursive"
}

# 모든 후보를 임시 clone에서 준비한 뒤 검증과 저장을 분리합니다.
_collapse_features() {
    _cf_mastodon_ver="$1"
    _cf_uri_ver="$2"
    _cf_target="$3"
    _cf_source="$4"
    _cf_recursive="$5"

    _cf_uri_dir=$(uri_version_dir "$_cf_mastodon_ver" "$_cf_uri_ver")
    require_dir "$_cf_uri_dir" "uri 버전 디렉터리를 찾을 수 없습니다: $_cf_uri_dir"
    _cf_manifest=$(resolve_manifest_path "$_cf_mastodon_ver" "$_cf_uri_ver")
    require_file "$_cf_manifest" "manifest를 찾을 수 없습니다: $_cf_manifest"
    _cf_merged=$(resolve_inheritance "$_cf_mastodon_ver" "$_cf_uri_ver")

    if ! yaml_has "$_cf_merged" ".features.$_cf_target"; then
        die "feature를 찾을 수 없습니다: $_cf_target"
    fi
    _cf_features=$(get_feature_with_deps_with_dev "$_cf_merged" "$_cf_target")
    [ -n "$_cf_features" ] || die "feature 정렬 실패"

    info "collapse할 feature 목록 (의존성 순서):"
    for _cf_list_feature in $_cf_features; do
        echo "  - $_cf_list_feature"
    done

    _made_temp_dir=""
    make_temp_dir
    _cf_temp_root="$_made_temp_dir"
    _cf_clone="${_cf_temp_root}/source"
    _cf_candidates="${_cf_temp_root}/patches"
    mkdir -p "$_cf_candidates"

    info "임시 Git clone에서 패치 후보를 재구성합니다..."
    if ! git clone --quiet --shared --no-checkout "$_cf_source" "$_cf_clone"; then
        _cleanup_temp_dir "$_cf_temp_root"
        die "collapse 임시 clone 생성에 실패했습니다."
    fi
    git -C "$_cf_clone" config user.name "$URI_GIT_NAME"
    git -C "$_cf_clone" config user.email "$URI_GIT_EMAIL"
    git -C "$_cf_clone" config commit.gpgSign false

    if ! _prepare_collapse_candidates \
        "$_cf_mastodon_ver" "$_cf_uri_ver" "$_cf_merged" "$_cf_features" \
        "$_cf_clone" "$_cf_candidates"; then
        warn "collapse를 중단합니다. 패치와 원본 브랜치는 변경되지 않았습니다."
        _cleanup_temp_dir "$_cf_temp_root"
        return 1
    fi

    if [ "$_cf_recursive" = true ]; then
        _cf_to_save=$(echo "$_cf_features" | reverse_lines)
    else
        if ! _dependency_candidates_match \
            "$_cf_mastodon_ver" "$_cf_uri_ver" "$_cf_target" \
            "$_cf_features" "$_cf_candidates"; then
            _cleanup_temp_dir "$_cf_temp_root"
            return 1
        fi
        _cf_to_save="$_cf_target"
    fi

    _cf_saved=0
    _cf_skipped=0
    for _cf_save_feature in $_cf_to_save; do
        _cf_result=0
        _persist_collapse_candidate \
            "$_cf_mastodon_ver" "$_cf_uri_ver" "$_cf_save_feature" \
            "$_cf_candidates" || _cf_result=$?
        case $_cf_result in
            0) _cf_saved=$((_cf_saved + 1)) ;;
            1) _cf_skipped=$((_cf_skipped + 1)) ;;
            *) ;;
        esac
    done

    _cleanup_collapsed_branches \
        "$_cf_mastodon_ver" "$_cf_uri_ver" "$_cf_features" "$_cf_source"
    _cleanup_temp_dir "$_cf_temp_root"

    info "결과: ${_cf_saved}개 저장됨, ${_cf_skipped}개 건너뜀 (상속과 동일)"
    success "collapse 완료!"
}

# 각 feature의 고유 커밋만 선언된 의존성 위로 rebase해 후보 패치를 만듭니다.
_prepare_collapse_candidates() {
    _pc_mastodon_ver="$1"
    _pc_uri_ver="$2"
    _pc_merged="$3"
    _pc_features="$4"
    _pc_clone="$5"
    _pc_candidates="$6"
    _pc_previous=""
    _pc_index=0

    if ! git -C "$_pc_clone" rev-parse --verify --quiet "refs/tags/${_pc_mastodon_ver}^{}" >/dev/null; then
        warn "Mastodon 버전 태그를 찾을 수 없습니다: $_pc_mastodon_ver"
        return 1
    fi

    for _pc_feature in $_pc_features; do
        _pc_branch_name=$(uri_branch_name "$_pc_mastodon_ver" "$_pc_uri_ver" "$_pc_feature")
        _pc_source_ref="refs/remotes/origin/${_pc_branch_name}"
        if ! git -C "$_pc_clone" rev-parse --verify --quiet "${_pc_source_ref}^{commit}" >/dev/null; then
            warn "feature 브랜치를 찾을 수 없습니다: $_pc_branch_name"
            return 1
        fi
        if ! git -C "$_pc_clone" merge-base --is-ancestor "$_pc_mastodon_ver" "$_pc_source_ref"; then
            warn "feature 브랜치가 버전 태그에서 파생되지 않았습니다: $_pc_feature"
            return 1
        fi

        if [ -z "$_pc_previous" ]; then
            _pc_original_base="$_pc_mastodon_ver"
        else
            _pc_previous_ref="refs/remotes/origin/$(uri_branch_name "$_pc_mastodon_ver" "$_pc_uri_ver" "$_pc_previous")"
            _pc_original_base=$(git -C "$_pc_clone" merge-base "$_pc_previous_ref" "$_pc_source_ref") || {
                warn "feature 경계의 merge-base를 결정할 수 없습니다: $_pc_feature"
                return 1
            }
        fi

        if ! git -C "$_pc_clone" checkout --detach --force "$_pc_mastodon_ver" >/dev/null 2>&1; then
            warn "버전 태그를 임시 clone에서 체크아웃할 수 없습니다."
            return 1
        fi

        _pc_required=$(get_feature_with_deps_with_dev "$_pc_merged" "$_pc_feature")
        for _pc_dependency in $_pc_required; do
            [ "$_pc_dependency" = "$_pc_feature" ] && continue
            _pc_dependency_patch="${_pc_candidates}/${_pc_dependency}.patch"
            if [ ! -f "$_pc_dependency_patch" ]; then
                warn "의존 feature 패치 후보를 찾을 수 없습니다: $_pc_dependency"
                return 1
            fi
            if [ -s "$_pc_dependency_patch" ] && ! git_am "$_pc_clone" "$_pc_dependency_patch" >/dev/null; then
                git_am_abort "$_pc_clone" || true
                warn "[$_pc_feature] 의존 feature '$_pc_dependency' 적용에 실패했습니다."
                return 1
            fi
        done
        _pc_dependency_base=$(git -C "$_pc_clone" rev-parse HEAD)

        _pc_candidate="${_pc_candidates}/${_pc_feature}.patch"
        _pc_commit_count=$(git_commit_count "$_pc_clone" "${_pc_original_base}..${_pc_source_ref}")
        if [ "$_pc_commit_count" -eq 0 ]; then
            : > "$_pc_candidate"
        else
            _pc_temp_branch="uri-collapse-candidate-${_pc_index}"
            if ! git -C "$_pc_clone" checkout -B "$_pc_temp_branch" "$_pc_source_ref" >/dev/null 2>&1; then
                warn "[$_pc_feature] 임시 브랜치 생성에 실패했습니다."
                return 1
            fi
            if ! GIT_COMMITTER_NAME="$URI_GIT_NAME" GIT_COMMITTER_EMAIL="$URI_GIT_EMAIL" \
                git -C "$_pc_clone" rebase --onto "$_pc_dependency_base" "$_pc_original_base" "$_pc_temp_branch" >/dev/null 2>&1; then
                git -C "$_pc_clone" rebase --abort >/dev/null 2>&1 || true
                warn "[$_pc_feature] 선언된 의존성 위로 rebase하지 못했습니다."
                return 1
            fi
            git_format_patch "$_pc_clone" "${_pc_dependency_base}..${_pc_temp_branch}" "$_pc_candidate"
            [ -s "$_pc_candidate" ] || {
                warn "[$_pc_feature] 패치 후보가 비어있습니다."
                return 1
            }
        fi

        _pc_previous="$_pc_feature"
        _pc_index=$((_pc_index + 1))
    done
}

# 비재귀 모드에서 의존 feature 후보가 현재 유효 패치와 동일한지 확인합니다.
_dependency_candidates_match() {
    _dm_mastodon_ver="$1"
    _dm_uri_ver="$2"
    _dm_target="$3"
    _dm_features="$4"
    _dm_candidates="$5"
    _dm_changed=""

    for _dm_feature in $_dm_features; do
        [ "$_dm_feature" = "$_dm_target" ] && continue
        _dm_candidate="${_dm_candidates}/${_dm_feature}.patch"
        _dm_existing=$(find_patch_file "$_dm_mastodon_ver" "$_dm_uri_ver" "$_dm_feature" 2>/dev/null || true)
        if [ -z "$_dm_existing" ] || [ ! -f "$_dm_existing" ] || \
            ! _patches_are_equal "$_dm_candidate" "$_dm_existing"; then
            _dm_changed="$_dm_changed $_dm_feature"
        fi
    done

    if [ -n "$_dm_changed" ]; then
        warn "--recursive 옵션 없이 의존 feature 패치 변경이 감지되었습니다:"
        for _dm_changed_feature in $_dm_changed; do
            echo "  - $_dm_changed_feature" >&2
        done
        warn "collapse를 중단했습니다. 어떤 패치나 원본 브랜치도 변경되지 않았습니다."
        warn "의존 feature도 갱신하려면 '--recursive'를 사용하세요."
        return 1
    fi
}

# 반환값: 0=저장, 1=상속과 동일, 2=빈 패치
_persist_collapse_candidate() {
    _ps_mastodon_ver="$1"
    _ps_uri_ver="$2"
    _ps_feature="$3"
    _ps_candidates="$4"
    _ps_candidate="${_ps_candidates}/${_ps_feature}.patch"

    if [ ! -s "$_ps_candidate" ]; then
        warn "[$_ps_feature] 추출할 커밋이 없습니다."
        return 2
    fi

    _ps_inherited=$(_find_inherited_patch "$_ps_mastodon_ver" "$_ps_uri_ver" "$_ps_feature")
    if [ -n "$_ps_inherited" ] && [ -f "$_ps_inherited" ] && \
        _patches_are_equal "$_ps_candidate" "$_ps_inherited"; then
        info "[$_ps_feature] 상속된 패치와 동일합니다. 건너뜁니다."
        return 1
    fi

    _ps_patch_file="$(uri_version_dir "$_ps_mastodon_ver" "$_ps_uri_ver")/${_ps_feature}.patch"
    if ! mv "$_ps_candidate" "$_ps_patch_file"; then
        warn "[$_ps_feature] 패치 파일을 저장하지 못했습니다: $_ps_patch_file"
        return 2
    fi
    success "[$_ps_feature] 패치 추출 완료: $_ps_patch_file"
}

_cleanup_collapsed_branches() {
    _cb_mastodon_ver="$1"
    _cb_uri_ver="$2"
    _cb_features="$3"
    _cb_source="$4"

    git_checkout_tag "$_cb_source" "$_cb_mastodon_ver"
    info "브랜치를 정리합니다..."
    _cb_reversed=$(echo "$_cb_features" | reverse_lines)
    for _cb_feature in $_cb_reversed; do
        _cb_branch=$(uri_branch_name "$_cb_mastodon_ver" "$_cb_uri_ver" "$_cb_feature")
        if git_branch_exists "$_cb_source" "$_cb_branch"; then
            git_delete_branch "$_cb_source" "$_cb_branch"
            info "  삭제됨: $_cb_branch"
        fi
    done
}

# 상속 체인에서 부모의 패치 파일 찾기 (현재 버전 제외)
# 사용법: _find_inherited_patch "v4.3.2" "uri1.23" "feature"
_find_inherited_patch() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _feature="$3"

    _current_dir=$(uri_version_dir "$_mastodon_ver" "$_uri_ver")

    # 상속 체인을 따라가며 패치 파일 찾기
    _chain=$(get_inheritance_chain "$_mastodon_ver" "$_uri_ver")

    for _manifest in $_chain; do
        _patch_dir=$(dirname "$_manifest")

        # 현재 버전은 건너뜀
        if [ "$_patch_dir" = "$_current_dir" ]; then
            continue
        fi

        _patch_file="${_patch_dir}/${_feature}.patch"

        if [ -f "$_patch_file" ]; then
            echo "$_patch_file"
            return 0
        fi
    done

    # 상속된 패치가 없으면 빈 문자열 반환 (정상 종료)
    echo ""
    return 0
}

# 두 패치 파일이 동일한지 비교 (메타데이터 제외, 실제 diff 내용만 비교)
# 사용법: if _patches_are_equal "patch1" "patch2"; then ...
_patches_are_equal() {
    _patch1="$1"
    _patch2="$2"

    # 메타데이터 라인을 제외하고 실제 diff 내용만 비교
    # 제외 항목: From (커밋 해시), From: (작성자), Date:, Subject:, index (blob 해시)
    _diff1=$(grep -v -E '^(From[ :]|Date:|Subject:|index )' "$_patch1")
    _diff2=$(grep -v -E '^(From[ :]|Date:|Subject:|index )' "$_patch2")

    [ "$_diff1" = "$_diff2" ]
}
