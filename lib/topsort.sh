#!/bin/sh
# topsort.sh - Topological sorting utilities
# POSIX-compatible shell script
# Dependency: platform-specific bundled uritsort

# Select the bundled uritsort for the detected platform
# Input: uname -s value, uname -m value
# Output: store the executable path in _URITSORT_BINARY
_select_uritsort_binary() {
    _uritsort_os="$1"
    _uritsort_arch="$2"

    case "$_uritsort_os" in
        Darwin)
            _uritsort_platform="macos"
            ;;
        Linux)
            _uritsort_platform="linux"
            ;;
        *)
            die "Unsupported uritsort platform (detected: $_uritsort_os/$_uritsort_arch)"
            ;;
    esac

    case "$_uritsort_arch" in
        arm64|aarch64)
            _uritsort_normalized_arch="arm64"
            ;;
        x86_64|amd64)
            _uritsort_normalized_arch="x86_64"
            ;;
        *)
            die "Unsupported uritsort platform (detected: $_uritsort_os/$_uritsort_arch)"
            ;;
    esac

    _uritsort_project_root=$(cd "$LIB_DIR/.." && pwd)
    _URITSORT_BINARY="${_uritsort_project_root}/libexec/uritsort/${_uritsort_platform}-${_uritsort_normalized_arch}/uritsort"

    if [ ! -f "$_URITSORT_BINARY" ]; then
        die "Bundled uritsort binary not found: $_URITSORT_BINARY (detected: $_uritsort_os/$_uritsort_arch)"
    fi
    if [ ! -x "$_URITSORT_BINARY" ]; then
        die "Bundled uritsort binary is not executable: $_URITSORT_BINARY (detected: $_uritsort_os/$_uritsort_arch)"
    fi
}

# Convert the existing edge-pair graph to uritsort's "node dependency..." format
_prepare_uritsort_input() {
    _uritsort_edges_file="$1"
    _uritsort_input_file="$2"

    awk '
        NF == 0 {
            next
        }

        {
            from = $1
            to = $2

            if (!(from in seen_node)) {
                seen_node[from] = 1
                nodes[++node_count] = from
            }
            if (!(to in seen_node)) {
                seen_node[to] = 1
                nodes[++node_count] = to
            }

            edge = to SUBSEP from
            if (from != to && !(edge in seen_edge)) {
                seen_edge[edge] = 1
                dependencies[to] = dependencies[to] " " from
            }
        }

        END {
            for (i = 1; i <= node_count; i++) {
                node = nodes[i]
                print node dependencies[node]
            }
        }
    ' "$_uritsort_edges_file" > "$_uritsort_input_file"
}

_run_uritsort() {
    _uritsort_edges_file="$1"
    _uritsort_binary="$2"
    _uritsort_input_file=$(make_temp)

    _prepare_uritsort_input "$_uritsort_edges_file" "$_uritsort_input_file"
    "$_uritsort_binary" "$_uritsort_input_file"
}

_uritsort_reports_cycle() {
    printf '%s\n' "$1" | grep -Fqi 'cycle detected among nodes:'
}

_topsort_file_with_binary() {
    _uritsort_edges_file="$1"
    _uritsort_binary="$2"

    if _uritsort_result=$(_run_uritsort "$_uritsort_edges_file" "$_uritsort_binary" 2>&1); then
        if [ -n "$_uritsort_result" ]; then
            printf '%s\n' "$_uritsort_result"
        fi
        return 0
    fi

    if _uritsort_reports_cycle "$_uritsort_result"; then
        die "Circular dependency detected: $_uritsort_result"
    fi
    die "Topological sort failed: $_uritsort_result"
}

# Topologically sort with the bundled uritsort
# Input: file containing edge pairs, one "preceding_node following_node" pair per line
# Output: sorted node list with preceding nodes first
# Usage: topsort_file "/path/to/edges.txt"
topsort_file() {
    _edges_file="$1"
    _select_uritsort_binary "$(uname -s)" "$(uname -m)"
    _topsort_file_with_binary "$_edges_file" "$_URITSORT_BINARY"
}

# Build a feature dependency graph from a manifest
# Input: manifest.yaml path and temporary path for storing edges
# Output: write dependencies to the edge file
# Usage: build_dependency_graph "manifest.yaml" "/tmp/edges.txt" ["true"|"false"]
build_dependency_graph() {
    _manifest="$1"
    _edges_file="$2"
    _include_dev="${3:-false}"

    # Initialize the edge file
    : > "$_edges_file"

    # List all features
    _features=$(yaml_list_features "$_manifest")

    # Convert each feature's dependencies into edges
    for _feature in $_features; do
        # Add the feature itself as a node so features without dependencies are included
        echo "$_feature $_feature" >> "$_edges_file"

        # Get the dependency list
        _deps=$(yaml_get_feature_dependencies "$_manifest" "$_feature" 2>/dev/null)

        for _dep in $_deps; do
            # Ignore empty strings and null
            if [ -n "$_dep" ] && [ "$_dep" != "null" ]; then
                # Record dep first because it must be applied before feature
                echo "$_dep $_feature" >> "$_edges_file"
            fi
        done

        if [ "$_include_dev" = "true" ]; then
            _dev_deps=$(yaml_get_feature_dev_dependencies "$_manifest" "$_feature" 2>/dev/null)

            for _dep in $_dev_deps; do
                # Ignore empty strings and null
                if [ -n "$_dep" ] && [ "$_dep" != "null" ]; then
                    # In include mode, record development dependencies as preceding features too
                    echo "$_dep $_feature" >> "$_edges_file"
                fi
            done
        fi
    done
}

