#!/bin/sh
# remove.sh - remove 명령 구현
# POSIX 호환 셸 스크립트

# remove 명령 사용법 출력
remove_usage() {
    cat <<EOF
사용법: uri remove <mastodon_version> [uri_version] [feature] [옵션]

Mastodon 버전, uri 버전, 또는 feature를 제거합니다.

인자:
  mastodon_version   Mastodon 버전 (예: v4.3.2)
  uri_version        uri 버전 (예: uri1.23)
  feature            feature 이름 (예: custom_emoji)

옵션:
  -h, --help         이 도움말을 출력합니다
  -f, --force        확인 없이 강제 삭제

예시:
  uri remove v4.3.2                           # Mastodon 버전 전체 삭제
  uri remove v4.3.2 uri1.23                   # uri 버전 삭제
  uri remove v4.3.2 uri1.23 custom_emoji      # feature 삭제
EOF
}

# remove 명령 메인 함수
cmd_remove() {
    require_uri_root

    _mastodon_ver=""
    _uri_ver=""
    _feature=""
    _force=false

    # 옵션 파싱
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                remove_usage
                exit 0
                ;;
            -f|--force)
                _force=true
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
                else
                    die "인자가 너무 많습니다: $1"
                fi
                ;;
        esac
        shift
    done

    # 필수 인자 확인
    if [ -z "$_mastodon_ver" ]; then
        die "mastodon_version이 필요합니다. 'uri remove --help'를 참조하세요."
    fi

    # 제거 수준 결정
    if [ -n "$_feature" ]; then
        _remove_feature "$_mastodon_ver" "$_uri_ver" "$_feature" "$_force"
    elif [ -n "$_uri_ver" ]; then
        _remove_uri_version "$_mastodon_ver" "$_uri_ver" "$_force"
    else
        _remove_mastodon_version "$_mastodon_ver" "$_force"
    fi
}

# feature 제거 (내부 함수)
_remove_feature() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _feature="$3"
    _force="$4"

    _uri_dir=$(uri_version_dir "$_mastodon_ver" "$_uri_ver")
    _manifest="${_uri_dir}/manifest.yaml"
    _patch_file="${_uri_dir}/${_feature}.patch"

    # 존재 확인
    if [ ! -f "$_manifest" ]; then
        die "uri 버전을 찾을 수 없습니다: $_uri_dir"
    fi

    if ! yaml_has "$_manifest" ".features.$_feature"; then
        die "feature를 찾을 수 없습니다: $_feature"
    fi

    # 다른 feature가 이 feature에 의존하는지 확인
    _dependents=$(_find_dependents "$_manifest" "$_feature")
    if [ -n "$_dependents" ]; then
        warn "다음 feature들이 $_feature 에 의존합니다:"
        for _dep in $_dependents; do
            echo "  - $_dep"
        done
        if [ "$_force" != true ]; then
            die "의존하는 feature가 있습니다. -f 옵션으로 강제 삭제하세요."
        fi
    fi

    # 확인
    if [ "$_force" != true ]; then
        printf "feature '%s'를 삭제하시겠습니까? [y/N] " "$_feature"
        read -r _confirm
        case "$_confirm" in
            [yY]|[yY][eE][sS]) ;;
            *) die "취소되었습니다." ;;
        esac
    fi

    info "feature $_feature 를 제거합니다..."

    # manifest에서 제거
    yaml_delete "$_manifest" ".features.$_feature"

    # 패치 파일 삭제
    if [ -f "$_patch_file" ]; then
        rm -f "$_patch_file"
    fi

    success "feature 제거 완료: $_feature"
}

# uri 버전 제거 (내부 함수)
_remove_uri_version() {
    _mastodon_ver="$1"
    _uri_ver="$2"
    _force="$3"

    _uri_dir=$(uri_version_dir "$_mastodon_ver" "$_uri_ver")

    if [ ! -d "$_uri_dir" ]; then
        die "uri 버전을 찾을 수 없습니다: $_uri_dir"
    fi

    # 확인
    if [ "$_force" != true ]; then
        printf "uri 버전 '%s'와 모든 feature를 삭제하시겠습니까? [y/N] " "$_uri_ver"
        read -r _confirm
        case "$_confirm" in
            [yY]|[yY][eE][sS]) ;;
            *) die "취소되었습니다." ;;
        esac
    fi

    info "uri 버전 $_uri_ver 를 제거합니다..."

    rm -rf "$_uri_dir"

    success "uri 버전 제거 완료: $_uri_ver"
}

# Mastodon 버전 제거 (내부 함수)
_remove_mastodon_version() {
    _mastodon_ver="$1"
    _force="$2"

    _ver_dir=$(version_dir "$_mastodon_ver")

    if [ ! -d "$_ver_dir" ]; then
        die "Mastodon 버전을 찾을 수 없습니다: $_ver_dir"
    fi

    # 확인
    if [ "$_force" != true ]; then
        printf "Mastodon 버전 '%s'와 모든 uri 버전, feature를 삭제하시겠습니까? [y/N] " "$_mastodon_ver"
        read -r _confirm
        case "$_confirm" in
            [yY]|[yY][eE][sS]) ;;
            *) die "취소되었습니다." ;;
        esac
    fi

    info "Mastodon 버전 $_mastodon_ver 를 제거합니다..."

    rm -rf "$_ver_dir"

    success "Mastodon 버전 제거 완료: $_mastodon_ver"
}

# 특정 feature에 의존하는 다른 feature 찾기 (내부 함수)
_find_dependents() {
    _manifest="$1"
    _target="$2"

    _features=$(yaml_list_features "$_manifest")
    _dependents=""

    for _f in $_features; do
        if [ "$_f" = "$_target" ]; then
            continue
        fi

        _deps=$(yaml_get_feature_dependencies "$_manifest" "$_f" 2>/dev/null)
        for _d in $_deps; do
            if [ "$_d" = "$_target" ]; then
                _dependents="$_dependents $_f"
                break
            fi
        done
    done

    echo "$_dependents" | sed 's/^ *//'
}
