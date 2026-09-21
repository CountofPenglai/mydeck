#!/bin/sh
# Usage: sh tools/diagnostics/run_headless_checks.sh /path/to/Godot [log-directory]
set -u
godot_binary=${1:?Pass the Godot executable path}
log_directory=${2:-}
if [ -z "$log_directory" ]; then
    log_directory=$(mktemp -d /private/tmp/mydeck-checks.XXXXXX)
fi
mkdir -p "$log_directory"
failed=0
passed=0
for scene in $(rg --files tools/diagnostics -g '*.tscn' | rg -v 'visual_check' | sort); do
    check_name=$(basename "$scene" .tscn)
    check_log="$log_directory/$check_name.log"
    "$godot_binary" --headless --path . "$scene" -- --main-menu-diagnostics > "$check_log" 2>&1
    check_exit=$?
    if [ "$check_exit" -ne 0 ] || rg -q 'SCRIPT ERROR|Parse Error|FAIL|Assertion failed' "$check_log" \
        || { rg '^ERROR:' "$check_log" | rg -qv 'resources still in use|RID allocations|Texture with GL ID'; }; then
        failed=$((failed + 1))
        printf 'FAIL %s (exit %s)\n' "$check_name" "$check_exit"
        tail -n 25 "$check_log"
    else
        passed=$((passed + 1))
        printf 'PASS %s\n' "$check_name"
    fi
done
printf 'HEADLESS_SUITE: %s passed, %s failed; logs: %s\n' "$passed" "$failed" "$log_directory"
test "$failed" -eq 0
