# Sourced: downloads checked against pinned hashes.

fetch() {  # fetch URL FILE
    [[ -f "$2" ]] && return
    curl -fL --retry 5 -C - -o "$2.part" "$1"
    mv "$2.part" "$2"
}

verify() {  # verify sha256|sha1 HASH FILE
    "${1}sum" -c --quiet - <<< "$2  $3" && return
    rm -f -- "$3"
    echo "$3 does not match its pinned checksum and was deleted; run again." >&2
    exit 1
}
