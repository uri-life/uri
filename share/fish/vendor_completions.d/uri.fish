# uri - fish shell completion

# --- Helper functions ---

# Find URI_ROOT
function __uri_find_root
    set -l dir $PWD
    while test "$dir" != /
        if test -f "$dir/manifest.yaml"
            echo "$dir"
            return 0
        end
        set dir (dirname "$dir")
    end
    return 1
end

# List upstream versions
function __uri_upstream_versions
    set -l root (__uri_find_root); or return
    set -l vdir "$root/versions"
    if test -d "$vdir"
        for d in $vdir/*/
            basename "$d"
        end
    end
end

# List patchset versions; requires an upstream_version argument
function __uri_patchset_versions
    set -l upstream_version $argv[1]
    set -l root (__uri_find_root); or return
    set -l pdir "$root/versions/$upstream_version/patches"
    if test -d "$pdir"
        for d in $pdir/*/
            basename "$d"
        end
    end
end

# List final active features
function __uri_features
    set -l upstream_version $argv[1]
    set -l patchset_version $argv[2]
    command uri list "$upstream_version" "$patchset_version" 2>/dev/null | string match -rv '^info: No features\.$'
end

# List features declared directly by the current manifest
function __uri_local_features
    set -l upstream_version $argv[1]
    set -l patchset_version $argv[2]
    set -l root (__uri_find_root); or return
    set -l manifest "$root/versions/$upstream_version/patches/$patchset_version/manifest.yaml"
    if command -q yq; and test -f "$manifest"
        yq eval '(.features // {}) | keys | .[]' "$manifest" 2>/dev/null
    end
end

function __uri_excluded_features
    set -l upstream_version $argv[1]
    set -l patchset_version $argv[2]
    set -l root (__uri_find_root); or return
    set -l manifest "$root/versions/$upstream_version/patches/$patchset_version/manifest.yaml"
    if command -q yq; and test -f "$manifest"
        yq eval '(.excludes // []) | .[]' "$manifest" 2>/dev/null
    end
end

function __uri_inherited_features
    set -l local_features (__uri_local_features $argv[1] $argv[2])
    for feature in (__uri_features $argv[1] $argv[2])
        if not contains -- "$feature" $local_features
            echo "$feature"
        end
    end
end

# Extract positional arguments after the subcommand, excluding flags
# argv: list of flags that consume a value, for example --upstream --name ...
function __uri_positional_args
    set -l value_flags $argv
    set -l tokens (commandline -opc)
    set -l positionals
    set -l skip_next false
    set -l found_subcmd false

    for i in (seq 2 (count $tokens))
        set -l tok $tokens[$i]
        if test "$skip_next" = true
            set skip_next false
            continue
        end
        if test "$found_subcmd" = false
            # Find the subcommand
            switch $tok
                case init add remove exclude include list expand collapse apply graph
                    set found_subcmd true
                case '-*'
                    continue
                case '*'
                    set found_subcmd true
            end
            continue
        end
        # Tokens after the subcommand
        switch $tok
            case '-*'
                if contains -- "$tok" $value_flags
                    set skip_next true
                end
            case '*'
                set -a positionals $tok
        end
    end
    if test (count $positionals) -gt 0
        printf '%s\n' $positionals
    end
end

# Check whether a flag is present on the command line
function __uri_has_flag
    set -l flag $argv[1]
    set -l tokens (commandline -opc)
    contains -- "$flag" $tokens
end

# Return the number of positional arguments for the current subcommand
function __uri_pos_count
    set -l pos (__uri_positional_args $argv)
    count $pos
end

# Return the nth positional argument
function __uri_get_pos
    set -l n $argv[1]
    set -l flags $argv[2..]
    set -l pos (__uri_positional_args $flags)
    if test (count $pos) -ge $n
        echo $pos[$n]
    end
end


