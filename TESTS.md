# TESTS

Every check in this repo, and what runs it. What exists is not the same as what runs, so each row names its runner.

A check that has not been seen to fail is untested (M041). Every check below has planted defects in `tests/plants/dev-checks.sh` that must turn it red for its stated reason, and each check must stay green on a clean copy. Some checks also have a "looks close but is fine" case that must stay green, so a rule that fires too widely is caught too. Plants run in a throwaway copy of the repo, never in the working tree, so no plant can be left behind and no real work can be lost. Each plant first confirms it really landed in the file before the check is run.

| Check | What it catches | Run by | Planted defects (red) and look-alikes (green) |
|---|---|---|---|
| `scripts/dev/check-line-endings.sh` | A tracked text file with CRLF line endings, in the working tree or committed to the index (what a fresh clone gets). Only .cmd and .bat may use CRLF. Examining nothing is a failure. | `validate.sh`; CI | red: CRLF in the working tree; CRLF committed to the index; a repo with nothing to examine |
| `scripts/dev/lint-portability.sh` (rules in `scripts/dev/lib/portability.pl`) | bash 4+ features that break on macOS bash 3.2, constructs the bash 3.2 parser gets wrong (a here-doc or a case statement inside `$( )`), GNU-only tool flags wherever they appear among the options, and commands missing on macOS | `validate.sh`; CI | red: an associative array; in-place sed after another flag; a here-doc inside `$( )`; the `-v` test. green: valid code that looks close to the rules |
| `scripts/dev/scan-secrets.sh` (rules in `scripts/dev/lib/secrets.pl`) | API keys and tokens, private keys, credentials in code (also in longer names such as DB_PASSWORD) and in env files, personal email addresses, phone numbers in international format, bank account numbers (IBANs that pass their checksum). UTF-16 files are decoded first. Binary files are skipped and named. Matches are shown masked. | `validate.sh`; CI | red: an API key (and the output masks it); a credential in a longer name; an env-style credential; a personal email; a phone number in short groups; an IBAN followed by more text; a key in a UTF-16 file. green: image names with @2x, git@host URLs, package@version names, a short number, noreply and example.com addresses, scores and dates |
| `scripts/dev/check-rule-map.sh` (rules in `scripts/dev/lib/rule-map.pl`) | A malformed or duplicate rule row; a rule marked done whose home is missing, is the rule map itself, or does not contain the rule's ID | `validate.sh`; CI | red: a done rule missing from its home; a done rule whose home does not exist; a malformed rule ID; a rule homed in the rule map itself |
| `scripts/dev/lint-workflows.sh` (rules in `scripts/dev/lib/workflows.pl`) | An action not pinned to a full commit SHA; no top-level `permissions:` or `write-all`; a job without `timeout-minutes` (at any indentation) | `validate.sh`; CI | red: an action pinned by tag; a job without a timeout (2-space and 4-space indentation); no permissions; write-all permissions |
| perl syntax (inside `validate.sh`) | A perl helper that does not compile | `validate.sh`; CI | red: a perl file with a syntax error |
| shellcheck (inside `validate.sh`, default severity) | Shell mistakes, including an unchecked `cd` and unquoted variables | `validate.sh` (required in CI on Linux; reported as SKIPPED, not a pass, where shellcheck is not installed) | red: an unchecked `cd`; an unquoted variable |
| `tests/run.sh` | Runs every test and plant file and counts passes and failures | CI on every change | n/a |

## Known limits

- The secret scan checks the files at the current commit, not git history. A secret added and removed within one push is not seen. A history scan is planned for Release 2.
- bash 3.2 behaviour is checked by rules and by the macOS CI run, not by a local bash 3.2.

## Where CI runs

- Linux: every push and pull request.
- Windows (Git Bash) and macOS: release tags and manual runs (decision A19).

## Running locally

```
bash scripts/dev/validate.sh
bash tests/run.sh
```
