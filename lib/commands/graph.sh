#!/bin/sh
# graph.sh - graph command implementation
# POSIX-compatible shell script

# Print graph command usage
graph_usage() {
    cat <<EOF
Usage: uri graph <upstream_version> <patchset_version> [options]

Print the feature dependency graph for a patchset version.

Arguments:
  upstream_version   Upstream version (for example, v1.2.3+build)
  patchset_version   Patchset version (for example, stack-a)

Options:
  -h, --help         Print this help text
  --include-dev      Include dev-dependencies in the graph
  --format FORMAT    Output format: tree or dot (default: tree)

Examples:
  uri graph v1.2.3+build stack-a
  uri graph v1.2.3+build stack-a --include-dev
  uri graph v1.2.3+build stack-a --format dot
EOF
}

# Main graph command function
cmd_graph() {
    _upstream_version=""
    _patchset_version=""
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
                    die "--format requires a value. Specify tree or dot."
                fi
                _format="$1"
                ;;
            --format=*)
                _format="${1#--format=}"
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                if [ -z "$_upstream_version" ]; then
                    _upstream_version="$1"
                elif [ -z "$_patchset_version" ]; then
                    _patchset_version="$1"
                else
                    die "Too many arguments: $1"
                fi
                ;;
        esac
        shift
    done

    if [ -z "$_upstream_version" ] || [ -z "$_patchset_version" ]; then
        die "upstream_version and patchset_version are required. See 'uri graph --help'."
    fi

    case "$_format" in
        tree|dot)
            ;;
        *)
            die "Unsupported output format: $_format"
            ;;
    esac

    require_uri_root
    load_uri_config
    validate_identifier "upstream_version" "$_upstream_version"
    validate_identifier "patchset_version" "$_patchset_version"

    _manifest=$(resolve_manifest_path "$_upstream_version" "$_patchset_version")
    require_file "$_manifest" "Could not find manifest: $_manifest"

    _merged=$(resolve_inheritance "$_upstream_version" "$_patchset_version")

    case "$_format" in
        tree)
            render_dependency_graph_tree "$_merged" "$_include_dev"
            ;;
        dot)
            render_dependency_graph_dot "$_merged" "$_include_dev"
            ;;
    esac
}
