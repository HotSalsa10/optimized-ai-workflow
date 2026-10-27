# TESTS

Every check in this repo, and what runs it. What exists is not the same as what runs, so each row names its runner.

A check that has not been seen to fail is untested (M041). Every check below has a planted defect in `tests/plants/` that must turn it red for its stated reason, and the same check must stay green on a clean copy. Plants run in a throwaway copy of the repo, never in the working tree, so no plant can be left behind and no real work can be lost.

| Check | What it catches | Run by | Planted defect |
|---|---|---|---|
| `scripts/dev/check-line-endings.sh` | A tracked text file with CRLF line endings (allowed only for .cmd and .bat) | `scripts/dev/validate.sh`; CI on every change | a committed shell script with CRLF endings |
| `scripts/dev/lint-portability.sh` | bash 4+ features that break on macOS bash 3.2, and GNU-only tool flags that break on macOS and BSD | `scripts/dev/validate.sh`; CI | `declare -A` in a script; `sed -i` in a script |
| `scripts/dev/scan-secrets.sh` | API keys, tokens, private keys, and personal data such as personal emails, phone numbers and bank account numbers | `scripts/dev/validate.sh`; CI | a fake API key; a fake personal email |
| `scripts/dev/check-rule-map.sh` | A rule marked done whose ID is missing from its home file | `scripts/dev/validate.sh`; CI | a rule marked done with no ID in its home |
| shellcheck | Shell mistakes such as unquoted variables and missing error handling | `scripts/dev/validate.sh` (required in CI on Linux, reported as SKIPPED where it is not installed) | a script with an unchecked `cd` |
| `tests/run.sh` | Runs every test and plant and prints a count of passes, failures and skips | CI on every change | n/a |

## Where CI runs

- Linux: every push and pull request.
- Windows (Git Bash) and macOS: release tags and manual runs (decision A19).

## Running locally

```
bash scripts/dev/validate.sh
bash tests/run.sh
```
