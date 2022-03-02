#!/bin/bash

: "${KUSTOMIZE:=kustomize}"
: "${KUBEVAL:=kubeval}"
: "${CONFTEST:=conftest}"
: "${SCHEMA_LOCATION:=https://raw.githubusercontent.com/CCI-MOC/openshift-schemas/master/schemas/}"

PROCESS_ALL_TREES=0

find_overlays() {
    find * -type f -regex '.*/overlays/.*/kustomization.yaml' -printf '%h\n'
}

okay() {
    echo -n "$(tput setaf 2)${1}:okay$(tput sgr0) "
}

fail() {
    echo "$(tput setaf 1)${1}:failed$(tput sgr0)"
    [[ -s "$tmpdir/stdout" ]] && { echo; cat "$tmpdir/stdout"; }
    [[ -s "$tmpdir/stderr" ]] && { echo; cat "$tmpdir/stderr"; }
    exit 1
}

while getopts ais: ch; do
    case $ch in
        (a) PROCESS_ALL_TREES=1
            ;;

        (i) IGNORE_MISSING_SCHEMAS=1
            ;;

        (s) SCHEMA_LOCATION=$OPTARG
            ;;

        (*) echo "invalid flag: $ch" >&2
            exit 2
            ;;
    esac
done
shift $(( OPTIND - 1 ))

tmpdir=$(mktemp -d buildXXXXXX)
trap "rm -rf $tmpdir" EXIT

git diff-index HEAD^ --name-only --diff-filter ACMR > "$tmpdir/files-in-commit"

for overlay in $(find_overlays); do
    : > "$tmpdir/stdout"

    if [[ $PROCESS_ALL_TREES != 1 ]]; then
        grep "$overlay" "$tmpdir/files-in-commit" || continue
    fi

    echo -n "$overlay "
    if $KUSTOMIZE build "$overlay" > "$tmpdir/manifests.yaml" 2> "$tmpdir/stderr"; then
        okay build
    else
        fail build
    fi

    if $KUBEVAL --strict \
        ${IGNORE_MISSING_SCHEMAS:+--ignore-missing-schemas} \
        ${SCHEMA_LOCATION:+--additional-schema-locations $SCHEMA_LOCATION} \
            "$tmpdir/manifests.yaml" > "$tmpdir/stdout" 2> "$tmpdir/stderr"; then
        okay schema
    else
        fail schema
    fi

    echo
done
