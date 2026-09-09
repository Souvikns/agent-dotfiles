# scripts/lib/backup.sh — move a conflicting target aside, reversibly.
#
# Backups live under the state home rather than inside either tool's
# configuration directory: a backup under CLAUDE_HOME would be read by Claude
# Code as live configuration.

ad_backup_dir() { printf '%s\n' "$(ad_state_home)/backups/$1"; }

# The slot mirrors the absolute target path with the leading slash removed, so
# the original location is recoverable from the slot alone.
ad_backup_slot() {
    _rel=$(printf '%s' "$2" | sed 's|^/||')
    printf '%s\n' "$(ad_backup_dir "$1")/$_rel"
}

ad_backup_move() {
    _slot=$(ad_backup_slot "$1" "$2")
    mkdir -p "$(dirname -- "$_slot")"
    mv "$2" "$_slot"
    printf '%s\n' "$_slot"
}

ad_backup_restore() {
    if [ ! -e "$1" ]; then return 1; fi
    if [ -e "$2" ]; then return 1; fi
    mkdir -p "$(dirname -- "$2")"
    mv "$1" "$2"
}

ad_backup_latest() {
    _d="$(ad_state_home)/backups"
    if [ ! -d "$_d" ]; then return 1; fi
    _l=$(ls -1 "$_d" 2>/dev/null | sort | tail -1)
    if [ -z "$_l" ]; then return 1; fi
    printf '%s\n' "$_l"
}