# --- Top-level completion without a subcommand ---
complete -c uri -f -n '__fish_use_subcommand' -a init     -d 'Initialize a patch set'
complete -c uri -f -n '__fish_use_subcommand' -a add      -d 'Add a patchset version or feature'
complete -c uri -f -n '__fish_use_subcommand' -a remove   -d 'Remove a version or feature'
complete -c uri -f -n '__fish_use_subcommand' -a exclude  -d 'Exclude an inherited feature'
complete -c uri -f -n '__fish_use_subcommand' -a include  -d 'Include a feature excluded in the current version'
complete -c uri -f -n '__fish_use_subcommand' -a list     -d 'List versions or features'
complete -c uri -f -n '__fish_use_subcommand' -a expand   -d 'Apply a feature to the upstream source'
complete -c uri -f -n '__fish_use_subcommand' -a collapse -d 'Extract a patch file'
complete -c uri -f -n '__fish_use_subcommand' -a apply    -d 'Apply all features'
complete -c uri -f -n '__fish_use_subcommand' -a graph    -d 'Print the feature dependency graph'
complete -c uri -f -n '__fish_use_subcommand' -s h -l help    -d 'Help'
complete -c uri -f -n '__fish_use_subcommand' -s v -l version -d 'Print version'

# --- init ---
complete -c uri -f -n '__fish_seen_subcommand_from init' -s h -l help     -d 'Help'
complete -c uri -f -n '__fish_seen_subcommand_from init' -l upstream -x    -d 'upstream Git URL'
complete -c uri -f -n '__fish_seen_subcommand_from init' -l branch-prefix -x -d 'Branch prefix'
complete -c uri -f -n '__fish_seen_subcommand_from init' -l committer-name -x -d 'Committer name'
complete -c uri -f -n '__fish_seen_subcommand_from init' -l committer-email -x -d 'Committer email'
complete -c uri -f -n '__fish_seen_subcommand_from init; and test (__uri_pos_count --upstream --branch-prefix --committer-name --committer-email) -eq 0' \
    -a '(__uri_upstream_versions)' -d 'Upstream version'

# --- add ---
complete -c uri -f -n '__fish_seen_subcommand_from add' -s h -l help          -d 'Help'
complete -c uri -f -n '__fish_seen_subcommand_from add' -l name         -x    -d 'Feature name'
complete -c uri -f -n '__fish_seen_subcommand_from add' -l description  -x    -d 'Feature description'
complete -c uri -f -n '__fish_seen_subcommand_from add' -l dependencies -x    -d 'Required features'
complete -c uri -f -n '__fish_seen_subcommand_from add' -l dev-dependencies -x -d 'Development-only dependencies'
complete -c uri -f -n '__fish_seen_subcommand_from add' -l inherits     -x    -d 'Patchset version to inherit'
complete -c uri -f -n '__fish_seen_subcommand_from add' -l inherits-upstream -x -d 'Upstream version to inherit'

complete -c uri -f -n '__fish_seen_subcommand_from add; and test (__uri_pos_count --name --description --dependencies --dev-dependencies --inherits --inherits-upstream) -eq 0' \
    -a '(__uri_upstream_versions)' -d 'Upstream version'
complete -c uri -f -n '__fish_seen_subcommand_from add; and test (__uri_pos_count --name --description --dependencies --dev-dependencies --inherits --inherits-upstream) -eq 1' \
    -a '(__uri_patchset_versions (__uri_get_pos 1 --name --description --dependencies --dev-dependencies --inherits --inherits-upstream))' -d 'Patchset version'
complete -c uri -f -n '__fish_seen_subcommand_from add; and test (__uri_pos_count --name --description --dependencies --dev-dependencies --inherits --inherits-upstream) -eq 2' \
    -a '(__uri_features (__uri_get_pos 1 --name --description --dependencies --dev-dependencies --inherits --inherits-upstream) (__uri_get_pos 2 --name --description --dependencies --dev-dependencies --inherits --inherits-upstream))' -d 'feature'

# --- remove ---
complete -c uri -f -n '__fish_seen_subcommand_from remove' -s h -l help  -d 'Help'
complete -c uri -f -n '__fish_seen_subcommand_from remove' -s f -l force -d 'Force deletion'

