#!/bin/sh
# graph.sh - graph 명령 구현
# POSIX 호환 셸 스크립트

# graph 명령 사용법 출력
graph_usage() {
    cat <<EOF
사용법: uri graph <mastodon_version> <uri_version> [옵션]

uri 버전에 포함된 feature 의존성 그래프를 출력합니다.

인자:
  mastodon_version   Mastodon 버전 (예: v4.3.2)
  uri_version        uri 버전 (예: uri1.23)

옵션:
  -h, --help         이 도움말을 출력합니다
  --include-dev      dev-dependencies를 그래프에 포함합니다
  --format FORMAT    출력 형식: tree 또는 dot (기본값: tree)

예시:
  uri graph v4.3.2 uri1.23
  uri graph v4.3.2 uri1.23 --include-dev
  uri graph v4.3.2 uri1.23 --format dot
EOF
}

# graph 명령 메인 함수
cmd_graph() {
    _mastodon_ver=""
    _uri_ver=""
    _include_dev=false
    _format="tree"

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                graph_usage
                exit 0
                ;;
            --include-dev)
                _include_dev=true
                ;;
            --format)
                shift
                if [ $# -eq 0 ]; then
                    die "--format 값이 필요합니다. tree 또는 dot을 지정하세요."
                fi
                _format="$1"
                ;;
            --format=*)
                _format="${1#--format=}"
                ;;
            -*)
                die "알 수 없는 옵션: $1"
                ;;
            *)
                if [ -z "$_mastodon_ver" ]; then
                    _mastodon_ver="$1"
                elif [ -z "$_uri_ver" ]; then
                    _uri_ver="$1"
                else
                    die "인자가 너무 많습니다: $1"
                fi
                ;;
        esac
        shift
    done

    if [ -z "$_mastodon_ver" ] || [ -z "$_uri_ver" ]; then
        die "mastodon_version, uri_version이 필요합니다. 'uri graph --help'를 참조하세요."
    fi

    case "$_format" in
        tree|dot)
            ;;
        *)
            die "지원하지 않는 출력 형식입니다: $_format"
            ;;
    esac

    require_uri_root

    _manifest=$(resolve_manifest_path "$_mastodon_ver" "$_uri_ver")
    require_file "$_manifest" "manifest를 찾을 수 없습니다: $_manifest"

    _merged=$(resolve_inheritance "$_mastodon_ver" "$_uri_ver")

    case "$_format" in
        tree)
            render_dependency_graph_tree "$_merged" "$_include_dev"
            ;;
        dot)
            render_dependency_graph_dot "$_merged" "$_include_dev"
            ;;
    esac
}
