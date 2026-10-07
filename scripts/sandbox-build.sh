#!/bin/sh
# Builds the installed /opt/paseo tree for bb sandbox VMs and writes
# paseo-linux-<arch>.tar.gz to the output directory. Runs as root inside
# debian:trixie-slim so native modules (node-pty) link against the same glibc
# as the VMs. Usage: sandbox-build.sh <source-dir> <output-dir>
set -eu

src=$1
out=$2
node_version=22.23.3

case "$(uname -m)" in
  x86_64) arch=x64 ;;
  aarch64) arch=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl xz-utils git python3 make g++ >/dev/null

node_home=/usr/local/node
mkdir -p "$node_home"
curl -fsSL "https://nodejs.org/dist/v$node_version/node-v$node_version-linux-$arch.tar.xz" \
  | tar -xJ -C "$node_home" --strip-components=1
export PATH="$node_home/bin:$PATH"

# Build a clone of the committed tree: no local node_modules or edits, and no
# root-owned files left in the mounted checkout.
work=$(mktemp -d)
git config --global --add safe.directory '*'
git clone --quiet --no-hardlinks "$src" "$work"
cd "$work"
commit=$(git rev-parse HEAD)
echo "Paseo fork commit: $commit"

export ONNXRUNTIME_NODE_INSTALL=skip
node -e 'const fs=require("node:fs"); const p=JSON.parse(fs.readFileSync("package.json","utf8")); delete p.scripts.prepare; fs.writeFileSync("package.json",JSON.stringify(p));'
npm ci --no-audit --no-fund
npm run build:server
mkdir packs
for package in highlight relay protocol client plugin server cli; do
  npm pack --ignore-scripts --workspace="@getpaseo/$package" --pack-destination "$work/packs"
done

rm -rf /opt/paseo
npm install --global --prefix /opt/paseo --no-audit --no-fund "$work"/packs/*.tgz
cp "$node_home/bin/node" /opt/paseo/bin/node
echo "$commit" > /opt/paseo/COMMIT
/opt/paseo/bin/node --disable-warning=DEP0040 /opt/paseo/bin/paseo --version

mkdir -p "$out"
tar -C /opt -czf "$out/paseo-linux-$arch.tar.gz" paseo
echo "$commit" > "$out/COMMIT"
