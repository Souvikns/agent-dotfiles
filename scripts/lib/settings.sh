# scripts/lib/settings.sh — generate Claude Code's user settings file.
#
# Claude Code has exactly one user-scope settings file and no user-level
# override, and it writes to that file itself. Verified 2026-09-09: it rewrites
# settings.json on EVERY startup, using a temp file plus an atomic rename. A
# rename replaces a symlink rather than writing through it, so a symlinked
# settings.json would be destroyed on first launch. It also normalises values
# it writes back ("opus" came back as "opus[1m]").
#
# Hence: generated, not linked. Three-way deep merge, lowest precedence first:
#   1. the live file on disk       - keys we do not define survive, and because
#                                    they are never read from the repository,
#                                    private values never reach the remote
#   2. claude/settings.json        - shared base
#   3. claude/machines/<name>.json - this machine
#
# Objects merge recursively; every non-object value, arrays included, is
# replaced by the higher layer.

ad_settings_merge() {
    _l=$1; _b=$2; _m=$3
    if [ ! -f "$_l" ]; then _l=/dev/null; fi
    if [ ! -f "$_b" ]; then _b=/dev/null; fi
    if [ ! -f "$_m" ]; then _m=/dev/null; fi
    # --slurpfile on /dev/null yields an empty array, so `$x[0] // {}` is how a
    # missing layer degrades to an empty object instead of failing.
    jq -n --slurpfile live "$_l" --slurpfile base "$_b" --slurpfile machine "$_m" '
      def deepmerge(b):
        reduce (b | keys_unsorted[]) as $k (.;
          if (.[$k] | type) == "object" and (b[$k] | type) == "object"
          then .[$k] |= deepmerge(b[$k])
          else .[$k] = b[$k]
          end
        );
      ($live[0] // {}) | deepmerge($base[0] // {}) | deepmerge($machine[0] // {})
    '
}

# $1 repo  $2 machine  $3 target  $4 clean(0|1)  $5 dry(0|1)
ad_settings_write() {
    _live=$3
    if [ "$4" -eq 1 ]; then _live=/dev/null; fi
    if ! _out=$(ad_settings_merge "$_live" \
                                  "$1/claude/settings.json" \
                                  "$1/claude/machines/$2.json" 2>&1); then
        ad_die "settings merge failed (is $3 valid JSON?): $_out"
    fi
    # A dry run still performs the merge, so a malformed layer surfaces, but
    # writes nothing and prints nothing.
    if [ "$5" -eq 1 ]; then return 0; fi
    mkdir -p "$(dirname -- "$3")"
    printf '%s\n' "$_out" > "$3.tmp"
    mv "$3.tmp" "$3"
}
