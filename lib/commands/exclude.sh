#!/bin/sh
# exclude.sh - exclude/include 명령 구현
# POSIX 호환 셸 스크립트

exclude_usage() {
    cat <<EOF
사용법: uri exclude <mastodon_version> <uri_version> <feature>

현재 uri 버전이 상속한 feature를 제외합니다.

인자:
  mastodon_version   Mastodon 버전 (예: v4.3.2)
  uri_version        uri 버전 (예: uri1.23)
  feature            제외할 상속 feature 이름

옵션:
  -h, --help         이 도움말을 출력합니다
EOF
}

include_usage() {
    cat <<EOF
사용법: uri include <mastodon_version> <uri_version> <feature>

현재 uri 버전이 직접 제외한 feature를 다시 포함합니다.

인자:
  mastodon_version   Mastodon 버전 (예: v4.3.2)
  uri_version        uri 버전 (예: uri1.23)
  feature            다시 포함할 feature 이름

옵션:
  -h, --help         이 도움말을 출력합니다
EOF
}

cmd_exclude() {
    require_uri_root

    _ce_mastodon_ver=""
    _ce_uri_ver=""
    _ce_feature=""

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                exclude_usage
                exit 0
                ;;
            -*)
                die "알 수 없는 옵션: $1"
                ;;
            *)
                if [ -z "$_ce_mastodon_ver" ]; then
                    _ce_mastodon_ver="$1"
                elif [ -z "$_ce_uri_ver" ]; then
                    _ce_uri_ver="$1"
                elif [ -z "$_ce_feature" ]; then
                    _ce_feature="$1"
                else
                    die "인자가 너무 많습니다: $1"
                fi
                ;;
        esac
        shift
    done

    if [ -z "$_ce_mastodon_ver" ] || [ -z "$_ce_uri_ver" ] || [ -z "$_ce_feature" ]; then
        die "mastodon_version, uri_version, feature가 모두 필요합니다. 'uri exclude --help'를 참조하세요."
    fi

    _ce_manifest=$(resolve_manifest_path "$_ce_mastodon_ver" "$_ce_uri_ver")
    require_file "$_ce_manifest" "manifest를 찾을 수 없습니다: $_ce_manifest"
    yaml_validate_excludes "$_ce_manifest"

    if yaml_has "$_ce_manifest" ".features.$_ce_feature"; then
        die "현재 manifest가 직접 선언한 feature는 제외할 수 없습니다. 'uri remove'를 사용하세요: $_ce_feature"
    fi
    if yaml_excludes_feature "$_ce_manifest" "$_ce_feature"; then
        die "feature가 이미 제외되어 있습니다: $_ce_feature"
    fi

    _ce_resolved=$(resolve_inheritance "$_ce_mastodon_ver" "$_ce_uri_ver")
    if ! yaml_has "$_ce_resolved" ".features.$_ce_feature"; then
        die "활성화된 상속 feature를 찾을 수 없습니다: $_ce_feature"
    fi

    _tmp=""
    make_temp >/dev/null
    _ce_candidate="$_tmp"
    cp "$_ce_manifest" "$_ce_candidate"
    yaml_append_exclude "$_ce_candidate" "$_ce_feature"
    resolve_inheritance_with_manifest "$_ce_mastodon_ver" "$_ce_uri_ver" "$_ce_candidate" >/dev/null

    yaml_append_exclude "$_ce_manifest" "$_ce_feature"
    success "feature 제외 완료: $_ce_feature"
}

cmd_include() {
    require_uri_root

    _ci_mastodon_ver=""
    _ci_uri_ver=""
    _ci_feature=""

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                include_usage
                exit 0
                ;;
            -*)
                die "알 수 없는 옵션: $1"
                ;;
            *)
                if [ -z "$_ci_mastodon_ver" ]; then
                    _ci_mastodon_ver="$1"
                elif [ -z "$_ci_uri_ver" ]; then
                    _ci_uri_ver="$1"
                elif [ -z "$_ci_feature" ]; then
                    _ci_feature="$1"
                else
                    die "인자가 너무 많습니다: $1"
                fi
                ;;
        esac
        shift
    done

    if [ -z "$_ci_mastodon_ver" ] || [ -z "$_ci_uri_ver" ] || [ -z "$_ci_feature" ]; then
        die "mastodon_version, uri_version, feature가 모두 필요합니다. 'uri include --help'를 참조하세요."
    fi

    _ci_manifest=$(resolve_manifest_path "$_ci_mastodon_ver" "$_ci_uri_ver")
    require_file "$_ci_manifest" "manifest를 찾을 수 없습니다: $_ci_manifest"
    yaml_validate_excludes "$_ci_manifest"

    if ! yaml_excludes_feature "$_ci_manifest" "$_ci_feature"; then
        die "현재 manifest에서 제외된 feature가 아닙니다: $_ci_feature"
    fi

    _tmp=""
    make_temp >/dev/null
    _ci_candidate="$_tmp"
    cp "$_ci_manifest" "$_ci_candidate"
    yaml_remove_exclude "$_ci_candidate" "$_ci_feature"
    resolve_inheritance_with_manifest "$_ci_mastodon_ver" "$_ci_uri_ver" "$_ci_candidate" >/dev/null

    yaml_remove_exclude "$_ci_manifest" "$_ci_feature"
    success "feature 포함 완료: $_ci_feature"
}
