## What and why

<!-- One paragraph: the problem, the change, the outcome. -->

## How it was verified

<!-- Commands run and what they showed. -->

## Checklist

- [ ] `/review` ran on the head commit and `bash scripts/ai-review.sh mark` posted the `ai-review` status
- [ ] `bash scripts/obligations.sh` shows nothing owed (docs pages, markers, required skills)
- [ ] The `internal-docs/` pages for the touched code are updated in the same commits
- [ ] `bash scripts/lifecycle-suite.sh` (auth or users changed) / `bash scripts/deps-smoke.sh` (a manifest changed), if the PR gate asked
