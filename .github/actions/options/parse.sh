#!/usr/bin/env bash
# Port of templates/utils/pr_title_parser.yml + commit_message_parser.yml (keep in sync while they
# live). Usage (env): PR_NUMBER, HEAD_REPOSITORY (the PR head's owner/name), PR_TITLE_FILE,
# COMMIT_MESSAGE_FILE, GITHUB_REPOSITORY, GITHUB_OUTPUT, GITHUB_STEP_SUMMARY.
#
# Writes the outputs pr_tags, commit_tags (JSON objects) and scr_update, plus a "Linked pull
# requests" job summary when the title has tags. The title and the message are attacker-controlled
# on fork PRs: they come in through files and are printed with workflow commands switched off.
# Companion PR tags (LIBRARY, CREATOR, ANALYTICS, PDF, ADAPTERS) must be PR numbers - anything else
# fails the step: the test jobs would otherwise test the target branch and go green on wrong code.
set -uo pipefail

TITLE="$(cat "$PR_TITLE_FILE" 2>/dev/null || true)"
COMMIT_MESSAGE="$(cat "$COMMIT_MESSAGE_FILE" 2>/dev/null || true)"

# Prints untrusted text with workflow commands switched off: a "::set-output" or "::error::" line
# in a commit message is shown, not executed.
print_untrusted() {
  local stop
  stop="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
  echo "::stop-commands::$stop"
  printf '%s\n' "$1"
  echo "::$stop::"
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Every tag of $1 as a "NAME<TAB>VALUE" line. $2 = title: only [name: value] tags;
# $2 = commit: a bare [name] counts too, with the value "true".
tags() {
  local tag name value
  while IFS= read -r tag; do
    tag="${tag:1:${#tag}-2}"
    if [[ "$tag" == *:* ]]; then
      name="$(trim "${tag%%:*}")"
      value="$(trim "${tag#*:}")"
    elif [ "$2" = commit ]; then
      name="$(trim "$tag")"
      value=true
    else
      continue
    fi
    name="${name^^}"
    [[ "$name" =~ ^[A-Z_]+$ ]] || continue
    [ -n "$value" ] || continue
    printf '%s\t%s\n' "$name" "$value"
  done < <(printf '%s\n' "$1" | grep -oE '\[[^][]+\]' || true)
}

to_json() {
  local json='{}' name value
  while IFS=$'\t' read -r name value; do
    [ -n "$name" ] || continue
    json="$(jq -c --arg k "$name" --arg v "$value" '. + {($k): $v}' <<< "$json")"
  done
  printf '%s' "$json"
}

PR_TAGS="$(tags "$TITLE" title | to_json)"
COMMIT_TAGS="$(tags "$COMMIT_MESSAGE" commit | to_json)"
SCR_UPDATE="$(jq -r '.SCR_UPDATE // ""' <<< "$COMMIT_TAGS")"

if [ -n "$TITLE" ]; then
  echo "PR title:"
  print_untrusted "$TITLE"
fi
if [ -n "$COMMIT_MESSAGE" ]; then
  echo "Commit message:"
  print_untrusted "$COMMIT_MESSAGE"
fi
echo "PR title tags: $PR_TAGS"
echo "Commit tags: $COMMIT_TAGS"

STATUS=0
for KEY in LIBRARY CREATOR ANALYTICS PDF ADAPTERS; do
  VALUE="$(jq -r --arg k "$KEY" '.[$k] // ""' <<< "$PR_TAGS")"
  if [ -n "$VALUE" ] && ! [[ "$VALUE" =~ ^[0-9]+$ ]]; then
    echo "::error::The [$KEY: ...] tag in the PR title must be a pull request number"
    STATUS=1
  fi
done

# [scr_update] skips every test job and leaves only SCR Update, which pushes back to the PR branch
# and so runs for PRs from this repository only. On a fork PR nothing would run at all and the
# result would be green - fail here instead, with the reason.
if [ -n "$SCR_UPDATE" ] && [ -n "${PR_NUMBER:-}" ] && [ "${HEAD_REPOSITORY:-}" != "$GITHUB_REPOSITORY" ]; then
  echo "::error::[scr_update] only works on pull requests from $GITHUB_REPOSITORY - push the branch there or drop the tag"
  STATUS=1
fi

{
  echo "pr_tags=$PR_TAGS"
  echo "commit_tags=$COMMIT_TAGS"
  echo "scr_update=$SCR_UPDATE"
} >> "$GITHUB_OUTPUT"

if [ "$PR_TAGS" != '{}' ]; then
  {
    echo "## Linked pull requests"
    echo ""
    echo "Triggered by [$GITHUB_REPOSITORY#$PR_NUMBER](https://github.com/$GITHUB_REPOSITORY/pull/$PR_NUMBER) \`$TITLE\`"
    echo ""
    jq -r 'to_entries[] | [.key, .value] | @tsv' <<< "$PR_TAGS" | while IFS=$'\t' read -r NAME VALUE; do
      case "$NAME" in
        LIBRARY) REPO=surveyjs/survey-library ;;
        CREATOR) REPO=surveyjs/survey-creator ;;
        ANALYTICS) REPO=surveyjs/survey-analytics ;;
        PDF) REPO=surveyjs/survey-pdf ;;
        ADAPTERS) REPO=surveyjs/theme-adapter-demos ;;
        *) REPO="" ;;
      esac
      if [ -n "$REPO" ] && [[ "$VALUE" =~ ^[0-9]+$ ]]; then
        echo "- **$NAME** — [$REPO#$VALUE](https://github.com/$REPO/pull/$VALUE)"
      else
        echo "- **$NAME** — \`$VALUE\`"
      fi
    done
  } >> "$GITHUB_STEP_SUMMARY"
fi
exit "$STATUS"