# Return a sorted feature list from a manifest
# Usage: get_sorted_features "manifest.yaml" ["true"|"false"]
# Output: features sorted in dependency order, with dependencies first
get_sorted_features() {
    _manifest="$1"
    _include_dev="${2:-false}"

    # Create a temporary file
    _edges_file=$(make_temp)

    # Build the dependency graph
    build_dependency_graph "$_manifest" "$_edges_file" "$_include_dev"

    # Return an empty list when the file is empty
    if [ ! -s "$_edges_file" ]; then
        return 0
    fi

    # Topologically sort; edges are "dep feature", so the output is the application order
    topsort_file "$_edges_file"
}

get_sorted_features_with_dev() {
    _manifest="$1"
    get_sorted_features "$_manifest" "true"
}

# Render the dependency graph as a tree
# Usage: render_dependency_graph_tree "manifest.yaml" ["true"|"false"]
render_dependency_graph_tree() {
    _manifest="$1"
    _include_dev="${2:-false}"
    _edges_file=$(make_temp)
    _sorted_file=$(make_temp)

    build_dependency_graph "$_manifest" "$_edges_file" "$_include_dev"

    if [ ! -s "$_edges_file" ]; then
        return 0
    fi

    topsort_file "$_edges_file" > "$_sorted_file"

    awk '
        FNR == NR {
            order[++node_count] = $0
            next
        }

        {
            from = $1
            to = $2
            if (from != to) {
                edge[from SUBSEP to] = 1
                has_parent[to] = 1
            }
        }

        END {
            for (i = 1; i <= node_count; i++) {
                node = order[i]
                if (!(node in has_parent)) {
                    print node
                    print_children(node, "")
                }
            }
        }

        function print_children(node, prefix, i, child, child_count, seen, connector, child_prefix) {
            child_count = 0
            for (i = 1; i <= node_count; i++) {
                child = order[i]
                if ((node SUBSEP child) in edge) {
                    child_count++
                }
            }

            seen = 0
            for (i = 1; i <= node_count; i++) {
                child = order[i]
                if ((node SUBSEP child) in edge) {
                    seen++
                    if (seen == child_count) {
                        connector = "└─ "
                        child_prefix = prefix "   "
                    } else {
                        connector = "├─ "
                        child_prefix = prefix "│  "
                    }
                    print prefix connector child
                    print_children(child, child_prefix)
                }
            }
        }
    ' "$_sorted_file" "$_edges_file"
}

# Render the dependency graph as Graphviz DOT
# Usage: render_dependency_graph_dot "manifest.yaml" ["true"|"false"]
render_dependency_graph_dot() {
    _manifest="$1"
    _include_dev="${2:-false}"
    _edges_file=$(make_temp)
    _sorted_file=$(make_temp)

    build_dependency_graph "$_manifest" "$_edges_file" "$_include_dev"

    if [ -s "$_edges_file" ]; then
        topsort_file "$_edges_file" > "$_sorted_file"
    fi

    awk '
        FNR == NR {
            nodes[++node_count] = $0
            next
        }

        {
            from = $1
            to = $2
            if (from != to) {
                edge_from[++edge_count] = from
                edge_to[edge_count] = to
            }
        }

        END {
            print "digraph dependencies {"
            for (i = 1; i <= node_count; i++) {
                printf "  \"%s\";\n", dot_quote(nodes[i])
            }
            for (i = 1; i <= edge_count; i++) {
                printf "  \"%s\" -> \"%s\";\n", dot_quote(edge_from[i]), dot_quote(edge_to[i])
            }
            print "}"
        }

        function dot_quote(value) {
            gsub(/\\/, "\\\\", value)
            gsub(/"/, "\\\"", value)
            return value
        }
    ' "$_sorted_file" "$_edges_file"
}