complete -c uri -f -n '__fish_seen_subcommand_from remove; and test (__uri_pos_count) -eq 0' \
    -a '(__uri_upstream_versions)' -d 'Upstream version'
complete -c uri -f -n '__fish_seen_subcommand_from remove; and test (__uri_pos_count) -eq 1' \
    -a '(__uri_patchset_versions (__uri_get_pos 1))' -d 'Patchset version'
complete -c uri -f -n '__fish_seen_subcommand_from remove; and test (__uri_pos_count) -eq 2' \
    -a '(__uri_local_features (__uri_get_pos 1) (__uri_get_pos 2))' -d 'feature'

# --- exclude ---
complete -c uri -f -n '__fish_seen_subcommand_from exclude' -s h -l help -d 'Help'
complete -c uri -f -n '__fish_seen_subcommand_from exclude; and test (__uri_pos_count) -eq 0' \
    -a '(__uri_upstream_versions)' -d 'Upstream version'
complete -c uri -f -n '__fish_seen_subcommand_from exclude; and test (__uri_pos_count) -eq 1' \
    -a '(__uri_patchset_versions (__uri_get_pos 1))' -d 'Patchset version'
complete -c uri -f -n '__fish_seen_subcommand_from exclude; and test (__uri_pos_count) -eq 2' \
    -a '(__uri_inherited_features (__uri_get_pos 1) (__uri_get_pos 2))' -d 'Inherited feature'

# --- include ---
complete -c uri -f -n '__fish_seen_subcommand_from include' -s h -l help -d 'Help'
complete -c uri -f -n '__fish_seen_subcommand_from include; and test (__uri_pos_count) -eq 0' \
    -a '(__uri_upstream_versions)' -d 'Upstream version'
complete -c uri -f -n '__fish_seen_subcommand_from include; and test (__uri_pos_count) -eq 1' \
    -a '(__uri_patchset_versions (__uri_get_pos 1))' -d 'Patchset version'
complete -c uri -f -n '__fish_seen_subcommand_from include; and test (__uri_pos_count) -eq 2' \
    -a '(__uri_excluded_features (__uri_get_pos 1) (__uri_get_pos 2))' -d 'Excluded feature'

# --- list ---
complete -c uri -f -n '__fish_seen_subcommand_from list' -s h -l help -d 'Help'

complete -c uri -f -n '__fish_seen_subcommand_from list; and test (__uri_pos_count) -eq 0' \
    -a '(__uri_upstream_versions)' -d 'Upstream version'
complete -c uri -f -n '__fish_seen_subcommand_from list; and test (__uri_pos_count) -eq 1' \
    -a '(__uri_patchset_versions (__uri_get_pos 1))' -d 'Patchset version'

# --- expand ---
complete -c uri -f -n '__fish_seen_subcommand_from expand' -s h -l help     -d 'Help'
complete -c uri -f -n '__fish_seen_subcommand_from expand' -l continue       -d 'Continue after resolving conflicts'
complete -c uri -f -n '__fish_seen_subcommand_from expand' -l abort          -d 'Abort operation'
complete -c uri -f -n '__fish_seen_subcommand_from expand' -l force          -d 'Delete existing branch'
complete -c uri -f -n '__fish_seen_subcommand_from expand' -l no-dev         -d 'Exclude development dependencies'

# --continue/--abort mode: destination directories only
complete -c uri -F -n '__fish_seen_subcommand_from expand; and __uri_has_flag --continue; and test (__uri_pos_count) -eq 0'
complete -c uri -F -n '__fish_seen_subcommand_from expand; and __uri_has_flag --abort; and test (__uri_pos_count) -eq 0'

# Normal mode
complete -c uri -f -n '__fish_seen_subcommand_from expand; and not __uri_has_flag --continue; and not __uri_has_flag --abort; and test (__uri_pos_count) -eq 0' \
    -a '(__uri_upstream_versions)' -d 'Upstream version'
