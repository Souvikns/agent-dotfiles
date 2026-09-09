# scripts/lib/machine.sh — which machine is this?
# The name is chosen by the user, not derived from the hostname, because
# hostnames are personal, unstable, and would be published.

ad_machine_file() { printf '%s\n' "$(ad_config_home)/machine"; }

ad_machine_valid() {
    case "${1:-}" in
        '')                  return 1 ;;
        *[!a-zA-Z0-9._-]*)   return 1 ;;
        *)                   return 0 ;;
    esac
}

ad_machine_save() {
    _f=$(ad_machine_file)
    mkdir -p "$(dirname -- "$_f")"
    printf '%s\n' "$1" > "$_f"
}

ad_machine_load() {
    _f=$(ad_machine_file)
    if [ ! -f "$_f" ]; then return 1; fi
    _n=$(cat "$_f")
    if [ -z "$_n" ]; then return 1; fi
    printf '%s\n' "$_n"
}

ad_machine_resolve() {
    if [ -n "${1:-}" ]; then
        if ! ad_machine_valid "$1"; then
            ad_die "invalid machine name '$1' (letters, digits, dot, dash, underscore only)"
        fi
        ad_machine_save "$1"
        printf '%s\n' "$1"
        return 0
    fi
    if ! ad_machine_load; then
        ad_die "no machine name recorded; pass --machine NAME on first run"
    fi
}
