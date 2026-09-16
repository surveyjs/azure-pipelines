all azure pipelines templates for SurveyJS

## Companion PR checkout

A pipeline run for one repo often has to build a matching, not-yet-merged change in another one.
Tag the triggering PR's title with the companion PR number:

    Add the new question type [library: 1234]

`templates/utils/pr_title_parser.yml` turns every `[name: value]` tag into an output variable, and
each stage maps it onto the variable its build template reads - `LIBRARY_PR`, `CREATOR_PR`, or `PR`
for whichever repo is checked out instead of `self` (see `creator.yml`, `library.yml`).

The build templates then check the companion out at **`pull/<N>/merge`** - the PR already merged
into its base branch - not at `pull/<N>/head`, the PR branch tip. This mirrors what the agent does
for `self`: a PR validation build gets `refs/pull/<N>/merge`, so the repo under test already
contains everything that landed on the base branch after the PR forked. A companion pinned to its
branch tip would not, and an API that is already on master then reads as missing, failing the build
on code that is in fact merged on both sides.

GitHub drops the `/merge` ref while a PR conflicts with its base (and briefly while it recomputes
mergeability). The step then falls back to `pull/<N>/head` and raises the build warning
`pull/<N>/merge is unavailable`. A build carrying that warning was tested against a stale base -
rebase or fix the conflicts in the companion PR and re-run.

Without a tag the companion comes from `resources.repositories[*].ref: $(branch)`
(`templates/utils/variables.yml`), i.e. the tip of the branch the triggering PR targets.
