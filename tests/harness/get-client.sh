#!/usr/bin/env bash
# get-client.sh floor|tested DEST: fetches the pinned Claude Code client for
# the harness (DECISIONS A49) into the folder DEST, as DEST/claude, and
# prints its path. "floor" is claude_code_min in REQUIRES; "tested" is the
# tested line of tests/harness/VERSIONS. The client comes from the npm
# registry's platform package (@anthropic-ai/claude-code-linux-x64), and the
# download must match the sha512 integrity pinned in VERSIONS; anything else
# fails (exit 1), and nothing is run. Linux x64 only for now (A27).
# Needs curl, tar and perl (Digest::SHA, MIME::Base64: core modules).
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
which=${1:-}
dest=${2:-}
die() {
  echo "get-client: $1" >&2
  exit 1
}
if [ -z "$which" ] || [ -z "$dest" ]; then
  die "usage: get-client.sh floor|tested DEST"
fi
case "$which" in
  floor) version=$(sed -n 's/^claude_code_min=//p' "$root/method/scripts/method/REQUIRES") ;;
  tested) version=$(sed -n 's/^tested	//p' "$here/VERSIONS") ;;
  *) die "usage: get-client.sh floor|tested DEST" ;;
esac
case "$version" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) die "no $which version found" ;;
esac
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) platform=linux-x64 ;;
  *) die "no pinned client for $(uname -s)/$(uname -m); the harness runs on Linux x64 (A27)" ;;
esac
want=$(awk -F '\t' -v v="$version" -v p="$platform" '$1 == v && $2 == p { print $3 }' "$here/VERSIONS")
[ -n "$want" ] || die "VERSIONS pins no checksum for $version on $platform"
mkdir -p "$dest" || die "cannot make $dest"
# the download is fetched, checked and unpacked in a new folder of its own,
# so no link already in DEST can send a write elsewhere; only the checked
# client is moved into place
work=$(mktemp -d "$dest/get.XXXXXX") || die "cannot make a work folder in $dest"
trap 'rm -rf "$work"' EXIT
tgz="$work/claude-$version.tgz"
# METHOD_HARNESS_REGISTRY: a stand-in registry, for the plants only
registry=${METHOD_HARNESS_REGISTRY:-https://registry.npmjs.org}
url="$registry/@anthropic-ai/claude-code-$platform/-/claude-code-$platform-$version.tgz"
curl -fsSL --retry 3 --connect-timeout 30 --max-time 600 -o "$tgz" "$url" || die "could not download $url"
got=$(perl -MDigest::SHA -MMIME::Base64 -e 'open my $f, "<:raw", $ARGV[0] or exit 1; my $d = Digest::SHA->new(512); $d->addfile($f); print "sha512-", encode_base64($d->digest, "")' "$tgz") || die "could not read $tgz"
if [ "$got" != "$want" ]; then
  die "the download of $version does not match VERSIONS (got $got); nothing was installed"
fi
tar -xzf "$tgz" -C "$work" package/claude || die "could not unpack $tgz"
if [ ! -f "$work/package/claude" ] || [ -L "$work/package/claude" ]; then
  die "the package holds no plain package/claude file"
fi
chmod +x "$work/package/claude" || die "cannot make the client runnable"
rm -rf "$dest/claude"
mv "$work/package/claude" "$dest/claude" || die "could not place the client in $dest"
printf '%s\n' "$dest/claude"