# Return the feature list for apply, excluding development-only features
# Usage: get_sorted_apply_features "manifest.yaml"
get_sorted_apply_features() {
    _manifest="$1"
    _all_features=$(yaml_list_features "$_manifest")
    _dev_candidates=$(make_temp)
    _required_file=$(make_temp)
    _edges_file=$(make_temp)
    _filtered_edges=$(make_temp)

    # Exclude candidate features pulled in only by dev-dependencies, and their dependencies, from apply roots
    for _feature in $_all_features; do
        _dev_deps=$(yaml_get_feature_dev_dependencies "$_manifest" "$_feature" 2>/dev/null)
        for _dep in $_dev_deps; do
            if [ -n "$_dep" ] && [ "$_dep" != "null" ]; then
                _collect_deps "$_manifest" "$_dep" "$_dev_candidates" "true"
            fi
        done
    done

    # Treat remaining features as deployment roots and recursively collect regular dependencies only
    for _feature in $_all_features; do
        if ! grep -q "^${_feature}$" "$_dev_candidates" 2>/dev/null; then
            _collect_deps "$_manifest" "$_feature" "$_required_file" "false"
        fi
    done

    build_dependency_graph "$_manifest" "$_edges_file" "false"

    while IFS= read -r _line; do
        _from=$(echo "$_line" | cut -d' ' -f1)
        _to=$(echo "$_line" | cut -d' ' -f2)

        if grep -q "^${_from}$" "$_required_file" && grep -q "^${_to}$" "$_required_file"; then
            echo "$_line"
        fi
    done < "$_edges_file" > "$_filtered_edges"

    if [ -s "$_filtered_edges" ]; then
        topsort_file "$_filtered_edges"
    fi
}

# Return a sorted list containing a specific feature and its dependencies
# Usage: get_feature_with_deps "manifest.yaml" "feature_name" ["true"|"false"]
# Output: the feature and its dependencies in dependency order
get_feature_with_deps() {
    _manifest="$1"
    _target="$2"
    _include_dev="${3:-false}"

    # Temporary files
    _edges_file=$(make_temp)
    _required_file=$(make_temp)

    # Build the full dependency graph
    build_dependency_graph "$_manifest" "$_edges_file" "$_include_dev"

    # Recursively collect required features starting from the target feature
    _collect_deps "$_manifest" "$_target" "$_required_file" "$_include_dev"

    # Create an edge file containing only required features
    _filtered_edges=$(make_temp)
    while IFS= read -r _line; do
        _from=$(echo "$_line" | cut -d' ' -f1)
        _to=$(echo "$_line" | cut -d' ' -f2)

        # Include only edges whose two nodes are both required
        if grep -q "^${_from}$" "$_required_file" && grep -q "^${_to}$" "$_required_file"; then
            echo "$_line"
        fi
    done < "$_edges_file" > "$_filtered_edges"

    # Sort; edges are "dep feature", so the output is the application order
    if [ -s "$_filtered_edges" ]; then
        topsort_file "$_filtered_edges"
    fi
}

get_feature_with_deps_with_dev() {
    _manifest="$1"
    _target="$2"
    get_feature_with_deps "$_manifest" "$_target" "true"
}

# Recursively collect dependencies (internal function)
_collect_deps() {
    _manifest="$1"
    _feature="$2"
    _output_file="$3"
    _include_dev="${4:-false}"

    # Skip features already collected
    if grep -q "^${_feature}$" "$_output_file" 2>/dev/null; then
        return
    fi

    # Add the current feature
    echo "$_feature" >> "$_output_file"

    # Collect dependencies
    _deps=$(yaml_get_feature_dependencies "$_manifest" "$_feature" 2>/dev/null)
    for _dep in $_deps; do
        if [ -n "$_dep" ] && [ "$_dep" != "null" ]; then
            _collect_deps "$_manifest" "$_dep" "$_output_file" "$_include_dev"
        fi
    done

    if [ "$_include_dev" = "true" ]; then
        _dev_deps=$(yaml_get_feature_dev_dependencies "$_manifest" "$_feature" 2>/dev/null)
        for _dep in $_dev_deps; do
            if [ -n "$_dep" ] && [ "$_dep" != "null" ]; then
                _collect_deps "$_manifest" "$_dep" "$_output_file" "$_include_dev"
            fi
        done
    fi
}

# Reverse a sorted result for use by commands such as collapse
# Usage: echo "$sorted_list" | reverse_lines
reverse_lines() {
    # Reverse in a POSIX-compatible way
    # Use awk because tail -r is BSD-specific
    awk '{a[NR]=$0} END {for(i=NR;i>=1;i--) print a[i]}'
}

# Check only for circular dependencies
# Usage: check_circular_deps "manifest.yaml" ["true"|"false"]
check_circular_deps() {
    _manifest="$1"
    _include_dev="${2:-false}"
    _edges_file=$(make_temp)

    build_dependency_graph "$_manifest" "$_edges_file" "$_include_dev"

    if [ ! -s "$_edges_file" ]; then
        return 0
    fi

    _select_uritsort_binary "$(uname -s)" "$(uname -m)"

    if _uritsort_result=$(_run_uritsort "$_edges_file" "$_URITSORT_BINARY" 2>&1); then
        return 0
    fi

    if _uritsort_reports_cycle "$_uritsort_result"; then
        return 1
    fi
    die "Topological sort failed: $_uritsort_result"
}
