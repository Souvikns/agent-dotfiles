# scripts/lib/link.sh — the three link rules.
#
#   1. target missing            -> create the link
#   2. target already correct    -> no operation (this is what makes reruns
#                                   idempotent: no backup, no rewrite)
#   3. anything else             -> refuse, unless --force, which backs up first
#
# Refusing by default is deliberate. Hand migration was chosen over automatic
# adoption, so the installer must never silently absorb or discard content it
# did not create.
#
# Caller contract: ad_link_apply returns non-zero for refusal, so under `set -e`
# a caller must write `out=$(ad_link_apply ...) || rc=$?` and never call it bare.

ad_link_state() {
    if [ -L "$1" ]; then
        if [ "$(readlink "$1")" = "$2" ]; then printf 'ok\n'; else printf 'foreign\n'; fi
    elif [ -e "$1" ]; then
        printf 'occupied\n'
    else
        printf 'missing\n'
    fi
}

# $1 source  $2 target  $3 force(0|1)  $4 dry(0|1)  $5 timestamp
# exit 0 applied, 3 refused, 4 source missing
ad_link_apply() {
    if [ ! -e "$1" ]; then
        printf 'missing-source\n'
        return 4
    fi

    _st=$(ad_link_state "$2" "$1")

    if [ "$_st" = "ok" ]; then
        printf 'noop\n'
        return 0
    fi

    if [ "$_st" = "missing" ]; then
        if [ "$4" -eq 0 ]; then
            mkdir -p "$(dirname -- "$2")"
            ln -s "$1" "$2"
        fi
        printf 'create\n'
        return 0
    fi

    if [ "$3" -ne 1 ]; then
        printf 'refuse %s\n' "$_st"
        return 3
    fi

    if [ "$4" -eq 1 ]; then
        printf 'replace %s\n' "$(ad_backup_slot "$5" "$2")"
        return 0
    fi

    _slot=$(ad_backup_move "$5" "$2")
    mkdir -p "$(dirname -- "$2")"
    ln -s "$1" "$2"
    printf 'replace %s\n' "$_slot"
    return 0
}
