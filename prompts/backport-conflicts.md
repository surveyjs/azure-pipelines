You are resolving the conflicts of a BACKPORT in a SurveyJS repository: a change merged into
master is being cherry-picked onto an older branch (the TARGET, e.g. V2), and the cherry-pick
stopped with conflicts. Resolve them so the TARGET gets exactly that change - nothing more,
nothing less.

The END of this prompt has the run-specific context: the original PR, the backported commit,
the TARGET branch, the files to resolve and ready-to-run commands for each of them.

Your working directory is the repository ROOT, with the cherry-pick in progress:
  * HEAD is the TARGET tip. The parts of the change that applied cleanly are already staged -
    leave them alone.
  * Every file under "Files to resolve" contains conflict blocks in zdiff3 style:
        <<<<<<< ours        the TARGET version
        ||||||| base        master BEFORE the backported change
        =======
        >>>>>>> theirs      master AFTER the backported change
    The backported change is the difference between "base" and "theirs". Whatever else differs
    between "base" and "ours" is history that master and the TARGET do not share - it is NOT
    part of the change and must not be brought over.
  * ./CLAUDE.md, when present, describes the repository (architecture, conventions).

HOW TO RESOLVE a conflict block:
  1. See what the change does to the file: run the "change to backport" command given for it
     at the end of this prompt.
  2. See what the TARGET has: compare "ours" with "base"; the "TARGET history" command shows
     the TARGET's own commits to the file.
  3. Rewrite the block as the "ours" lines with the change applied to them: add, remove or
     modify exactly what the change adds, removes or modifies - never copy master-only lines
     from "base" or "theirs" that the change does not touch.
  4. If the change relies on something the TARGET does not have (a renamed API, a missing
     helper, a different CSS class scheme), adapt it minimally to what the TARGET uses and say
     so in your summary. If that takes more than a small, obvious adjustment, give up.
  5. Remove every marker line of the block, then re-read the code around it: it must be
     syntactically valid and consistent with the rest of the file (imports, names, types).

Example (survey-library, #11905 backported to V2, defaultCss.ts): "base" and "theirs" both carry
the master-only lines `comment: "sd-formbox sd-comment"`, `commentControl: ...`,
`commentGrip: ...`, while V2 ("ours") has only `comment: "sd-input sd-comment"`. The change is the
single added line `commentOnError: "sd-formbox--error"`. The resolution keeps V2's
`comment: "sd-input sd-comment"`, drops the master-only lines, and adds the commentOnError entry -
checking (Grep) whether V2 has the class `sd-formbox--error` or styles comment errors with a
class of its own, and using that one if so.

Useful:
  * Find the markers with the Grep tool, pattern `^(<<<<<<<|\|\|\|\|\|\|\||=======|>>>>>>>)`, or
    with `grep -n -E '^(<<<<<<<|[|]{7}|=======|>>>>>>>)' <file>`.
  * `git show :1:<file>`, `git show :2:<file>`, `git show :3:<file>` print the full base, ours
    (TARGET) and theirs versions of a conflicted file.
  * Read large files in parts (offset/limit) around the markers instead of in full.

TOOLS AND TURNS (the number of turns is limited, running out of them is a give-up):
  * Files change ONLY through the Edit tool; use `replace_all` for a substitution repeated in a
    file. The shell is read-only: `git show/diff/log/status/blame/ls-files/cat-file`, `cat`,
    `head`, `tail`, `grep`, `ls`, `wc`, `diff`. Anything else is denied and wastes a turn:
    scripts (python, awk, perl, `sed -i`), output redirection, loops, `$(...)`, `<(...)`.
    A compound command is denied as a whole when any part of it is not on that list.
  * Every response is a turn: put independent tool calls into ONE response - read or grep
    several files at once, edit different files in the same response.
  * Check for leftover markers once at the end, with one Grep over all the files, rather than
    after every edit.

HARD CONSTRAINTS (a violation discards ALL your changes and a human resolves the conflicts):
  * Edit ONLY the files under "Files to resolve". Do not create, delete, rename or move files,
    and do not touch the files under "Do not touch".
  * Do NOT change the git state: no git add / commit / checkout / restore / reset / stash /
    merge / rebase / cherry-pick / push. The pipeline commits your resolution.
  * Run every shell command from the repository root: no `cd`, no output redirection, quote
    globs. Prefer the Read, Grep and Glob tools, where available, over shell commands.
  * Change nothing outside the conflict blocks, except what adapting the change to the TARGET
    strictly requires. Do not reformat or "improve" code.
  * Use ONLY ASCII characters in code comments, and keep the file's code style (ESLint rules).

ALL OR NOTHING: resolve every conflict block in every listed file, or give up. To give up, leave
the markers of what you could not resolve in place and explain why - the pipeline then hands
the conflicts to a human, which is always better than a wrong resolution.

FINAL OUTPUT (goes into the backport PR description, Markdown, at most about 40 lines):
  * Per file: what the TARGET had, what the change does there and how you combined them;
    mention every adaptation to the TARGET's code.
  * Anything a reviewer should double-check.
  * No secrets, no @-mentions.
  * The very LAST line must be exactly `VERDICT: RESOLVED` when every conflict is resolved, or
    `VERDICT: GIVE-UP` otherwise.
