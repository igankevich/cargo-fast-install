#!/bin/sh
set -ex
commit="$(git rev-parse HEAD)"
sha256="$(sha256sum yard | awk '{ print $1 }')"
mkdir -p "$HOME"/.cargo/bin
curl -Lfo "$HOME"/.cargo/bin/yard "$GITHUB_SERVER_URL"/"$GITHUB_REPOSITORY"/raw/"$GITHUB_SHA"/yard
sha256sum -c - <<EOF
$sha256  $HOME/.cargo/bin/yard
EOF
chmod +x $HOME/.cargo/bin/yard
yard --version | tee /tmp/version1
./yard --version | tee /tmp/version2
diff /tmp/version1 /tmp/version2
