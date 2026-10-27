# TESTS

Every check in this repo, and what runs it. What exists is not the same as what runs, so each row names its runner.

A check that has not been seen to fail is untested (M041). Every check below has planted defects in `tests/plants/dev-checks.sh` that must turn it red for its stated reason, and each check must stay green on a clean copy. Some checks also have a "looks close but is fine" case that must stay green, so a rule that fires too widely is caught too. Plants run in a throwaway copy of the repo, never in the working tree, so no plant can be left behind and no real work can be lost. Each plant that changes a file first confirms the change really landed before the check is run.

| Check | What it catches | Run by | Planted defects (red) and look-alikes (green) |
|---|---|---|---|
| `scripts/dev/check-line-endings.sh` | A tracked text file with CRLF line endings, in the working tree or committed to the index (what a fresh clone gets). Only .cmd and .bat may use CRLF. Examining nothing is a failure. | `validate.sh`; CI | red: CRLF in the working tree; CRLF committed to the index; a repo with nothing to examine |
| `scripts/dev/lint-portability.sh` (rules in `scripts/dev/lib/portability.pl`) | An early warning, not a shell parser (see Known limits). It flags bash 4+ features that break on macOS bash 3.2; a `$( )` that runs onto the next line, or holds a here-doc or a case statement (bash 3.2 reads `$( )` by matching brackets and quotes, so these can break it); GNU-only flags among a command's options, also inside `$( )` and backticks; and commands missing on macOS where a command starts. | `validate.sh`; CI | red: an associative array; in-place sed after another flag; a here-doc inside `$( )`; the `-v` test; a corpus of 37 forms in `tests/plants/fixtures/portability-corpus.txt`, each of which must be reported on its own line. green: valid code that looks close to the rules; the corpus's 35 other lines, among them here-strings, arithmetic shifts, the word "case" inside a string and a YAML line in a here-doc, none of which may be reported |
| `scripts/dev/scan-secrets.sh` (rules in `scripts/dev/lib/secrets.pl`) | API keys and tokens, private keys, credentials in code (also in longer names such as DB_PASSWORD) and in env files, personal email addresses, phone numbers in international format, bank account numbers (IBANs that pass their checksum). UTF-16 files, with or without a byte-order mark, are decoded first. Binary files are searched for keys and tokens only, and the pass line names them. Matches are shown masked. | `validate.sh`; CI | red: an API key (and the output masks it); a credential in a longer name; an env-style credential; a personal email; 4 personal emails at domains that end like file names (.md, .py, .rs, .sh); a phone number in short groups; an IBAN followed by more text; a key in a UTF-16LE file with a byte-order mark; a key in a UTF-16BE file without one; a key in a file that one NUL byte makes look binary. green: image names with @2x, git@host URLs, package@version names, a short number, noreply and example.com addresses, scores and dates, a +0 score change and a map coordinate, settings whose value is a path (apiKeyHelper, a key path, a key file), uppercase file hashes; a clean binary file, which the pass line must name |
| `scripts/dev/check-rule-map.sh` (rules in `scripts/dev/lib/rule-map.pl`) | A malformed or duplicate rule row (a row that starts with spaces is still read); a rule marked done whose home is missing, is the rule map itself (also written as `./docs/rule-map.md`), or does not contain the rule's ID | `validate.sh`; CI | red: a done rule missing from its home; a done rule whose home does not exist; a malformed rule ID; a bad row that starts with a space; a rule homed in the rule map itself, written plainly and with `./` |
| `scripts/dev/lint-workflows.sh` (rules in `scripts/dev/lib/workflows.pl`) | An action not pinned to a full commit SHA; no top-level `permissions:`; `write-all` in any `permissions:` line, top-level or in a job, quoted or not; a job without `timeout-minutes` (at any indentation, also when the job's key line ends in a comment) | `validate.sh`; CI | red: an action pinned by tag; a job without a timeout (2-space and 4-space indentation, and a commented key line); no permissions; write-all permissions at the top level, in quotes and on one job |
| perl syntax (inside `validate.sh`) | A perl helper that does not compile | `validate.sh`; CI | red: a perl file with a syntax error |
| shellcheck (inside `validate.sh`, default severity) | Shell mistakes, including an unchecked `cd` and unquoted variables | `validate.sh` (required in CI on Linux; reported as SKIPPED, not a pass, where shellcheck is not installed) | red: an unchecked `cd`; an unquoted variable |
| `tests/run.sh` | Runs every test and plant file and counts passes and failures | CI on every change | n/a |

## Known limits

- The secret scan checks the files at the current commit, not git history. A secret added and removed within one push is not seen. A history scan is planned for Release 2.
- The portability lint is an early warning. It reads one line at a time and treats here-doc text as code, so it can miss a form split across lines and can flag text inside a here-doc. The real proof that the scripts run on bash 3.2 and BSD tools is the test suite on macOS, and on Git Bash it is the Windows run. Both run only on release tags and by hand (decision A19), and neither has run yet (RISKS #9).
- No local bash 3.2 was available, so bash 3.2 behaviour has not been seen here.
- In binary files the secret scan looks for keys and tokens, not for email addresses, phone numbers or IBANs.

## Where CI runs

- Linux: every push and pull request.
- Windows (Git Bash) and macOS: release tags and manual runs (decision A19).

## Running locally

```
bash scripts/dev/validate.sh
bash tests/run.sh
```
