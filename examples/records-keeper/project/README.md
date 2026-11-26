# Records keeper

A ledger of items and their amounts (ledger.csv, amounts in whole cents),
checked by scripts/check-ledger.sh, and a script that posts its rows to
the live ledger, scripts/post-rows.sh. exports/ keeps an old export as a
spreadsheet program wrote it. All items are invented.

- Check the ledger: `bash scripts/check-ledger.sh`
- Post the rows: `bash scripts/post-rows.sh --reason "why"` (a dry run;
  add `--live` to write)