complete -c uri -f -n '__fish_seen_subcommand_from expand; and not __uri_has_flag --continue; and not __uri_has_flag --abort; and test (__uri_pos_count) -eq 1' \
    -a '(__uri_patchset_versions (__uri_get_pos 1))' -d 'Patchset version'
complete -c uri -f -n '__fish_seen_subcommand_from expand; and not __uri_has_flag --continue; and not __uri_has_flag --abort; and test (__uri_pos_count) -eq 2' \
    -a '(__uri_features (__uri_get_pos 1) (__uri_get_pos 2))' -d 'feature'
complete -c uri -F -n '__fish_seen_subcommand_from expand; and not __uri_has_flag --continue; and not __uri_has_flag --abort; and test (__uri_pos_count) -eq 3'

# --- collapse ---
complete -c uri -f -n '__fish_seen_subcommand_from collapse' -s h -l help -d 'Help'
complete -c uri -f -n '__fish_seen_subcommand_from collapse' -l recursive -d 'Recursively update dependent features'

complete -c uri -f -n '__fish_seen_subcommand_from collapse; and test (__uri_pos_count) -eq 0' \
    -a '(__uri_upstream_versions)' -d 'Upstream version'
complete -c uri -f -n '__fish_seen_subcommand_from collapse; and test (__uri_pos_count) -eq 1' \
    -a '(__uri_patchset_versions (__uri_get_pos 1))' -d 'Patchset version'
complete -c uri -f -n '__fish_seen_subcommand_from collapse; and test (__uri_pos_count) -eq 2' \
    -a '(__uri_features (__uri_get_pos 1) (__uri_get_pos 2))' -d 'feature'
complete -c uri -F -n '__fish_seen_subcommand_from collapse; and test (__uri_pos_count) -eq 3'

# --- apply ---
complete -c uri -f -n '__fish_seen_subcommand_from apply' -s h -l help  -d 'Help'
complete -c uri -f -n '__fish_seen_subcommand_from apply' -l continue    -d 'Continue after resolving conflicts'
complete -c uri -f -n '__fish_seen_subcommand_from apply' -l abort       -d 'Abort operation'

# --continue/--abort mode: destination directories only
complete -c uri -F -n '__fish_seen_subcommand_from apply; and __uri_has_flag --continue; and test (__uri_pos_count) -eq 0'
complete -c uri -F -n '__fish_seen_subcommand_from apply; and __uri_has_flag --abort; and test (__uri_pos_count) -eq 0'

# Normal mode
complete -c uri -f -n '__fish_seen_subcommand_from apply; and not __uri_has_flag --continue; and not __uri_has_flag --abort; and test (__uri_pos_count) -eq 0' \
    -a '(__uri_upstream_versions)' -d 'Upstream version'
complete -c uri -f -n '__fish_seen_subcommand_from apply; and not __uri_has_flag --continue; and not __uri_has_flag --abort; and test (__uri_pos_count) -eq 1' \
    -a '(__uri_patchset_versions (__uri_get_pos 1))' -d 'Patchset version'
complete -c uri -F -n '__fish_seen_subcommand_from apply; and not __uri_has_flag --continue; and not __uri_has_flag --abort; and test (__uri_pos_count) -eq 2'

# --- graph ---
complete -c uri -f -n '__fish_seen_subcommand_from graph' -s h -l help        -d 'Help'
complete -c uri -f -n '__fish_seen_subcommand_from graph' -l include-dev       -d 'Include development dependencies'
complete -c uri -f -n '__fish_seen_subcommand_from graph' -l format -xa 'tree dot' -d 'Output format'

complete -c uri -f -n '__fish_seen_subcommand_from graph; and test (__uri_pos_count --format) -eq 0' \
    -a '(__uri_upstream_versions)' -d 'Upstream version'
complete -c uri -f -n '__fish_seen_subcommand_from graph; and test (__uri_pos_count --format) -eq 1' \
    -a '(__uri_patchset_versions (__uri_get_pos 1 --format))' -d 'Patchset version'
