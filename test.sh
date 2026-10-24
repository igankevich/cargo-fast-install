#!/bin/sh

main() {
    set -e
    workdir="$(mktemp -d)"
    root="$PWD"
    trap cleanup EXIT
    export PATH="$PWD:$PATH"
    spawn_local_registry
    generate_package
}

spawn_local_registry() {
    mkdir -p "$workdir"/http/registry
    mkdir -p "$workdir"/http/crates
    mkdir -p "$workdir"/http/binaries
    port=25593
    python3 -m http.server --directory "$workdir"/http --bind 127.0.0.1 "$port" &
    registry_pid=$!
    registry_url=http://127.0.0.1:"$port"/registry
    download_url=http://127.0.0.1:"$port"/crates
    binaries_url=http://127.0.0.1:"$port"/binaries
    cat >"$workdir"/http/registry/config.json <<EOF
{"dl":"$download_url"}
EOF
    until curl -fs "$registry_url"/config.json >/dev/null 2>&1; do
        sleep 1
    done
    export CARGO_FAST_INSTALL_REGISTRY="$registry_url"
}

generate_package() {
    mkdir "$workdir"/mycrate
    cd "$workdir"/mycrate
    cargo init --bin
    cargo build --release
    find
    cargo-fast-install --generate --url "$binaries_url/{crate.name}-{crate.version}-{target}.tar.gz"
    mv *.tar.gz "$workdir"/http/binaries
    cargo package --allow-dirty
    cksum="$(sha256sum target/package/mycrate-0.1.0.crate | awk '{ print $1 }')"
    mkdir -p "$workdir"/http/crates/mycrate/0.1.0
    cp target/package/mycrate-0.1.0.crate "$workdir"/http/crates/mycrate/0.1.0/download
    mkdir -p "$workdir"/http/registry/my/cr
    cat >"$workdir"/http/registry/my/cr/mycrate <<EOF
{"name":"mycrate","vers":"0.1.0","deps":[],"cksum":"$cksum","features":{},"yanked":false,"pubtime":"2026-09-17T21:00:56Z"}
EOF
    cargo-fast-install mycrate
}

cleanup() {
    kill "$registry_pid" 2>/dev/null || true
    rm -rf "$workdir"
}

main
