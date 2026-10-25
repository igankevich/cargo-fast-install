#!/bin/sh

main() {
    set -e
    workdir="$(mktemp -d)"
    root="$PWD"
    trap cleanup EXIT
    export PATH="$PWD:$PATH"
    python3 --version
    spawn_local_registry
    run_test test_normal_package
    run_test test_normal_package_with_variant
    run_test test_bad_archive_hash
    run_test test_bad_crate_hash
    run_test test_yanked_crate
}

spawn_local_registry() {
    mkdir -p "$workdir"/http/registry
    mkdir -p "$workdir"/http/crates
    mkdir -p "$workdir"/http/binaries
    port=25593
    python3 -m http.server --directory "$workdir"/http --bind 127.0.0.1 "$port" >/dev/null 2>&1 &
    registry_pid=$!
    registry_url=http://127.0.0.1:"$port"/registry
    download_url=http://127.0.0.1:"$port"/crates
    binaries_url=http://127.0.0.1:"$port"/binaries
    touch "$workdir"/http/registry/health
    until curl -fs "$registry_url"/health >/dev/null 2>&1; do
        sleep 1
    done
    export CARGO_FAST_INSTALL_REGISTRY="$registry_url"
}

run_test() {
    for dir in registry crates binaries; do
        rm -rf "$workdir"/http/"$dir"
        mkdir -p "$workdir"/http/"$dir"
    done
    rm -rf "$workdir"/mycrate
    cat >"$workdir"/http/registry/config.json <<EOF
{"dl":"$download_url"}
EOF
    set +e
    printf "Running %s…\n" "$*" >&2
    "$@" >"$workdir"/run-test-output 2>&1
    ret=$?
    set -e
    if test "$ret" != 0; then
        printf "Expected \`%s\` to succeed, but it failed\n" "$*" >&2
        cat "$workdir"/run-test-output >&2
        exit 1
    fi
}

expect_fail() {
    set +e
    "$@" >"$workdir"/stdout 2>&1
    ret=$?
    set -e
    if test "$ret" = 0; then
        printf "Expected \`%s\` to fail, but it succeeded\n" "$*" >&2
        cat "$workdir"/stdout >&2
        return 1
    fi
}

test_archive_reproducibility() {
    mkdir "$workdir"/mycrate
    cd "$workdir"/mycrate
    cargo init --bin
    cargo build --release
    cargo-fast-install --generate --url "$binaries_url/{crate.name}-{crate.version}-{target}.tar.gz"
    sha256sum cargo-fast-install.jsonl >"$workdir"/CHECKSUM
    sleep 1
    cargo-fast-install --generate --url "$binaries_url/{crate.name}-{crate.version}-{target}.tar.gz"
    sha256sum --check "$workdir"/CHECKSUM
}

test_normal_package() {
    mkdir "$workdir"/mycrate
    cd "$workdir"/mycrate
    cargo init --bin
    cargo build --release
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
    expect_fail cargo-fast-install mycrate:full
}

test_normal_package_with_variant() {
    mkdir "$workdir"/mycrate
    cd "$workdir"/mycrate
    cargo init --bin
    cargo build --release
    cargo-fast-install --generate --url "$binaries_url/{crate.name}-{crate.version}-{target}.tar.gz" --variant full
    cat cargo-fast-install.jsonl
    mv *.tar.gz "$workdir"/http/binaries
    cargo package --allow-dirty
    cksum="$(sha256sum target/package/mycrate-0.1.0.crate | awk '{ print $1 }')"
    mkdir -p "$workdir"/http/crates/mycrate/0.1.0
    cp target/package/mycrate-0.1.0.crate "$workdir"/http/crates/mycrate/0.1.0/download
    mkdir -p "$workdir"/http/registry/my/cr
    cat >"$workdir"/http/registry/my/cr/mycrate <<EOF
{"name":"mycrate","vers":"0.1.0","deps":[],"cksum":"$cksum","features":{},"yanked":false,"pubtime":"2026-09-17T21:00:56Z"}
EOF
    cargo-fast-install mycrate:full
    expect_fail cargo-fast-install mycrate
}

test_bad_archive_hash() {
    mkdir "$workdir"/mycrate
    cd "$workdir"/mycrate
    cargo init --bin
    cargo build --release
    cargo-fast-install --generate --url "$binaries_url/{crate.name}.tar.gz"
    # Damage the archive.
    printf "x" >>mycrate.tar.gz
    mv mycrate.tar.gz "$workdir"/http/binaries
    cargo package --allow-dirty
    cksum="$(sha256sum target/package/mycrate-0.1.0.crate | awk '{ print $1 }')"
    mkdir -p "$workdir"/http/crates/mycrate/0.1.0
    cp target/package/mycrate-0.1.0.crate "$workdir"/http/crates/mycrate/0.1.0/download
    mkdir -p "$workdir"/http/registry/my/cr
    cat >"$workdir"/http/registry/my/cr/mycrate <<EOF
{"name":"mycrate","vers":"0.1.0","deps":[],"cksum":"$cksum","features":{},"yanked":false,"pubtime":"2026-09-17T21:00:56Z"}
EOF
    expect_fail cargo-fast-install mycrate
}

test_bad_crate_hash() {
    mkdir "$workdir"/mycrate
    cd "$workdir"/mycrate
    cargo init --bin
    cargo build --release
    cargo-fast-install --generate --url "$binaries_url/{crate.name}.tar.gz"
    mv mycrate.tar.gz "$workdir"/http/binaries
    cargo package --allow-dirty
    cksum="$(sha256sum target/package/mycrate-0.1.0.crate | awk '{ print $1 }')"
    # Damage the crate.
    printf "x" >>target/package/mycrate-0.1.0.crate
    mkdir -p "$workdir"/http/crates/mycrate/0.1.0
    cp target/package/mycrate-0.1.0.crate "$workdir"/http/crates/mycrate/0.1.0/download
    mkdir -p "$workdir"/http/registry/my/cr
    cat >"$workdir"/http/registry/my/cr/mycrate <<EOF
{"name":"mycrate","vers":"0.1.0","deps":[],"cksum":"$cksum","features":{},"yanked":false,"pubtime":"2026-09-17T21:00:56Z"}
EOF
    expect_fail cargo-fast-install mycrate
}

test_yanked_crate() {
    mkdir "$workdir"/mycrate
    cd "$workdir"/mycrate
    cargo init --bin
    cargo build --release
    cargo-fast-install --generate --url "$binaries_url/{crate.name}.tar.gz"
    mv mycrate.tar.gz "$workdir"/http/binaries
    cargo package --allow-dirty
    cksum="$(sha256sum target/package/mycrate-0.1.0.crate | awk '{ print $1 }')"
    mkdir -p "$workdir"/http/crates/mycrate/0.1.0
    cp target/package/mycrate-0.1.0.crate "$workdir"/http/crates/mycrate/0.1.0/download
    mkdir -p "$workdir"/http/registry/my/cr
    cat >"$workdir"/http/registry/my/cr/mycrate <<EOF
{"name":"mycrate","vers":"0.1.0","deps":[],"cksum":"$cksum","features":{},"yanked":true,"pubtime":"2026-09-17T21:00:56Z"}
EOF
    expect_fail cargo-fast-install mycrate
    expect_fail cargo-fast-install --crate mycrate@"$cksum" mycrate
}

cleanup() {
    kill "$registry_pid" 2>/dev/null || true
    rm -rf "$workdir"
}

main
