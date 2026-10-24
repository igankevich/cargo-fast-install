#!/bin/sh
set -ex
commit="$(git rev-parse HEAD)"
sha256="$(sha256sum cargo-fast-install | awk '{ print $1 }')"
mkdir -p "$HOME"/.cargo/bin
curl -Lfo "$HOME"/.cargo/bin/cargo-fast-install "$GITHUB_SERVER_URL"/"$GITHUB_REPOSITORY"/raw/"$GITHUB_SHA"/cargo-fast-install
sha256sum -c - <<EOF
$sha256  $HOME/.cargo/bin/cargo-fast-install
EOF
chmod +x $HOME/.cargo/bin/cargo-fast-install
export PATHEXT="$PATHEXT:.PY"
export PATH="$HOME/.cargo/bin:$PATH"
cargo fast-install --version
