#!/bin/sh

main() {
    set -ex
    install_ruff
    check_with_ruff
    check_with_mypy
}

install_ruff() {
    file=ruff-x86_64-unknown-linux-musl
    curl -fLO https://github.com/astral-sh/ruff/releases/download/0.17.2/"$file".tar.gz
    sha256sum --check <<EOF
d6407f429ef15e558cbe980d30a67f27d02e3d2f72780be141ee006b2fdf7df3  $file.tar.gz
EOF
    tar xf "$file".tar.gz
    install -D -t ~/.local/bin -m755 "$file"/ruff
}

check_with_ruff() {
    ruff check cargo-fast-install
    ruff format --check cargo-fast-install
}

check_with_mypy() {
    pip install mypy
    mypy cargo-fast-install
}

main
