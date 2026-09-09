# scripts/lib/manifest.sh — the record of what this repository installed.
# uninstall.sh removes only what appears here and still matches.

ad_manifest_path() { printf '%s\n' "$(ad_state_home)/manifest.json"; }

ad_manifest_init() {
    _p=$(ad_manifest_path)
    mkdir -p "$(dirname -- "$_p")"
    jq -n --arg repo "$1" --arg machine "$2" \
          --arg rev "$(ad_repo_revision "$1")" --arg ts "$(ad_timestamp)" \
       '{repo: $repo, revision: $rev, machine: $machine,
         installed_at: $ts, targets: []}' > "$_p"
}

ad_manifest_machine() {
    _p=$(ad_manifest_path)
    if [ ! -f "$_p" ]; then return 1; fi
    jq -r '.machine' "$_p"
}

# Replaces any existing row for the same target, so reruns do not duplicate.
ad_manifest_add() {
    _p=$(ad_manifest_path)
    jq --arg kind "$1" --arg src "$2" --arg tgt "$3" --arg bak "$4" \
       --arg ts "$(ad_timestamp)" \
       '.targets |= (map(select(.target != $tgt))
                     + [{kind: $kind, source: $src, target: $tgt,
                         backup: (if $bak == "" then null else $bak end),
                         timestamp: $ts}])' "$_p" > "$_p.tmp"
    mv "$_p.tmp" "$_p"
}

ad_manifest_targets() {
    _p=$(ad_manifest_path)
    if [ ! -f "$_p" ]; then return 1; fi
    jq -r '.targets[] | [.kind, .source, .target, (.backup // "")] | join("|")' "$_p"
}
