#!/usr/bin/env bash
# Tests that .gitignore keeps local settings and common credential files out
# of commits, in any folder, while the files the repo needs stay tracked.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh" || {
  echo "tests: cannot load tests/lib.sh; stopping before anything runs"
  exit 1
}

echo "tests: .gitignore"

must_ignore="sub/.claude/settings.local.json .claude/settings.local.json prod.env .envrc .env.local cert.pem server.key store.p12 store.pfx id_rsa id_ed25519 .npmrc .netrc .pypirc .git-credentials credentials-prod.json .credentials.json client_secret_web.json my-service-account-key.json .aws/credentials prod.tfvars terraform.tfstate terraform.tfstate.backup id_dsa app.jks app.keystore key.ppk .pgpass .vault-token .docker/config.json .kube/config kubeconfig"
must_keep=".env.example planted.env.example scripts/dev/scan-secrets.sh .claude/settings.json prod.tfvars.example"

# ignore_problems DIR: prints each path whose ignore status in DIR is wrong.
ignore_problems() {
  for p in $must_ignore; do
    (cd "$1" && git check-ignore -q --no-index -- "$p") || echo "not ignored: $p"
  done
  for p in $must_keep; do
    (cd "$1" && git check-ignore -q --no-index -- "$p") && echo "ignored but needed: $p"
  done
}

# 1. the repo's .gitignore
problems=$(ignore_problems "$(repo_root)")
if [ -z "$problems" ]; then
  pass ".gitignore ignores local settings and credential files in any folder, and keeps what the repo needs"
else
  fail ".gitignore ignores local settings and credential files in any folder, and keeps what the repo needs" "$problems"
fi

# 2. the test goes red when local settings are ignored at the root only
sb=$(make_sandbox) || abort_sandbox
perl -pi -e 's{^\*\*/\.claude/settings\.local\.json$}{.claude/settings.local.json}' "$sb/.gitignore"
if grep -q '^\.claude/settings\.local\.json$' "$sb/.gitignore"; then
  case "$(ignore_problems "$sb")" in
    *"not ignored: sub/.claude/settings.local.json"*) pass "the test goes red when local settings are ignored at the root only" ;;
    *) fail "the test goes red when local settings are ignored at the root only" ;;
  esac
else
  fail "the root-only plant did not apply, so the result would mean nothing"
fi
drop_sandbox "$sb"

echo "tests: .gitignore: $tests_pass passed, $tests_fail failed, $tests_skip skipped"
[ "$tests_fail" -eq 0 ]
