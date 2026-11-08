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
[ -n "$which" ] && [ -n "$dest" ] || die "usage: get-client.sh floor|tested DEST"
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
tgz="$dest/claude-$version.tgz"
# METHOD_HARNESS_REGISTRY: a stand-in registry, for the plants only
registry=${METHOD_HARNESS_REGISTRY:-https://registry.npmjs.org}
url="$registry/@anthropic-ai/claude-code-$platform/-/claude-code-$platform-$version.tgz"
curl -fsSL --retry 3 --connect-timeout 30 --max-time 600 -o "$tgz" "$url" || { rm -f "$tgz"; die "could not download $url"; }
got=$(perl -MDigest::SHA -MMIME::Base64 -e 'open my $f, "<:raw", $ARGV[0] or exit 1; my $d = Digest::SHA->new(512); $d->addfile($f); print "sha512-", encode_base64($d->digest, "")' "$tgz") || { rm -f "$tgz"; die "could not read $tgz"; }
if [ "$got" != "$want" ]; then
  rm -f "$tgz"
  die "the download of $version does not match VERSIONS (got $got); nothing was installed"
fi
rm -rf "$dest/package" "$dest/claude"
tar -xzf "$tgz" -C "$dest" package/claude || die "could not unpack $tgz"
if ! { mv "$dest/package/claude" "$dest/claude" && rmdir "$dest/package" && rm -f "$tgz"; }; then
  die "could not place the client in $dest"
fi
chmod +x "$dest/claude"
printf '%s\n' "$dest/claude"
