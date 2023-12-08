# Api interface schema

## What is this?

- How we store the performance data, and query subsets of performance tests to run.

## Storage approach:

- We leverage Sqlite and version it with Github Artifacts (good for 90 days). The database itself is stored as a .sqlite file, in the sqlite branch.
- Each time we make an update to the database, we make a new git commit to the sqlite branch with the updated file, and overwrite its history.

## Sqlite Schema:

[ image in sqlite studio ]


## Netperf API:

TBD.
