#!/bin/sh
# init.sh - init command implementation
# POSIX-compatible shell script

init_usage() {
    cat <<EOF
Usage: uri init --upstream URL [options] [upstream_version]

Initialize a Git patch set. --upstream is required for a new root.

Arguments:
  upstream_version       Upstream tag or version (for example, v1.2.3+build)
                         When omitted, create only the root manifest

Options:
  -h, --help             Print this help text
  --upstream URL         upstream Git URL
  --branch-prefix PREFIX Top-level prefix for generated branches (default: uri)
  --committer-name NAME  Explicit committer name for applying patches
  --committer-email EMAIL Explicit committer email for applying patches

Configuration options are not required when adding only a version to an existing root.
When provided again, they must exactly match the stored values.

Examples:
  uri init --upstream https://example.com/project.git
  uri init --upstream https://example.com/project.git v1.2.3+build
  uri init v1.2.4
EOF
}

cmd_init() {
    _init_upstream=""
    _init_upstream_set=false
    _init_branch_prefix="uri"
    _init_branch_prefix_set=false
    _init_committer_name=""
    _init_committer_name_set=false
    _init_committer_email=""
    _init_committer_email_set=false
    _init_upstream_version=""

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                init_usage
                exit 0
                ;;
            --upstream|--branch-prefix|--committer-name|--committer-email)
                _init_option="$1"
                shift
                [ $# -gt 0 ] || die "$_init_option requires a value."
                case "$_init_option" in
                    --upstream)
                        _init_upstream="$1"
                        _init_upstream_set=true
                        ;;
                    --branch-prefix)
                        _init_branch_prefix="$1"
                        _init_branch_prefix_set=true
                        ;;
                    --committer-name)
                        _init_committer_name="$1"
                        _init_committer_name_set=true
                        ;;
                    --committer-email)
                        _init_committer_email="$1"
                        _init_committer_email_set=true
                        ;;
                esac
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                if [ -z "$_init_upstream_version" ]; then
                    _init_upstream_version="$1"
                else
                    die "Too many arguments: $1"
                fi
                ;;
        esac
        shift
    done

    if [ "$_init_committer_name_set" != "$_init_committer_email_set" ]; then
        die "--committer-name and --committer-email must be specified together."
    fi
    if [ "$_init_committer_name_set" = true ] && \
        { [ -z "$_init_committer_name" ] || [ -z "$_init_committer_email" ]; }; then
        die "The committer name and email must not be empty."
    fi
    if [ -n "$_init_upstream_version" ]; then
        validate_identifier "upstream_version" "$_init_upstream_version"
    fi
    validate_identifier "branch-prefix" "$_init_branch_prefix"

    if set_uri_root_if_exists; then
        load_uri_config
        _validate_existing_init_config
        if [ -z "$_init_upstream_version" ]; then
            die "Already initialized: ${URI_ROOT}/manifest.yaml"
        fi
        _init_upstream_version_dir "$_init_upstream_version"
        return
    fi

    [ "$_init_upstream_set" = true ] || die "A new patch set requires --upstream URL."
    [ -n "$_init_upstream" ] || die "--upstream URL must not be empty."

    _init_root="$PWD"
    _init_manifest="${_init_root}/manifest.yaml"
    info "Initializing patch set..."

    if [ "$_init_committer_name_set" = true ]; then
        URI_INIT_UPSTREAM="$_init_upstream" \
        URI_INIT_PREFIX="$_init_branch_prefix" \
        URI_INIT_NAME="$_init_committer_name" \
        URI_INIT_EMAIL="$_init_committer_email" \
            yq -n '{"upstream": strenv(URI_INIT_UPSTREAM), "branch-prefix": strenv(URI_INIT_PREFIX), "committer": {"mode": "explicit", "name": strenv(URI_INIT_NAME), "email": strenv(URI_INIT_EMAIL)}}' > "$_init_manifest"
    else
        URI_INIT_UPSTREAM="$_init_upstream" URI_INIT_PREFIX="$_init_branch_prefix" \
            yq -n '{"upstream": strenv(URI_INIT_UPSTREAM), "branch-prefix": strenv(URI_INIT_PREFIX), "committer": {"mode": "repository"}}' > "$_init_manifest"
    fi

    mkdir -p "${_init_root}/versions"
    success "Initialized: $_init_manifest"

    if [ -n "$_init_upstream_version" ]; then
        URI_ROOT="$_init_root"
        export URI_ROOT
        _init_upstream_version_dir "$_init_upstream_version"
    fi
}

_validate_existing_init_config() {
    if [ "$_init_upstream_set" = true ] && [ "$_init_upstream" != "$URI_UPSTREAM" ]; then
        die "The existing upstream setting cannot be changed."
    fi
    if [ "$_init_branch_prefix_set" = true ] && [ "$_init_branch_prefix" != "$URI_BRANCH_PREFIX" ]; then
        die "The existing branch-prefix setting cannot be changed."
    fi
    if [ "$_init_committer_name_set" = true ]; then
        if [ "$URI_COMMITTER_MODE" != "explicit" ] || \
            [ "$_init_committer_name" != "$URI_COMMITTER_NAME" ] || \
            [ "$_init_committer_email" != "$URI_COMMITTER_EMAIL" ]; then
            die "The existing committer setting cannot be changed."
        fi
    fi
}

_init_upstream_version_dir() {
    _iuv_version="$1"
    _iuv_dir=$(upstream_version_dir "$_iuv_version")

    if [ -d "$_iuv_dir" ]; then
        info "Upstream version directory already exists: $_iuv_dir"
        return
    fi

    info "Creating structure for upstream version $_iuv_version..."
    mkdir -p "${_iuv_dir}/patches"
    success "Created upstream version structure: $_iuv_dir"
}

# Alias retained for compatibility with legacy internal tests and callers.
_init_version() {
    _init_upstream_version_dir "$1"
}
