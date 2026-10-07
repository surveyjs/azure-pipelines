# Перенос library.yml на GitHub Actions — подпроект A: эталонный перенос тестовой части

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** перенести тестовую часть `library.yml` (Lint, Options, 13 тестовых стадий, итоговый check) на GitHub Actions один к одному и запустить её из survey-library в теневом режиме.

**Architecture:**
- Общие шаги Azure-шаблонов становятся composite actions в `surveyjs/azure-pipelines/.github/actions/`. Логика вынесена в `.sh`-скрипты, их покрывают тесты на bash.
- Каждый Azure `test.yml` становится reusable workflow в `.github/workflows/`.
- Оркестратор `.github/workflows/library.yml` повторяет граф стадий Azure и заканчивается джобом `result`.
- В survey-library появляется тонкий вызывающий workflow.
- Кэша, Staging и Backport в этом подпроекте нет: это подпроекты D, B и C.

**Tech Stack:**
- GitHub Actions: `workflow_call`, composite actions;
- bash 5, jq, git;
- actionlint;
- actions/checkout@v5, actions/setup-node@v5, actions/upload-artifact@v4, mikepenz/action-junit-report@v5.

**Spec:** [docs/superpowers/specs/2026-10-06-library-gha-migration-design.md](../specs/2026-10-06-library-gha-migration-design.md)

## Global Constraints

**Раннеры и шаги:**
- Раннер: `runs-on: ubuntu-24.04`.
- В вызываемых workflow: `timeout-minutes: 60` у тестовых джобов.
- Shell в workflow: `defaults.run.shell: bash --noprofile --norc {0}`.
- Shell в шагах composite actions: `shell: bash --noprofile --norc {0}`.
- `actions/checkout` всегда с `persist-credentials: false` и `fetch-depth: 1`.

**Секреты и ссылки:**
- Секрет: `SURVEYJS_BOT_TOKEN` (PAT). В actions он передаётся input'ом `token`, внутри скриптов экспортируется как env `GITHUB_TOKEN`. Секретов с именами `GITHUB_*` нет.
- Внутренние ссылки: `surveyjs/azure-pipelines/.github/actions/<name>@gha-migration` и `surveyjs/azure-pipelines/.github/workflows/<name>.yml@gha-migration`. Переход на `@main` — подпроект E.

**Совместимость с Azure:**
- Имена артефактов совпадают с Azure (`Library_React_E2E`, `SurveyJSLibraryBuildCore`, …).
- Метку `[azurepipelines skip]` не меняем на `[skip ci]`.
- Шаги, которые пишут в репозитории, оставляем закомментированными строкой `# SHADOW-OFF: <команда>`. Чтобы включить такой шаг, достаточно удалить префикс `# SHADOW-OFF: `.

**Безопасность:**
- Недоверенный текст (заголовок PR, сообщение коммита, значения тегов) попадает в `run:` только через `env`, никогда через `${{ }}`.

**Окружение:**
- `npm install` всегда выполняется с `PUPPETEER_SKIP_DOWNLOAD=true`.
- Node: input `node-version` action'а `npm-install`, по умолчанию `"22"`. Если инвентаризация (Task 0) показала другую мажорную версию на агентах Azure, ставим её.
- Кэша нет: это подпроект D.

**Коммиты** делает пользователь. Задачи оставляют изменения незакоммиченными.

## Review Focus

1. **Тег с пробелами или в другом регистре** (`[Creator : 12 ]`) должен разобраться как `CREATOR=12`. Тест в Task 3.
2. **Строки `::error::` и `::set-output` в сообщении коммита** должны напечататься, но не выполниться и не изменить выходы. Тест в Task 3.
3. **Companion PR без merge-ref** (конфликтует с базой) должен откатиться на `pull/N/head` с warning, а не уронить сборку. Тест в Task 2.
4. **Упавший options при пропущенных тестах** должен давать красный `result`. Без этого check выходит ложно-зелёным. Тест в Task 1.
5. **Push-прогон, где options нет:** тесты должны идти с пустыми тегами без ошибки `fromJSON('')`. Локально это не проверить, поэтому это сценарий 8 в Task 11.

---

### Task 0: Инвентаризация и подготовка (выполняет человек)

**Files:**
- Create: `docs/superpowers/notes/2026-10-06-azure-library-inventory.md`

**Interfaces:**
- Produces: `NODE_MAJOR` (используется в Task 4), список триггеров (Task 11), медиана и 90-й перцентиль времени PR-прогонов Azure (подпроект D).

- [ ] **Step 1: Снять настройки Azure.** В Azure DevOps: Pipelines → Library → Edit → ⋮ → Triggers. Записать в файл инвентаризации:
  - ветки и пути CI-триггера;
  - ветки PR-триггера;
  - «Build pull requests from forks», «Make secrets available to builds of forks»;
  - сборку draft PR;
  - «Batch changes while a build is in progress».

  Затем Variables: UI-переменные пайплайна.
- [ ] **Step 2: Узнать версию Node на агентах.** Organization settings → Agent pools → пул пайплайна Library → Agents → любой агент → Capabilities: значение `node`/`Node.js`. Записать как `NODE_MAJOR`.
- [ ] **Step 3: Снять время прогонов.** Pipelines → Library → Analytics → Pipeline duration, PR-сборки за 14 дней. Записать медиану и 90-й перцентиль.
- [ ] **Step 4: Завести секрет в GitHub.** Org settings → Secrets and variables → Actions: секрет `SURVEYJS_BOT_TOKEN` со значением `GITHUB_TOKEN` из variable group `pipeline-secrets` (PAT surveyjsdeveloper). Доступ — репозиторию `surveyjs/survey-library`.
- [ ] **Step 5: Настроить Actions в организации.** Org settings → Actions → General:
  - разрешить actions из `surveyjs/*`, `actions/*` и `mikepenz/action-junit-report@*`;
  - «Fork pull request workflows from outside collaborators»: «Require approval for first-time contributors».
- [ ] **Step 6: Создать ветку** `gha-migration` в azure-pipelines от `main`: `git switch -c gha-migration`. Все остальные задачи выполняются в ней.

---

### Task 1: Тестовый каркас, CI репозитория и action `result`

**Files:**
- Create: `tests/lib.sh`, `tests/run.sh`, `tests/result.test.sh`
- Create: `.github/actions/result/action.yml`, `.github/actions/result/check.sh`
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Produces:
  - `tests/lib.sh`: `assert_eq <name> <expected> <actual>`, `assert_contains <name> <haystack> <needle>`, `assert_not_contains <name> <haystack> <needle>`, `assert_fails <name> <status>`, `finish`.
  - Action `result`: input `needs` (строка `toJSON(needs)`). Падает, если у какого-либо джоба результат `failure` или `cancelled`.
  - `ci.yml`: джобы `unit`, `actionlint`, `smoke`. Задачи 2–5 добавляют шаги в `smoke`.

- [ ] **Step 1: Проверить инструменты.**

Run: `jq --version && git --version`.
Expected: обе версии напечатаны. Если `jq` нет, выполнить `winget install --id jqlang.jq -e` и открыть новый Git Bash.

- [ ] **Step 2: Написать тестовый каркас.**

`tests/lib.sh`:
```bash
# Assertion helpers for tests/*.test.sh. Sourced from the repository root (tests/run.sh cd's
# there). Every test file calls `finish` last: it exits non-zero when an assertion failed.

FAILURES=0

pass() { printf '  ok    %s\n' "$1"; }

fail() {
  printf '  FAIL  %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

# assert_eq <name> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then
    pass "$1"
  else
    fail "$1"
    printf '        expected: %s\n        actual:   %s\n' "$2" "$3"
  fi
}

# assert_contains <name> <haystack> <needle>
assert_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1"; printf '        missing: %s\n        in:      %s\n' "$3" "$2" ;;
  esac
}

# assert_not_contains <name> <haystack> <needle>
assert_not_contains() {
  case "$2" in
    *"$3"*) fail "$1"; printf '        unexpected: %s\n' "$3" ;;
    *) pass "$1" ;;
  esac
}

# assert_fails <name> <exit status>
assert_fails() {
  if [ "$2" -ne 0 ]; then
    pass "$1"
  else
    fail "$1"
    printf '        expected a non-zero exit status\n'
  fi
}

finish() {
  if [ "$FAILURES" -eq 0 ]; then exit 0; fi
  printf '%s assertion(s) failed\n' "$FAILURES"
  exit 1
}
```

`tests/run.sh`:
```bash
#!/usr/bin/env bash
# Runs every tests/*.test.sh from the repository root. Needs bash, git and jq
# (Windows: `winget install --id jqlang.jq -e`; the GitHub runners have all three).
cd "$(dirname "$0")/.." || exit 2
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git is required"; exit 2; }

STATUS=0
for T in tests/*.test.sh; do
  echo "== $T"
  bash "$T" || STATUS=1
done
exit "$STATUS"
```

- [ ] **Step 3: Написать падающий тест `tests/result.test.sh`.**

```bash
# Tests of .github/actions/result/check.sh - the single required status check.
source tests/lib.sh

run() {
  OUT="$(NEEDS="$1" bash .github/actions/result/check.sh 2>&1)"
  STATUS=$?
}

run '{"lint":{"result":"success"},"options":{"result":"skipped"},"library-core":{"result":"success"}}'
assert_eq "success and skipped pass" 0 "$STATUS"
assert_contains "every job's result is printed" "$OUT" "options: skipped"

run '{"lint":{"result":"success"},"library-core":{"result":"failure"}}'
assert_eq "a failed job fails the check" 1 "$STATUS"
assert_contains "the failed job is named" "$OUT" "::error::library-core=failure"

run '{"options":{"result":"failure"},"library-core":{"result":"skipped"},"creator-core":{"result":"skipped"}}'
assert_eq "a failed options job fails the check although the tests were skipped" 1 "$STATUS"

run '{"creator-react":{"result":"cancelled"}}'
assert_eq "a cancelled job fails the check" 1 "$STATUS"

run '{}'
assert_eq "no needs pass" 0 "$STATUS"

run 'not json'
assert_eq "garbage fails instead of passing" 1 "$STATUS"

finish
```

- [ ] **Step 4: Запустить тест и убедиться, что он падает.**

Run: `bash tests/run.sh`
Expected: `== tests/result.test.sh`, строки `FAIL` (скрипта `check.sh` ещё нет), итоговый код 1.

- [ ] **Step 5: Реализовать action.**

`.github/actions/result/check.sh`:
```bash
#!/usr/bin/env bash
# Usage (env): NEEDS - toJSON(needs) of the calling job.
# Fails when a needed job ended as failure or cancelled. A job skipped by its own condition
# (scr_update, options on a push) is fine. A failed options job is not: it skips every test job,
# and without this check the run would go green having tested nothing.
set -uo pipefail

if ! printf '%s' "$NEEDS" | jq -e 'type == "object"' >/dev/null 2>&1; then
  echo "::error::NEEDS is not a JSON object"
  exit 1
fi

printf '%s' "$NEEDS" | jq -r 'to_entries[] | "\(.key): \(.value.result)"'

BAD="$(printf '%s' "$NEEDS" | jq -r 'to_entries[] | select(.value.result == "failure" or .value.result == "cancelled") | "\(.key)=\(.value.result)"')"
if [ -n "$BAD" ]; then
  while IFS= read -r L; do echo "::error::$L"; done <<< "$BAD"
  exit 1
fi
echo "All jobs succeeded or were skipped by their own conditions."
```

`.github/actions/result/action.yml`:
```yaml
name: Library CI result
description: >
  The single required status check of the library workflow: fails when a job it needs failed or
  was cancelled. A job skipped by its own condition (scr_update, options on a push) is fine.
inputs:
  needs:
    description: toJSON(needs) of the calling job
    required: true
runs:
  using: composite
  steps:
    - shell: bash --noprofile --norc {0}
      env:
        # Through the environment, never interpolated: the needs outputs carry PR-title text.
        NEEDS: ${{ inputs.needs }}
      run: bash "$GITHUB_ACTION_PATH/check.sh"
```

- [ ] **Step 6: Запустить тест и убедиться, что он проходит.**

Run: `bash tests/run.sh`
Expected: в `result.test.sh` все строки `ok`, итоговый код 0.

- [ ] **Step 7: Создать CI репозитория `.github/workflows/ci.yml`.**

```yaml
# CI of this repository: unit tests of the action scripts, actionlint over the workflows, and a
# smoke run of every leaf composite action - the runner validates an action.yml only when it runs
# it, and actionlint does not look into composite actions.
name: CI

on:
  push:
  pull_request:

permissions:
  contents: read

defaults:
  run:
    shell: bash --noprofile --norc {0}

jobs:
  unit:
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v5
        with:
          persist-credentials: false
      - name: Unit tests
        run: bash tests/run.sh

  actionlint:
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v5
        with:
          persist-credentials: false
      - name: actionlint
        run: |
          set -e
          bash <(curl -sSfL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash)
          ./actionlint -color

  smoke:
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v5
        with:
          persist-credentials: false
      - name: result
        uses: ./.github/actions/result
        with:
          needs: '{"lint":{"result":"success"},"options":{"result":"skipped"}}'
```

- [ ] **Step 8: Если запущен Docker Desktop, прогнать actionlint локально.**

Run: `MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W):/repo" -w /repo rhysd/actionlint:latest -color`
Expected: пустой вывод, код 0. Если Docker не запущен, шаг пропускается: actionlint выполнится в `ci.yml` после push.

---

### Task 2: Action `checkout-pr`

**Files:**
- Create: `.github/actions/checkout-pr/action.yml`, `.github/actions/checkout-pr/switch.sh`
- Create: `tests/checkout-pr.test.sh`
- Modify: `.github/workflows/ci.yml` (шаг в `smoke`)

**Interfaces:**
- Consumes: `tests/lib.sh` (Task 1).
- Produces: action `checkout-pr` с inputs:
  - `pr` — номер или пусто;
  - `path` — каталог репозитория относительно workspace, по умолчанию `.`;
  - `name` — имя для лога, обязательный;
  - `token` — PAT или пусто.

- [ ] **Step 1: Написать падающий тест `tests/checkout-pr.test.sh`.**

```bash
# Tests of .github/actions/checkout-pr/switch.sh against a local remote with GitHub-style
# refs/pull/N/{head,merge} refs.
source tests/lib.sh

TMP="$(mktemp -d)"
GIT=(git -c user.email=test@example.com -c user.name=test -c init.defaultBranch=main)
"${GIT[@]}" init -q --bare "$TMP/remote.git"
"${GIT[@]}" init -q "$TMP/src"
(
  cd "$TMP/src" || exit 1
  "${GIT[@]}" commit -q --allow-empty -m base
  "${GIT[@]}" push -q "$TMP/remote.git" main
  "${GIT[@]}" switch -q -c feature
  "${GIT[@]}" commit -q --allow-empty -m "pr head"
  "${GIT[@]}" switch -q main
  "${GIT[@]}" merge -q --no-ff -m "pr merge" feature
  # PR 1 has both refs; PR 2 conflicts with its base, so GitHub keeps no merge ref for it.
  "${GIT[@]}" push -q "$TMP/remote.git" feature:refs/pull/1/head main:refs/pull/1/merge feature:refs/pull/2/head
)
HEAD_SHA="$(git -C "$TMP/src" rev-parse feature)"
MERGE_SHA="$(git -C "$TMP/src" rev-parse main)"

fresh() {
  rm -rf "$TMP/work"
  git clone -q --depth 1 "file://$TMP/remote.git" "$TMP/work" 2>/dev/null
  BASE_SHA="$(git -C "$TMP/work" rev-parse HEAD)"
}
run() {
  OUT="$(PR_NUMBER="$1" REPO_DIR="$TMP/work" REPO_NAME=survey-creator GIT_TOKEN="" \
    bash .github/actions/checkout-pr/switch.sh 2>&1)"
  STATUS=$?
  NOW="$(git -C "$TMP/work" rev-parse HEAD)"
}

fresh; run 1
assert_eq "a PR with a merge ref is checked out at pull/N/merge" "$MERGE_SHA" "$NOW"
assert_contains "and the log says so" "$OUT" "survey-creator PR 1 merged into its base branch"

fresh; run 2
assert_eq "without a merge ref it falls back to pull/N/head" "$HEAD_SHA" "$NOW"
assert_contains "with a warning" "$OUT" "::warning::pull/2/merge is unavailable - survey-creator PR 2"
assert_eq "the fallback is not an error" 0 "$STATUS"

fresh; run ''
assert_eq "no PR leaves the branch tip" "$BASE_SHA" "$NOW"
assert_eq "no PR is not an error" 0 "$STATUS"

fresh; run '1; touch pwned'
assert_eq "a non-numeric PR is rejected" 1 "$STATUS"
assert_eq "before git runs" "$BASE_SHA" "$NOW"
assert_contains "with an error" "$OUT" "::error::Companion PR for survey-creator must be a number"

fresh; run 3
assert_fails "a PR without any ref fails the step" "$STATUS"

rm -rf "$TMP"
finish
```

- [ ] **Step 2: Запустить тест и убедиться, что он падает.**

Run: `bash tests/run.sh`
Expected: в `checkout-pr.test.sh` есть `FAIL` (`switch.sh` не найден), код 1.

- [ ] **Step 3: Реализовать `switch.sh`.**

`.github/actions/checkout-pr/switch.sh`:
```bash
#!/usr/bin/env bash
# Usage (env): PR_NUMBER - companion PR number or empty; REPO_DIR - the repository's directory;
# REPO_NAME - its name for the log; GIT_TOKEN - optional PAT for the fetch.
set -euo pipefail

PR="${PR_NUMBER:-}"
if [ -z "$PR" ]; then
  echo "No companion PR for $REPO_NAME - staying on the branch tip"
  exit 0
fi
# The number comes from a PR title: anything but digits must not reach git.
if ! [[ "$PR" =~ ^[0-9]+$ ]]; then
  echo "::error::Companion PR for $REPO_NAME must be a number"
  exit 1
fi

AUTH=""
if [ -n "${GIT_TOKEN:-}" ]; then
  AUTH="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GIT_TOKEN" | base64 -w0)"
fi
# The header reaches git through the environment only - it never lands in .git/config. An empty
# value keeps the fetch anonymous.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="http.https://github.com/.extraheader" GIT_CONFIG_VALUE_0="$AUTH"

cd "$REPO_DIR"
# pull/N/merge, not /head: the PR already merged into its base, the same shape of ref the workflow
# checks out for its own PR. The branch tip alone misses commits the base got after the PR forked,
# so an API that is already on the base branch reads as missing and the build fails. A missing
# merge ref means the PR conflicts with its base - warn and fall back to the tip rather than fail.
if git fetch --depth=1 origin "pull/$PR/merge"; then
  echo "$REPO_NAME PR $PR merged into its base branch"
else
  echo "::warning::pull/$PR/merge is unavailable - $REPO_NAME PR $PR most likely conflicts with its base branch. Falling back to the PR branch tip: this build does not see commits the base branch got after the PR forked."
  git fetch --depth=1 origin "pull/$PR/head"
fi
git checkout --quiet FETCH_HEAD
echo "$REPO_NAME is at $(git rev-parse HEAD)"
```

- [ ] **Step 4: Запустить тест и убедиться, что он проходит.**

Run: `bash tests/run.sh`
Expected: в `checkout-pr.test.sh` все строки `ok`, код 0.

- [ ] **Step 5: Написать `action.yml`.**

`.github/actions/checkout-pr/action.yml`:
```yaml
name: Switch to the companion PR
description: >
  Port of the "Switch to PR $(PR)" step of templates/*/build.yml (keep in sync while those live).
  Moves the repository at `path` to pull/<pr>/merge, falling back to pull/<pr>/head with a warning
  when GitHub keeps no merge ref (the PR conflicts with its base). No-op when `pr` is empty.
inputs:
  pr:
    description: Companion PR number, or empty
    default: ""
  path:
    description: Repository directory, relative to the workspace
    default: "."
  name:
    description: Repository name for the log
    required: true
  token:
    description: PAT for the fetch; empty fetches anonymously
    default: ""
runs:
  using: composite
  steps:
    - if: inputs.pr != ''
      shell: bash --noprofile --norc {0}
      env:
        PR_NUMBER: ${{ inputs.pr }}
        REPO_DIR: ${{ inputs.path }}
        REPO_NAME: ${{ inputs.name }}
        GIT_TOKEN: ${{ inputs.token }}
      run: bash "$GITHUB_ACTION_PATH/switch.sh"
```

- [ ] **Step 6: Добавить smoke-шаг в конец `steps` джоба `smoke` в `.github/workflows/ci.yml`.**

```yaml
      - name: checkout-pr (no PR - must be a no-op)
        uses: ./.github/actions/checkout-pr
        with:
          name: azure-pipelines
```

---

### Task 3: Action `options`

**Files:**
- Create: `.github/actions/options/action.yml`, `.github/actions/options/fetch.sh`, `.github/actions/options/parse.sh`
- Create: `tests/options.test.sh`
- Modify: `.github/workflows/ci.yml` (шаги в `smoke`)

**Interfaces:**
- Consumes: `tests/lib.sh`.
- Produces: action `options` без inputs, с outputs:
  - `pr_tags` — JSON-объект, как минимум `{}`;
  - `commit_tags` — JSON-объект, как минимум `{}`;
  - `scr_update` — строка, может быть пустой.

  Вне события `pull_request` все outputs пустые: `{}`, `{}`, `""`.

- [ ] **Step 1: Написать падающий тест `tests/options.test.sh`.**

```bash
# Tests of .github/actions/options/parse.sh: the tags of the PR title and of the commit message.
source tests/lib.sh

TMP="$(mktemp -d)"
run() { # <title> <commit message> [pr number, default 42]
  printf '%s' "$1" > "$TMP/title.txt"
  printf '%s' "$2" > "$TMP/commit.txt"
  : > "$TMP/output"
  : > "$TMP/summary"
  OUT="$(PR_NUMBER="${3-42}" PR_TITLE_FILE="$TMP/title.txt" COMMIT_MESSAGE_FILE="$TMP/commit.txt" \
    GITHUB_REPOSITORY=surveyjs/survey-library GITHUB_OUTPUT="$TMP/output" GITHUB_STEP_SUMMARY="$TMP/summary" \
    bash .github/actions/options/parse.sh 2>&1)"
  STATUS=$?
  PR_TAGS="$(sed -n 's/^pr_tags=//p' "$TMP/output")"
  COMMIT_TAGS="$(sed -n 's/^commit_tags=//p' "$TMP/output")"
  SCR_UPDATE="$(sed -n 's/^scr_update=//p' "$TMP/output")"
  SUMMARY="$(cat "$TMP/summary")"
}

run 'Add the new question type [creator: 1234] [adapters: 56]' 'Add the new question type'
assert_eq "title tags become a JSON object" '{"CREATOR":"1234","ADAPTERS":"56"}' "$PR_TAGS"
assert_eq "no commit tags" '{}' "$COMMIT_TAGS"
assert_eq "scr_update is empty without the tag" '' "$SCR_UPDATE"
assert_eq "valid tags pass" 0 "$STATUS"
assert_contains "the summary links the companion PR" "$SUMMARY" '[surveyjs/survey-creator#1234](https://github.com/surveyjs/survey-creator/pull/1234)'

run 'Fix [Creator : 12 ] and [backport: V2]' 'msg'
assert_eq "names are trimmed and upper-cased, non-PR tags stay text" '{"CREATOR":"12","BACKPORT":"V2"}' "$PR_TAGS"

run 'Fix [WIP] [my-tag: 1] [creator: ]' 'msg'
assert_eq "bare, invalid-name and empty-value title tags are skipped" '{}' "$PR_TAGS"
assert_eq "no summary without tags" '' "$SUMMARY"

run 'Update screenshots' $'Update screenshots\n\n[scr_update]'
assert_eq "a bare commit tag is true" '{"SCR_UPDATE":"true"}' "$COMMIT_TAGS"
assert_eq "scr_update comes from the commit message" 'true' "$SCR_UPDATE"

run 'Fix [creator: abc]' 'msg'
assert_eq "a non-numeric companion PR fails the step" 1 "$STATUS"
assert_contains "and names the tag" "$OUT" '::error::The [CREATOR: ...] tag in the PR title must be a pull request number'

run 'Fix' $'msg\n::error::injected\n::set-output name=scr_update::true'
assert_eq "workflow commands in the commit message do not set outputs" '' "$SCR_UPDATE"
TOKEN="$(printf '%s\n' "$OUT" | sed -n 's/^::stop-commands::\(.*\)$/\1/p' | tail -n1)"
STOP_AT="$(printf '%s\n' "$OUT" | grep -n "^::stop-commands::$TOKEN\$" | cut -d: -f1)"
INJECTED_AT="$(printf '%s\n' "$OUT" | grep -n '^::error::injected$' | cut -d: -f1)"
RESUME_AT="$(printf '%s\n' "$OUT" | grep -n "^::$TOKEN::\$" | cut -d: -f1)"
[ -n "$TOKEN" ] && [ "${STOP_AT:-0}" -lt "${INJECTED_AT:-0}" ] && [ "${INJECTED_AT:-0}" -lt "${RESUME_AT:-0}" ]
assert_eq "the commit message is printed between stop-commands and resume" 0 "$?"

run '' '' ''
assert_eq "outside a PR the tags are {}" '{}' "$PR_TAGS"
assert_eq "outside a PR scr_update is empty" '' "$SCR_UPDATE"
assert_eq "outside a PR it passes" 0 "$STATUS"

rm -rf "$TMP"
finish
```

- [ ] **Step 2: Запустить тест и убедиться, что он падает.**

Run: `bash tests/run.sh`
Expected: в `options.test.sh` есть `FAIL`, код 1.

- [ ] **Step 3: Реализовать `parse.sh`.**

`.github/actions/options/parse.sh`:
```bash
#!/usr/bin/env bash
# Port of templates/utils/pr_title_parser.yml + commit_message_parser.yml (keep in sync while they
# live). Usage (env): PR_NUMBER, PR_TITLE_FILE, COMMIT_MESSAGE_FILE, GITHUB_REPOSITORY,
# GITHUB_OUTPUT, GITHUB_STEP_SUMMARY.
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
```

- [ ] **Step 4: Запустить тест и убедиться, что он проходит.**

Run: `bash tests/run.sh`
Expected: в `options.test.sh` все строки `ok`, код 0.

- [ ] **Step 5: Написать `fetch.sh` и `action.yml`.**

`.github/actions/options/fetch.sh`:
```bash
#!/usr/bin/env bash
# Usage (env): GH_TOKEN, PR_NUMBER, HEAD_SHA, GITHUB_API_URL, GITHUB_REPOSITORY, RUNNER_TEMP.
# Fetches the PR title - fresh, so "Re-run all jobs" sees an edited title - and the message of the
# PR's head commit into $RUNNER_TEMP/options/. Both are attacker-controlled text on fork PRs: they
# travel through files, never through ${{ }}. A failed API call is fatal on purpose: the tags
# select the companion PRs, and losing them silently tests the target branch with a green build.
set -uo pipefail

DIR="$RUNNER_TEMP/options"
mkdir -p "$DIR"
: > "$DIR/title.txt"
: > "$DIR/commit.txt"
if [ -z "${PR_NUMBER:-}" ]; then
  echo "Not a pull request - no PR title to parse"
  exit 0
fi

api() {
  curl -sS -f --max-time 30 \
    -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
    "$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/$1"
}
if ! PR_JSON="$(api "pulls/$PR_NUMBER")"; then
  echo "::error::Could not fetch PR #$PR_NUMBER from the GitHub API (see the curl error above). Companion PR tags are unknown, so the test jobs would silently run against the target branch."
  exit 1
fi
if ! COMMIT_JSON="$(api "commits/$HEAD_SHA")"; then
  echo "::error::Could not fetch the PR's head commit from the GitHub API (see the curl error above)."
  exit 1
fi
printf '%s' "$PR_JSON" | jq -r '.title // ""' > "$DIR/title.txt"
printf '%s' "$COMMIT_JSON" | jq -r '.commit.message // ""' > "$DIR/commit.txt"
```

`.github/actions/options/action.yml`:
```yaml
name: Options
description: >
  Port of templates/utils/pr_title_parser.yml + commit_message_parser.yml (keep in sync while
  they live). Exports the [name: value] tags of the PR title and the [name] / [name: value] tags
  of the PR head commit's message. Outside a pull_request event the outputs are {}, {} and "".
outputs:
  pr_tags:
    description: JSON object of the PR title's tags, names upper-cased ({"CREATOR":"1234"})
    value: ${{ steps.parse.outputs.pr_tags }}
  commit_tags:
    description: JSON object of the commit message's tags; a bare [name] is "true"
    value: ${{ steps.parse.outputs.commit_tags }}
  scr_update:
    description: commit_tags.SCR_UPDATE, empty when absent
    value: ${{ steps.parse.outputs.scr_update }}
runs:
  using: composite
  steps:
    - shell: bash --noprofile --norc {0}
      env:
        GH_TOKEN: ${{ github.token }}
        PR_NUMBER: ${{ github.event.pull_request.number }}
        HEAD_SHA: ${{ github.event.pull_request.head.sha }}
      run: bash "$GITHUB_ACTION_PATH/fetch.sh"
    - id: parse
      shell: bash --noprofile --norc {0}
      env:
        PR_NUMBER: ${{ github.event.pull_request.number }}
        PR_TITLE_FILE: ${{ runner.temp }}/options/title.txt
        COMMIT_MESSAGE_FILE: ${{ runner.temp }}/options/commit.txt
      run: bash "$GITHUB_ACTION_PATH/parse.sh"
```

- [ ] **Step 6: Добавить smoke-шаги в конец джоба `smoke` в `ci.yml`.**

```yaml
      - name: options
        id: options
        uses: ./.github/actions/options
      - name: options outputs outside a PR
        if: github.event_name == 'push'
        env:
          PR_TAGS: ${{ steps.options.outputs.pr_tags }}
          SCR_UPDATE: ${{ steps.options.outputs.scr_update }}
        run: |
          [ "$PR_TAGS" = '{}' ] && [ -z "$SCR_UPDATE" ] || { echo "::error::unexpected options outputs on push"; exit 1; }
```

---

### Task 4: Action `npm-install`

**Files:**
- Create: `.github/actions/npm-install/action.yml`, `.github/actions/npm-install/install.sh`, `.github/actions/npm-install/browser-deps.sh`
- Create: `tests/npm-install.test.sh`, `tests/fixtures/npm-smoke/package.json`
- Modify: `.github/workflows/ci.yml` (шаг в `smoke`)

**Interfaces:**
- Consumes: `tests/lib.sh`.
- Produces: action `npm-install`, inputs:
  - `directories` — каталоги, по одному на строку, относительно workspace; обязательный;
  - `update` — строки `<каталог> <пакет>`: `npm update` после установки, по умолчанию пусто;
  - `token`, по умолчанию пусто;
  - `browsers` — `"true"` или `"false"`, по умолчанию `"false"`;
  - `node-version` — по умолчанию `"22"`.

- [ ] **Step 1: Написать падающий тест `tests/npm-install.test.sh`.**

```bash
# Tests of .github/actions/npm-install/{install,browser-deps}.sh with npm and npx stubbed out.
source tests/lib.sh

TMP="$(mktemp -d)"
mkdir -p "$TMP/bin" "$TMP/ws/a" "$TMP/ws/b" "$TMP/ws/nopkg"
echo '{}' > "$TMP/ws/a/package.json"
echo '{}' > "$TMP/ws/b/package.json"
cat > "$TMP/bin/npm" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "$(basename "$PWD")" "$*" "${GIT_CONFIG_VALUE_0:-}" "${PUPPETEER_SKIP_DOWNLOAD:-}" >> "$NPM_LOG"
[ ! -f fail-install ] || exit 1
EOF
cat > "$TMP/bin/npx" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$(basename "$PWD")" "$*" >> "$NPX_LOG"
EOF
chmod +x "$TMP/bin/npm" "$TMP/bin/npx"
export PATH="$TMP/bin:$PATH" GITHUB_WORKSPACE="$TMP/ws" NPM_LOG="$TMP/npm.log" NPX_LOG="$TMP/npx.log"
INSTALL='install --no-audit --no-fund --no-update-notifier --no-package-lock'

run() { # <directories> [token] [update]
  : > "$NPM_LOG"
  OUT="$(NPM_DIRS="$1" GITHUB_TOKEN="${2:-}" NPM_UPDATE="${3:-}" bash .github/actions/npm-install/install.sh 2>&1)"
  STATUS=$?
  LOG="$(sort "$NPM_LOG")"
}

run $'a\n\nb'
assert_eq "every listed directory installs, blank lines ignored" 0 "$STATUS"
assert_eq "one npm install per directory, Azure flags, puppeteer download off" \
  "$(printf 'a|%s||true\nb|%s||true' "$INSTALL" "$INSTALL")" "$LOG"

run 'a' 'secret-token'
assert_contains "the token becomes a basic extraheader for git" "$LOG" "|AUTHORIZATION: basic eC1hY2Nlc3MtdG9rZW46c2VjcmV0LXRva2Vu|"

run 'a' '' 'a eslint-plugin-surveyjs'
assert_contains "update runs npm update in its directory after the install" "$LOG" \
  "a|update eslint-plugin-surveyjs --no-package-lock --no-audit --no-fund||true"

touch "$TMP/ws/b/fail-install"
run $'a\nb'
assert_eq "a failed install fails the step" 1 "$STATUS"
assert_contains "and names the directory" "$OUT" "FAILED: $TMP/ws/b"
rm "$TMP/ws/b/fail-install"

run 'nopkg'
assert_eq "a directory without package.json fails" 1 "$STATUS"
assert_contains "and says why" "$OUT" "package.json not found"

run "$TMP/ws/a"
assert_eq "absolute paths are taken as they are" "a|$INSTALL||true" "$LOG"

mkdir -p "$TMP/ws/b/node_modules/.bin"
printf '#!/bin/sh\n' > "$TMP/ws/b/node_modules/.bin/playwright"
chmod +x "$TMP/ws/b/node_modules/.bin/playwright"
: > "$NPX_LOG"
OUT="$(NPM_DIRS=$'a\nb' bash .github/actions/npm-install/browser-deps.sh 2>&1)"
assert_eq "install-deps runs with the first Playwright CLI found" "b|--no-install playwright install-deps chromium" "$(cat "$NPX_LOG")"

: > "$NPX_LOG"
OUT="$(NPM_DIRS='a' bash .github/actions/npm-install/browser-deps.sh 2>&1)"
assert_eq "no Playwright CLI - nothing runs" "" "$(cat "$NPX_LOG")"
assert_contains "but it warns" "$OUT" "::warning::No Playwright CLI"

rm -rf "$TMP"
finish
```

- [ ] **Step 2: Запустить тест и убедиться, что он падает.**

Run: `bash tests/run.sh`
Expected: в `npm-install.test.sh` есть `FAIL`, код 1.

- [ ] **Step 3: Реализовать скрипты.**

`.github/actions/npm-install/install.sh`:
```bash
#!/usr/bin/env bash
# Port of templates/utils/npm.yml (keep in sync while it lives), minus its /tmp tarball cache -
# hosted runners start clean; sub-project D adds actions/cache.
# Usage (env): NPM_DIRS - directories, one per line, relative to GITHUB_WORKSPACE or absolute;
# NPM_UPDATE - optional "<directory> <package>" lines, `npm update`d after the installs;
# GITHUB_TOKEN - optional PAT.
#
# Some package.json files depend on git URLs (survey-utils, eslint-plugin-surveyjs). npm tries
# https first and, when that fails, silently retries over ssh - where the runner has no key, so
# the log shows only "Permission denied (publickey)" and hides the real error. The extraheader
# authenticates the request (anonymous git to github.com gets rate-limited); rewriting ssh to
# https keeps the real failure visible when it happens. An empty extraheader resets the header
# list, so a fork PR without the secret still works anonymously.
set -e

AUTH=""
if [ -n "${GITHUB_TOKEN:-}" ]; then
  AUTH="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 -w0)"
fi
export GIT_CONFIG_COUNT=3
export GIT_CONFIG_KEY_0="http.https://github.com/.extraheader" GIT_CONFIG_VALUE_0="$AUTH"
export GIT_CONFIG_KEY_1="url.https://github.com/.insteadOf"    GIT_CONFIG_VALUE_1="ssh://git@github.com/"
export GIT_CONFIG_KEY_2="url.https://github.com/.insteadOf"    GIT_CONFIG_VALUE_2="git@github.com:"
# puppeteer 22 sits unused in the root package.json files and would download Chrome every time
export PUPPETEER_SKIP_DOWNLOAD=true

resolve() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *) printf '%s' "$GITHUB_WORKSPACE/$1" ;;
  esac
}

FLAGS=(--no-audit --no-fund --no-update-notifier --no-package-lock)
PIDS=()
DIRS=()
while IFS= read -r DIR; do
  DIR="${DIR%$'\r'}"
  [ -n "$DIR" ] || continue
  DIR="$(resolve "$DIR")"
  (
    if [ ! -f "$DIR/package.json" ]; then
      echo "[$DIR] package.json not found"
      exit 1
    fi
    echo "[$DIR] npm install"
    cd "$DIR" && npm install "${FLAGS[@]}"
  ) &
  PIDS+=($!)
  DIRS+=("$DIR")
done <<< "$NPM_DIRS"

FAILED=0
for i in "${!PIDS[@]}"; do
  if ! wait "${PIDS[$i]}"; then
    echo "FAILED: ${DIRS[$i]}"
    FAILED=1
  fi
done
[ "$FAILED" -eq 0 ] || exit 1

while IFS= read -r LINE; do
  LINE="${LINE%$'\r'}"
  [ -n "$LINE" ] || continue
  DIR="$(resolve "${LINE%% *}")"
  PKG="${LINE#* }"
  echo "[$DIR] npm update $PKG"
  (cd "$DIR" && npm update "$PKG" --no-package-lock --no-audit --no-fund)
done <<< "${NPM_UPDATE:-}"
```

`.github/actions/npm-install/browser-deps.sh`:
```bash
#!/usr/bin/env bash
# Usage (env): NPM_DIRS - as in install.sh. Installs the system libraries Playwright's Chromium
# needs, with the Playwright CLI of the first listed directory that has one.
set -euo pipefail

while IFS= read -r DIR; do
  DIR="${DIR%$'\r'}"
  [ -n "$DIR" ] || continue
  case "$DIR" in /*) ;; *) DIR="$GITHUB_WORKSPACE/$DIR" ;; esac
  if [ -x "$DIR/node_modules/.bin/playwright" ]; then
    cd "$DIR"
    npx --no-install playwright install-deps chromium
    exit 0
  fi
done <<< "$NPM_DIRS"
echo "::warning::No Playwright CLI in the listed directories - browser dependencies were not installed"
```

- [ ] **Step 4: Запустить тест и убедиться, что он проходит.**

Run: `bash tests/run.sh`
Expected: в `npm-install.test.sh` все строки `ok`, код 0.

- [ ] **Step 5: Написать `action.yml` и фикстуру.**

`.github/actions/npm-install/action.yml`:
```yaml
name: npm install
description: >
  Port of templates/utils/npm.yml (keep in sync while it lives): sets Node up and runs
  `npm install` in every listed directory in parallel, then the optional `npm update`s.
  No cache yet - sub-project D adds it.
inputs:
  directories:
    description: Directories to install, one per line, relative to the workspace
    required: true
  update:
    description: Optional "<directory> <package>" lines to `npm update` after the installs
    default: ""
  token:
    description: PAT for the git dependencies; empty installs anonymously
    default: ""
  browsers:
    description: "'true' - also install the system libraries of Playwright's Chromium"
    default: "false"
  node-version:
    description: Node.js version - the one the Azure agents run (see the inventory)
    default: "22"
runs:
  using: composite
  steps:
    - uses: actions/setup-node@v5
      with:
        node-version: ${{ inputs.node-version }}
        package-manager-cache: false
    - shell: bash --noprofile --norc {0}
      env:
        NPM_DIRS: ${{ inputs.directories }}
        NPM_UPDATE: ${{ inputs.update }}
        GITHUB_TOKEN: ${{ inputs.token }}
      run: bash "$GITHUB_ACTION_PATH/install.sh"
    - if: inputs.browsers == 'true'
      shell: bash --noprofile --norc {0}
      env:
        NPM_DIRS: ${{ inputs.directories }}
      run: bash "$GITHUB_ACTION_PATH/browser-deps.sh"
```

`tests/fixtures/npm-smoke/package.json`:
```json
{
  "name": "npm-smoke",
  "version": "1.0.0",
  "private": true
}
```

- [ ] **Step 6: Если в Task 0 `NODE_MAJOR` оказался не 22, заменить default `"22"` в `action.yml` на `NODE_MAJOR`.**

- [ ] **Step 7: Добавить smoke-шаг в конец джоба `smoke` в `ci.yml`.**

```yaml
      - name: npm-install
        uses: ./.github/actions/npm-install
        with:
          directories: tests/fixtures/npm-smoke
```

---

### Task 5: Action `publish-test-results`

**Files:**
- Create: `.github/actions/publish-test-results/action.yml`
- Create: `tests/fixtures/junit/smoke-junit.xml`
- Modify: `.github/workflows/ci.yml` (шаг в `smoke`)

**Interfaces:**
- Produces: action `publish-test-results`, inputs:
  - `path` — обязательный;
  - `artifact-name` — обязательный;
  - `junit-file` — по умолчанию пусто, без отчёта;
  - `title` — по умолчанию `"Tests"`.

  Вызывать с `if: ${{ !cancelled() }}`.

- [ ] **Step 1: Написать `action.yml`.**

`.github/actions/publish-test-results/action.yml`:
```yaml
name: Publish test results
description: >
  Port of the PublishBuildArtifacts(test-results) + PublishTestResults@2 pair of the Azure test
  templates. Uploads the results directory as an artifact and reports the JUnit file as annotations
  plus a job summary (annotate_only: no checks permission, so it works on fork PRs too). Call it
  with an `if` that keeps it running after a failed test step unless the run was cancelled - Azure
  ran these with always() / succeededOrFailed().
inputs:
  path:
    description: Directory to upload, relative to the workspace
    required: true
  artifact-name:
    description: Artifact name - the Azure ArtifactName
    required: true
  junit-file:
    description: JUnit file name inside `path`; empty uploads without a report
    default: ""
  title:
    description: Report title - the Azure testRunTitle
    default: "Tests"
runs:
  using: composite
  steps:
    # always(): the caller's `if` already decided that the action runs; both steps run then, after a
    # failed test step too. No ${{ }} in the description above - the runner evaluates it there as well.
    - if: always()
      uses: actions/upload-artifact@v4
      with:
        name: ${{ inputs.artifact-name }}
        path: ${{ inputs.path }}
        if-no-files-found: ignore
        overwrite: true
        retention-days: 14
    - if: always() && inputs.junit-file != ''
      uses: mikepenz/action-junit-report@v5
      with:
        report_paths: ${{ inputs.path }}/${{ inputs.junit-file }}
        check_name: ${{ inputs.title }}
        annotate_only: true
        detailed_summary: true
        include_passed: false
        require_tests: false
        fail_on_failure: true
```

- [ ] **Step 2: Написать фикстуру `tests/fixtures/junit/smoke-junit.xml`.**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="smoke" tests="1" failures="0" errors="0">
  <testsuite name="smoke" tests="1" failures="0" errors="0">
    <testcase classname="smoke" name="passes" time="0.001"/>
  </testsuite>
</testsuites>
```

- [ ] **Step 3: Добавить smoke-шаг в конец джоба `smoke` в `ci.yml`.**

```yaml
      - name: publish-test-results
        if: ${{ !cancelled() }}
        uses: ./.github/actions/publish-test-results
        with:
          path: tests/fixtures/junit
          artifact-name: Smoke_Results
          junit-file: smoke-junit.xml
          title: Smoke Tests
```

- [ ] **Step 4: Проверить.**

Run: `bash tests/run.sh`
Expected: код 0. Шаг ничего не ломает. Сам action проверит джоб `smoke` после push ветки: в summary джоба появится таблица «Smoke Tests» с одним пройденным тестом, а в прогоне — артефакт `Smoke_Results`.

---

### Task 6: Action `build-library` и workflows тестов library

**Files:**
- Create: `.github/actions/build-library/action.yml`
- Create: `.github/workflows/library-core.yml`, `library-react.yml`, `library-angular.yml`, `library-vue.yml`, `library-js.yml`

**Interfaces:**
- Consumes: `checkout-pr` (Task 2), `npm-install` (Task 4), `publish-test-results` (Task 5).
- Produces:
  - Action `build-library`, inputs:
    - `repository` — по умолчанию `surveyjs/survey-library`;
    - `ref`, `pr` — по умолчанию пусто;
    - `package` — пусто означает только survey-core;
    - `example` — `"true"` или `"false"`;
    - `artifact-name`;
    - `browsers`;
    - `token`.
  - Reusable workflows `library-{core,angular,vue,js}.yml`: inputs `ref`, `pr` (string, по умолчанию пусто).
  - `library-react.yml`: inputs `ref`, `pr` и `scr-update`.

- [ ] **Step 1: Написать `build-library`.**

`.github/actions/build-library/action.yml`:
```yaml
name: Build survey-library
description: >
  Port of templates/library/<framework>/build.yml (keep in sync while those live): checks
  survey-library out at the workspace root, switches to a companion PR if one is given, installs,
  builds survey-core and, with `package`, one UI package; with `artifact-name` uploads that build
  (the Azure `store: true`).
inputs:
  repository:
    description: survey-library repository; the triggering commit when it is the run's own repo
    default: surveyjs/survey-library
  ref:
    description: Ref to check out; empty = the triggering commit (own repo) or the default branch
    default: ""
  pr:
    description: Companion survey-library PR number, or empty
    default: ""
  package:
    description: UI package under packages/ (survey-react-ui, ...); empty = survey-core only
    default: ""
  example:
    description: "'true' - packages/<package>/example has a package.json of its own"
    default: "false"
  artifact-name:
    description: Upload packages/<package or survey-core>/build under this name; empty = no upload
    default: ""
  browsers:
    description: "'true' - install the system libraries of Playwright's Chromium"
    default: "false"
  token:
    description: PAT (secrets.SURVEYJS_BOT_TOKEN); empty works for everything public
    default: ""
runs:
  using: composite
  steps:
    - uses: actions/checkout@v5
      with:
        repository: ${{ inputs.repository }}
        ref: ${{ inputs.ref }}
        token: ${{ inputs.token || github.token }}
        persist-credentials: false
        fetch-depth: 1
    - uses: surveyjs/azure-pipelines/.github/actions/checkout-pr@gha-migration
      with:
        pr: ${{ inputs.pr }}
        name: survey-library
        token: ${{ inputs.token }}
    - id: dirs
      shell: bash --noprofile --norc {0}
      env:
        PACKAGE: ${{ inputs.package }}
        EXAMPLE: ${{ inputs.example }}
      run: |
        {
          echo 'list<<EOF'
          echo .
          echo packages/survey-core
          if [ -n "$PACKAGE" ]; then echo "packages/$PACKAGE"; fi
          if [ -n "$PACKAGE" ] && [ "$EXAMPLE" = true ]; then echo "packages/$PACKAGE/example"; fi
          echo EOF
        } >> "$GITHUB_OUTPUT"
    - uses: surveyjs/azure-pipelines/.github/actions/npm-install@gha-migration
      with:
        directories: ${{ steps.dirs.outputs.list }}
        token: ${{ inputs.token }}
        browsers: ${{ inputs.browsers }}
    - name: Build Core
      shell: bash --noprofile --norc {0}
      working-directory: packages/survey-core
      run: npm run build:all
    - name: Build
      if: inputs.package != ''
      shell: bash --noprofile --norc {0}
      working-directory: packages/${{ inputs.package }}
      run: npm run build
    - name: Publish build artifacts
      if: inputs.artifact-name != ''
      uses: actions/upload-artifact@v4
      with:
        name: ${{ inputs.artifact-name }}
        path: packages/${{ inputs.package || 'survey-core' }}/build
        overwrite: true
        retention-days: 14
```

- [ ] **Step 2: Написать `.github/workflows/library-core.yml`.**

```yaml
# Port of templates/library/core/test.yml (keep in sync while it lives).
name: Library Core Test

on:
  workflow_call:
    inputs:
      ref:
        description: survey-library ref; empty = the triggering commit
        type: string
        default: ""
      pr:
        description: Companion survey-library PR number, or empty
        type: string
        default: ""

defaults:
  run:
    shell: bash --noprofile --norc {0}

jobs:
  unit-postcss:
    name: Unit PostCSS
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-library@gha-migration
        with:
          ref: ${{ inputs.ref }}
          pr: ${{ inputs.pr }}
          artifact-name: SurveyJSLibraryBuildCore
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Tests Unit
        working-directory: packages/survey-core
        run: npm run test
      - name: Tests CSS
        working-directory: packages/survey-core
        run: npm run test:postcss
```

- [ ] **Step 3: Написать `.github/workflows/library-react.yml`.**

```yaml
# Port of templates/library/react/test.yml (keep in sync while it lives).
name: Library React Test

on:
  workflow_call:
    inputs:
      ref:
        description: survey-library ref; empty = the triggering commit
        type: string
        default: ""
      pr:
        description: Companion survey-library PR number, or empty
        type: string
        default: ""
      scr-update:
        description: Non-empty ([scr_update] in the commit message) - only regenerate the screenshots
        type: string
        default: ""

defaults:
  run:
    shell: bash --noprofile --norc {0}

jobs:
  markup:
    name: Markup
    if: inputs.scr-update == ''
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-library@gha-migration
        with:
          ref: ${{ inputs.ref }}
          pr: ${{ inputs.pr }}
          package: survey-react-ui
          artifact-name: SurveyJSLibraryBuildReact
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Test Markup
        working-directory: packages/survey-react-ui
        run: npm run test

  a11y-e2e:
    name: A11Y & E2E
    if: inputs.scr-update == ''
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-library@gha-migration
        with:
          ref: ${{ inputs.ref }}
          pr: ${{ inputs.pr }}
          package: survey-react-ui
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      # the a11y script pins --reporter dot, so junit is appended back here and pointed at
      # its own file to avoid clobbering the e2e results written in the same job
      - name: Test A11Y
        working-directory: packages/survey-react-ui
        env:
          PLAYWRIGHT_JUNIT_OUTPUT_FILE: ${{ github.workspace }}/packages/survey-react-ui/test-results/a11y-junit-results.xml
        run: npm run accessibility-tests:ci -- --reporter dot,junit
      - name: Publish A11Y results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-react-ui/test-results
          artifact-name: Library_React_A11Y
          junit-file: a11y-junit-results.xml
          title: React A11Y Tests
      - name: Test E2E
        working-directory: packages/survey-react-ui
        run: npm run e2e:ci
      - name: Publish E2E results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-react-ui/test-results
          artifact-name: Library_React_E2E
          junit-file: e2e-junit-results.xml
          title: React E2E Tests

  scr:
    name: SCR Test
    if: inputs.scr-update == ''
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-library@gha-migration
        with:
          ref: ${{ inputs.ref }}
          pr: ${{ inputs.pr }}
          package: survey-react-ui
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Test SCR
        working-directory: packages/survey-react-ui
        run: npm run scr:ci
      - name: Publish SCR results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-react-ui/test-results
          artifact-name: Library_React_SCR
          junit-file: e2e-junit-results.xml
          title: React SCR Tests

  scr-update:
    name: SCR Update
    # Pushes back to the PR branch, so only for a PR from this repository.
    if: inputs.scr-update != '' && github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-library@gha-migration
        with:
          ref: ${{ inputs.ref }}
          pr: ${{ inputs.pr }}
          package: survey-react-ui
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Update SCR
        working-directory: packages/survey-react-ui
        run: npm run scr:update
      - name: Commit updated screenshots
        env:
          HEAD_REF: ${{ github.head_ref }}
          TOKEN: ${{ secrets.SURVEYJS_BOT_TOKEN }}
        run: |
          set -euo pipefail
          git config user.email "surveyjs.org@gmail.com"
          git config user.name "surveyjsdeveloper"
          git add screenshots
          TOTAL="$(git diff --cached --name-only | wc -l | tr -d ' ')"
          git commit --allow-empty -m "updated $TOTAL screenshots" --no-verify
          # The PAT goes to git through the environment only - never into .git/config. The push
          # must be the PAT's: a push with the workflow token would not start a new CI run.
          AUTH="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$TOKEN" | base64 -w0)"
          export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="http.https://github.com/.extraheader" GIT_CONFIG_VALUE_0="$AUTH"
          git fetch origin "$HEAD_REF"
          git rebase --onto "origin/$HEAD_REF" HEAD~1
          # The new baselines, for review and - in the shadow period - to take them from here.
          mkdir -p "$RUNNER_TEMP/scr-update"
          git diff --name-only --diff-filter=AM HEAD~1 HEAD -- screenshots | while IFS= read -r F; do
            mkdir -p "$RUNNER_TEMP/scr-update/$(dirname "$F")"
            cp "$F" "$RUNNER_TEMP/scr-update/$F"
          done
          # SHADOW-OFF: git push --no-verify origin "HEAD:$HEAD_REF"
      - name: Publish updated screenshots
        if: ${{ !cancelled() }}
        uses: actions/upload-artifact@v4
        with:
          name: Library_SCR_Update
          path: ${{ runner.temp }}/scr-update
          if-no-files-found: ignore
          overwrite: true
          retention-days: 14
```

- [ ] **Step 4: Написать `.github/workflows/library-angular.yml`.**

```yaml
# Port of templates/library/angular/test.yml (keep in sync while it lives).
name: Library Angular Test

on:
  workflow_call:
    inputs:
      ref:
        description: survey-library ref; empty = the triggering commit
        type: string
        default: ""
      pr:
        description: Companion survey-library PR number, or empty
        type: string
        default: ""

defaults:
  run:
    shell: bash --noprofile --norc {0}

jobs:
  a11y-e2e:
    name: A11Y & E2E
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-library@gha-migration
        with:
          ref: ${{ inputs.ref }}
          pr: ${{ inputs.pr }}
          package: survey-angular-ui
          example: "true"
          artifact-name: SurveyJSLibraryBuildAngular
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Build Example
        working-directory: packages/survey-angular-ui
        run: npm run build:example:prod
      # the a11y script pins --reporter dot, so junit is appended back here and pointed at
      # its own file to avoid clobbering the e2e results written in the same job
      - name: Test A11Y
        working-directory: packages/survey-angular-ui
        env:
          PLAYWRIGHT_JUNIT_OUTPUT_FILE: ${{ github.workspace }}/packages/survey-angular-ui/test-results/a11y-junit-results.xml
        run: npm run accessibility-tests:ci -- --reporter dot,junit
      - name: Publish A11Y results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-angular-ui/test-results
          artifact-name: Library_Angular_A11Y
          junit-file: a11y-junit-results.xml
          title: Angular A11Y Tests
      - name: Test E2E
        working-directory: packages/survey-angular-ui
        run: npm run e2e:ci
      - name: Publish E2E results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-angular-ui/test-results
          artifact-name: Library_Angular_E2E
          junit-file: e2e-junit-results.xml
          title: Angular E2E Tests

  markup-scr:
    name: Markup & SCR
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-library@gha-migration
        with:
          ref: ${{ inputs.ref }}
          pr: ${{ inputs.pr }}
          package: survey-angular-ui
          example: "true"
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Build Example
        working-directory: packages/survey-angular-ui
        run: npm run build:example:prod
      - name: Test Markup
        working-directory: packages/survey-angular-ui
        run: npm run test
      - name: Test SCR
        working-directory: packages/survey-angular-ui
        run: npm run scr:ci
      - name: Publish SCR results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-angular-ui/test-results
          artifact-name: Library_Angular_SCR
          junit-file: e2e-junit-results.xml
          title: Angular SCR Tests
```

- [ ] **Step 5: Написать `.github/workflows/library-vue.yml`.**

```yaml
# Port of templates/library/vue/test.yml (keep in sync while it lives).
name: Library Vue Test

on:
  workflow_call:
    inputs:
      ref:
        description: survey-library ref; empty = the triggering commit
        type: string
        default: ""
      pr:
        description: Companion survey-library PR number, or empty
        type: string
        default: ""

defaults:
  run:
    shell: bash --noprofile --norc {0}

jobs:
  a11y-e2e:
    name: A11Y & E2E
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-library@gha-migration
        with:
          ref: ${{ inputs.ref }}
          pr: ${{ inputs.pr }}
          package: survey-vue3-ui
          example: "true"
          artifact-name: SurveyJSLibraryBuildVue3
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Build Example
        working-directory: packages/survey-vue3-ui
        run: npm run build:example:prod
      # the a11y script pins --reporter dot, so junit is appended back here and pointed at
      # its own file to avoid clobbering the e2e results written in the same job
      - name: Test A11Y
        working-directory: packages/survey-vue3-ui
        env:
          PLAYWRIGHT_JUNIT_OUTPUT_FILE: ${{ github.workspace }}/packages/survey-vue3-ui/test-results/a11y-junit-results.xml
        run: npm run accessibility-tests:ci -- --reporter dot,junit
      - name: Publish A11Y results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-vue3-ui/test-results
          artifact-name: Library_Vue_A11Y
          junit-file: a11y-junit-results.xml
          title: Vue3 A11Y Tests
      - name: Test E2E
        working-directory: packages/survey-vue3-ui
        run: npm run e2e:ci
      - name: Publish E2E results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-vue3-ui/test-results
          artifact-name: Library_Vue_E2E
          junit-file: e2e-junit-results.xml
          title: Vue3 E2E Tests

  scr:
    name: SCR
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-library@gha-migration
        with:
          ref: ${{ inputs.ref }}
          pr: ${{ inputs.pr }}
          package: survey-vue3-ui
          example: "true"
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Build Example
        working-directory: packages/survey-vue3-ui
        run: npm run build:example:prod
      - name: Test Markup
        working-directory: packages/survey-vue3-ui
        run: npm run test
      - name: Test SCR
        working-directory: packages/survey-vue3-ui
        run: npm run scr:ci
      - name: Publish SCR results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-vue3-ui/test-results
          artifact-name: Library_Vue3_SCR
          junit-file: e2e-junit-results.xml
          title: Vue3 SCR Tests
```

- [ ] **Step 6: Написать `.github/workflows/library-js.yml`.**

```yaml
# Port of templates/library/js/test.yml (keep in sync while it lives).
name: Library JS (Preact ShadowDOM BoxSizing) Test

on:
  workflow_call:
    inputs:
      ref:
        description: survey-library ref; empty = the triggering commit
        type: string
        default: ""
      pr:
        description: Companion survey-library PR number, or empty
        type: string
        default: ""

defaults:
  run:
    shell: bash --noprofile --norc {0}

jobs:
  a11y-e2e:
    name: A11Y & E2E
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-library@gha-migration
        with:
          ref: ${{ inputs.ref }}
          pr: ${{ inputs.pr }}
          package: survey-js-ui
          artifact-name: SurveyJSLibraryBuildSurveyUI
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      # the a11y script pins --reporter dot, so junit is appended back here and pointed at
      # its own file to avoid clobbering the e2e results written in the same job
      - name: Test A11Y
        working-directory: packages/survey-js-ui
        env:
          PLAYWRIGHT_JUNIT_OUTPUT_FILE: ${{ github.workspace }}/packages/survey-js-ui/test-results/a11y-junit-results.xml
        run: npm run accessibility-tests:ci -- --reporter dot,junit
      - name: Publish A11Y results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-js-ui/test-results
          artifact-name: Library_Preact_A11Y
          junit-file: a11y-junit-results.xml
          title: Preact A11Y Tests
      - name: Test E2E
        working-directory: packages/survey-js-ui
        run: npm run e2e:ci
      - name: Publish E2E results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-js-ui/test-results
          artifact-name: Library_Preact_E2E
          junit-file: e2e-junit-results.xml
          title: Preact E2E Tests

  scr:
    name: SCR
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-library@gha-migration
        with:
          ref: ${{ inputs.ref }}
          pr: ${{ inputs.pr }}
          package: survey-js-ui
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Test SCR
        working-directory: packages/survey-js-ui
        run: npm run scr:ci
      - name: Publish SCR results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-js-ui/test-results
          artifact-name: Library_Preact_SCR
          junit-file: e2e-junit-results.xml
          title: Preact SCR Tests
```

- [ ] **Step 7: Сверить с Azure-шаблонами.** Открыть рядом `templates/library/{core,react,angular,vue,js}/test.yml` и новые файлы. Для каждого Azure-джоба проверить, что совпадают:
  - джоб с тем же `displayName`;
  - те же скрипты в том же порядке;
  - те же `ArtifactName`/`testRunTitle`;
  - `store: true` у первого джоба — это `artifact-name` в `build-library`.

  Единственные отличия:
  - SCR Update: push закомментирован, добавлен артефакт `Library_SCR_Update`;
  - условие SCR Update дополнено проверкой «PR из этого же репозитория».

- [ ] **Step 8: actionlint.**

Run: `MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W):/repo" -w /repo rhysd/actionlint:latest -color`, если запущен Docker Desktop. Иначе actionlint выполнится в `ci.yml` после push.
Expected: без ошибок.

---

### Task 7: Action `build-creator` и workflows тестов creator

**Files:**
- Create: `.github/actions/build-creator/action.yml`
- Create: `.github/workflows/creator-core.yml`, `creator-react.yml`, `creator-angular.yml`, `creator-vue.yml`, `creator-js.yml`

**Interfaces:**
- Consumes: `checkout-pr`, `npm-install`, `publish-test-results`.
- Produces:
  - Action `build-creator`, inputs:
    - `creator-repository` — по умолчанию `surveyjs/survey-creator`;
    - `creator-ref`, `creator-pr`;
    - `library-repository` — по умолчанию `surveyjs/survey-library`;
    - `library-ref`, `library-pr`;
    - `library-ui`, например `survey-react-ui`;
    - `creator-ui`, например `survey-creator-react`;
    - `example` — каталог примера относительно workspace;
    - `browsers`, `token`.

    Раскладка: creator — корень workspace, survey-library — `survey-library/`.
  - Workflows `creator-*.yml`: inputs `creator-ref`, `creator-pr`, `library-ref`, `library-pr` (string). У `creator-{react,angular,vue,js}` есть ещё `scr-blocking` (boolean, по умолчанию `true`).

- [ ] **Step 1: Написать `build-creator`.**

`.github/actions/build-creator/action.yml`:
```yaml
name: Build survey-creator
description: >
  Port of templates/creator/<framework>/build.yml (keep in sync while those live): survey-creator
  at the workspace root, survey-library at survey-library/ next to its packages, each switched to
  its companion PR if one is given. Builds survey-core (+ the library UI package), copies those
  builds into the creator packages' node_modules, then builds survey-creator-core (+ the creator
  UI package).
inputs:
  creator-repository:
    description: survey-creator repository
    default: surveyjs/survey-creator
  creator-ref:
    description: survey-creator ref; empty = the triggering commit (own repo) or the default branch
    default: ""
  creator-pr:
    description: Companion survey-creator PR number, or empty
    default: ""
  library-repository:
    description: survey-library repository
    default: surveyjs/survey-library
  library-ref:
    description: survey-library ref; empty = the triggering commit (own repo) or the default branch
    default: ""
  library-pr:
    description: Companion survey-library PR number, or empty
    default: ""
  library-ui:
    description: Library UI package (survey-react-ui, ...); empty = survey-core only
    default: ""
  creator-ui:
    description: Creator UI package (survey-creator-react, ...); empty = survey-creator-core only
    default: ""
  example:
    description: Example app directory with its own package.json, relative to the workspace
    default: ""
  browsers:
    description: "'true' - install the system libraries of Playwright's Chromium"
    default: "false"
  token:
    description: PAT (secrets.SURVEYJS_BOT_TOKEN); empty works for everything public
    default: ""
runs:
  using: composite
  steps:
    - uses: actions/checkout@v5
      with:
        repository: ${{ inputs.creator-repository }}
        ref: ${{ inputs.creator-ref }}
        token: ${{ inputs.token || github.token }}
        persist-credentials: false
        fetch-depth: 1
    - uses: surveyjs/azure-pipelines/.github/actions/checkout-pr@gha-migration
      with:
        pr: ${{ inputs.creator-pr }}
        name: survey-creator
        token: ${{ inputs.token }}
    - uses: actions/checkout@v5
      with:
        repository: ${{ inputs.library-repository }}
        ref: ${{ inputs.library-ref }}
        path: survey-library
        token: ${{ inputs.token || github.token }}
        persist-credentials: false
        fetch-depth: 1
    - uses: surveyjs/azure-pipelines/.github/actions/checkout-pr@gha-migration
      with:
        pr: ${{ inputs.library-pr }}
        path: survey-library
        name: survey-library
        token: ${{ inputs.token }}
    - id: dirs
      shell: bash --noprofile --norc {0}
      env:
        LIBRARY_UI: ${{ inputs.library-ui }}
        CREATOR_UI: ${{ inputs.creator-ui }}
        EXAMPLE: ${{ inputs.example }}
      run: |
        {
          echo 'list<<EOF'
          echo survey-library
          echo survey-library/packages/survey-core
          if [ -n "$LIBRARY_UI" ]; then echo "survey-library/packages/$LIBRARY_UI"; fi
          echo .
          echo packages/survey-creator-core
          if [ -n "$CREATOR_UI" ]; then echo "packages/$CREATOR_UI"; fi
          if [ -n "$EXAMPLE" ]; then echo "$EXAMPLE"; fi
          echo EOF
        } >> "$GITHUB_OUTPUT"
    - uses: surveyjs/azure-pipelines/.github/actions/npm-install@gha-migration
      with:
        directories: ${{ steps.dirs.outputs.list }}
        token: ${{ inputs.token }}
        browsers: ${{ inputs.browsers }}
    - name: Build survey-core
      shell: bash --noprofile --norc {0}
      working-directory: survey-library/packages/survey-core
      run: npm run build:all
    - name: Build ${{ inputs.library-ui }}
      if: inputs.library-ui != ''
      shell: bash --noprofile --norc {0}
      working-directory: survey-library/packages/${{ inputs.library-ui }}
      run: npm run build
    - name: Copy the survey-library builds into node_modules
      shell: bash --noprofile --norc {0}
      env:
        LIBRARY_UI: ${{ inputs.library-ui }}
        CREATOR_UI: ${{ inputs.creator-ui }}
      run: |
        set -e
        copy() { echo "Copying $1 -> $2"; rm -rf "$2"; cp -r "$1" "$2"; }
        CORE=survey-library/packages/survey-core/build
        copy "$CORE" packages/survey-creator-core/node_modules/survey-core
        if [ -n "$CREATOR_UI" ]; then
          copy "$CORE" "packages/$CREATOR_UI/node_modules/survey-core"
          copy "survey-library/packages/$LIBRARY_UI/build" "packages/$CREATOR_UI/node_modules/$LIBRARY_UI"
        fi
    - name: Build Core
      shell: bash --noprofile --norc {0}
      working-directory: packages/survey-creator-core
      run: npm run build:all
    - name: Build
      if: inputs.creator-ui != ''
      shell: bash --noprofile --norc {0}
      working-directory: packages/${{ inputs.creator-ui }}
      run: npm run build
```

- [ ] **Step 2: Написать `.github/workflows/creator-core.yml`.**

```yaml
# Port of templates/creator/core/test.yml (keep in sync while it lives).
name: Creator Core Test

on:
  workflow_call:
    inputs:
      creator-ref:
        description: survey-creator ref - the branch the library PR targets
        type: string
        default: ""
      creator-pr:
        description: Companion survey-creator PR number, or empty
        type: string
        default: ""
      library-ref:
        description: survey-library ref; empty = the triggering commit
        type: string
        default: ""
      library-pr:
        description: Companion survey-library PR number, or empty
        type: string
        default: ""

defaults:
  run:
    shell: bash --noprofile --norc {0}

jobs:
  unit:
    name: Unit & Presets & PostCSS
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-creator@gha-migration
        with:
          creator-ref: ${{ inputs.creator-ref }}
          creator-pr: ${{ inputs.creator-pr }}
          library-ref: ${{ inputs.library-ref }}
          library-pr: ${{ inputs.library-pr }}
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Unit
        working-directory: packages/survey-creator-core
        run: npm run test
      - name: Presets
        working-directory: packages/survey-creator-core
        run: npm run test:presets
      - name: PostCSS
        working-directory: packages/survey-creator-core
        run: npm run test:postcss
```

- [ ] **Step 3: Написать `.github/workflows/creator-react.yml`.**

```yaml
# Port of templates/creator/react/test.yml (keep in sync while it lives), without its "SCR Update"
# job: the library pipeline never runs it (no SCR_UPDATE in the creator stages).
name: Creator React Test

on:
  workflow_call:
    inputs:
      creator-ref:
        description: survey-creator ref - the branch the library PR targets
        type: string
        default: ""
      creator-pr:
        description: Companion survey-creator PR number, or empty
        type: string
        default: ""
      library-ref:
        description: survey-library ref; empty = the triggering commit
        type: string
        default: ""
      library-pr:
        description: Companion survey-library PR number, or empty
        type: string
        default: ""
      scr-blocking:
        description: false - a failed screenshot job does not fail the workflow (the baselines belong to survey-creator's own pipeline)
        type: boolean
        default: true

defaults:
  run:
    shell: bash --noprofile --norc {0}

jobs:
  example-a11y:
    name: Example & A11Y
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-creator@gha-migration
        with:
          creator-ref: ${{ inputs.creator-ref }}
          creator-pr: ${{ inputs.creator-pr }}
          library-ref: ${{ inputs.library-ref }}
          library-pr: ${{ inputs.library-pr }}
          library-ui: survey-react-ui
          creator-ui: survey-creator-react
          example: packages/survey-creator-react/example
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Build Example
        working-directory: packages/survey-creator-react/example
        run: npm run build
      - name: Test
        working-directory: packages/survey-creator-react
        run: npm run test
      # the a11y script pins --reporter dot, so junit is appended back here to get a results file
      - name: Test A11Y
        working-directory: packages/survey-creator-react
        env:
          PLAYWRIGHT_JUNIT_OUTPUT_FILE: ${{ github.workspace }}/packages/survey-creator-react/test-results/a11y-junit-results.xml
        run: npm run test:a11y:ci -- --reporter dot,junit
      - name: Publish A11Y results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-creator-react/test-results
          artifact-name: Creator_React_A11Y
          junit-file: a11y-junit-results.xml
          title: Creator React A11Y Tests

  e2e:
    name: E2E
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-creator@gha-migration
        with:
          creator-ref: ${{ inputs.creator-ref }}
          creator-pr: ${{ inputs.creator-pr }}
          library-ref: ${{ inputs.library-ref }}
          library-pr: ${{ inputs.library-pr }}
          library-ui: survey-react-ui
          creator-ui: survey-creator-react
          example: packages/survey-creator-react/example
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Test E2E
        working-directory: packages/survey-creator-react
        run: npm run e2e:ci
      - name: Publish results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-creator-react/test-results
          artifact-name: Creator_React_E2E
          junit-file: e2e-junit-results.xml
          title: Creator React E2E Tests

  scr:
    name: SCR Test
    continue-on-error: ${{ !inputs.scr-blocking }}
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-creator@gha-migration
        with:
          creator-ref: ${{ inputs.creator-ref }}
          creator-pr: ${{ inputs.creator-pr }}
          library-ref: ${{ inputs.library-ref }}
          library-pr: ${{ inputs.library-pr }}
          library-ui: survey-react-ui
          creator-ui: survey-creator-react
          example: packages/survey-creator-react/example
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Test SCR
        working-directory: packages/survey-creator-react
        run: npm run test:scr:ci
      - name: Publish results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-creator-react/test-results
          artifact-name: Creator_React_SCR
          junit-file: e2e-junit-results.xml
          title: Creator React SCR Tests

  scr-legacy:
    name: SCR Legacy
    if: github.base_ref == 'V2' || github.ref_name == 'V2'
    continue-on-error: ${{ !inputs.scr-blocking }}
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-creator@gha-migration
        with:
          creator-ref: ${{ inputs.creator-ref }}
          creator-pr: ${{ inputs.creator-pr }}
          library-ref: ${{ inputs.library-ref }}
          library-pr: ${{ inputs.library-pr }}
          library-ui: survey-react-ui
          creator-ui: survey-creator-react
          example: packages/survey-creator-react/example
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Test SCR Legacy
        working-directory: packages/survey-creator-react
        run: npm run test:scr:legacy:ci
      - name: Publish results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-creator-react/test-results
          artifact-name: Creator_React_SCR_Legacy
          junit-file: e2e-junit-results.xml
          title: Creator React SCR Legacy Tests
```

- [ ] **Step 4: Написать `.github/workflows/creator-angular.yml`.**

```yaml
# Port of templates/creator/angular/test.yml (keep in sync while it lives).
name: Creator Angular Test

on:
  workflow_call:
    inputs:
      creator-ref:
        description: survey-creator ref - the branch the library PR targets
        type: string
        default: ""
      creator-pr:
        description: Companion survey-creator PR number, or empty
        type: string
        default: ""
      library-ref:
        description: survey-library ref; empty = the triggering commit
        type: string
        default: ""
      library-pr:
        description: Companion survey-library PR number, or empty
        type: string
        default: ""
      scr-blocking:
        description: false - a failed screenshot job does not fail the workflow (the baselines belong to survey-creator's own pipeline)
        type: boolean
        default: true

defaults:
  run:
    shell: bash --noprofile --norc {0}

jobs:
  markup-a11y:
    name: Markup & Example & A11Y
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-creator@gha-migration
        with:
          creator-ref: ${{ inputs.creator-ref }}
          creator-pr: ${{ inputs.creator-pr }}
          library-ref: ${{ inputs.library-ref }}
          library-pr: ${{ inputs.library-pr }}
          library-ui: survey-angular-ui
          creator-ui: survey-creator-angular
          example: packages/survey-creator-angular/example/angular-ui
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Test
        working-directory: packages/survey-creator-angular
        run: npm run test:single
      - name: Build Example
        working-directory: packages/survey-creator-angular
        run: npm run build:example:prod
      # the a11y script pins --reporter dot, so junit is appended back here to get a results file
      - name: Test A11Y
        working-directory: packages/survey-creator-angular
        env:
          PLAYWRIGHT_JUNIT_OUTPUT_FILE: ${{ github.workspace }}/packages/survey-creator-angular/test-results/a11y-junit-results.xml
        run: npm run test:a11y:ci -- --reporter dot,junit
      - name: Publish A11Y results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-creator-angular/test-results
          artifact-name: Creator_Angular_A11Y
          junit-file: a11y-junit-results.xml
          title: Creator Angular A11Y Tests

  e2e:
    name: E2E
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-creator@gha-migration
        with:
          creator-ref: ${{ inputs.creator-ref }}
          creator-pr: ${{ inputs.creator-pr }}
          library-ref: ${{ inputs.library-ref }}
          library-pr: ${{ inputs.library-pr }}
          library-ui: survey-angular-ui
          creator-ui: survey-creator-angular
          example: packages/survey-creator-angular/example/angular-ui
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Build Example
        working-directory: packages/survey-creator-angular
        run: npm run build:example:prod
      - name: Test E2E
        working-directory: packages/survey-creator-angular
        run: npm run e2e:ci
      - name: Publish results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-creator-angular/test-results
          artifact-name: Creator_Angular_E2E
          junit-file: e2e-junit-results.xml
          title: Creator Angular E2E Tests

  scr:
    name: SCR
    continue-on-error: ${{ !inputs.scr-blocking }}
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-creator@gha-migration
        with:
          creator-ref: ${{ inputs.creator-ref }}
          creator-pr: ${{ inputs.creator-pr }}
          library-ref: ${{ inputs.library-ref }}
          library-pr: ${{ inputs.library-pr }}
          library-ui: survey-angular-ui
          creator-ui: survey-creator-angular
          example: packages/survey-creator-angular/example/angular-ui
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Build Example
        working-directory: packages/survey-creator-angular
        run: npm run build:example:prod
      - name: Test SCR
        working-directory: packages/survey-creator-angular
        run: npm run test:scr:ci
      - name: Publish results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-creator-angular/test-results
          artifact-name: Creator_Angular_SCR
          junit-file: e2e-junit-results.xml
          title: Creator Angular SCR Tests
```

- [ ] **Step 5: Написать `.github/workflows/creator-vue.yml`.**

```yaml
# Port of templates/creator/vue/test.yml (keep in sync while it lives).
name: Creator Vue Test

on:
  workflow_call:
    inputs:
      creator-ref:
        description: survey-creator ref - the branch the library PR targets
        type: string
        default: ""
      creator-pr:
        description: Companion survey-creator PR number, or empty
        type: string
        default: ""
      library-ref:
        description: survey-library ref; empty = the triggering commit
        type: string
        default: ""
      library-pr:
        description: Companion survey-library PR number, or empty
        type: string
        default: ""
      scr-blocking:
        description: false - a failed screenshot job does not fail the workflow (the baselines belong to survey-creator's own pipeline)
        type: boolean
        default: true

defaults:
  run:
    shell: bash --noprofile --norc {0}

jobs:
  example-a11y:
    name: Example & A11Y
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-creator@gha-migration
        with:
          creator-ref: ${{ inputs.creator-ref }}
          creator-pr: ${{ inputs.creator-pr }}
          library-ref: ${{ inputs.library-ref }}
          library-pr: ${{ inputs.library-pr }}
          library-ui: survey-vue3-ui
          creator-ui: survey-creator-vue
          example: packages/survey-creator-vue/example
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Build Example
        working-directory: packages/survey-creator-vue
        run: npm run build:example:prod
      # the a11y script pins --reporter dot, so junit is appended back here to get a results file
      - name: Test A11Y
        working-directory: packages/survey-creator-vue
        env:
          PLAYWRIGHT_JUNIT_OUTPUT_FILE: ${{ github.workspace }}/packages/survey-creator-vue/test-results/a11y-junit-results.xml
        run: npm run test:a11y:ci -- --reporter dot,junit
      - name: Publish A11Y results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-creator-vue/test-results
          artifact-name: Creator_Vue_A11Y
          junit-file: a11y-junit-results.xml
          title: Creator Vue A11Y Tests

  e2e:
    name: E2E
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-creator@gha-migration
        with:
          creator-ref: ${{ inputs.creator-ref }}
          creator-pr: ${{ inputs.creator-pr }}
          library-ref: ${{ inputs.library-ref }}
          library-pr: ${{ inputs.library-pr }}
          library-ui: survey-vue3-ui
          creator-ui: survey-creator-vue
          example: packages/survey-creator-vue/example
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Build Example
        working-directory: packages/survey-creator-vue
        run: npm run build:example:prod
      - name: Test E2E
        working-directory: packages/survey-creator-vue
        run: npm run e2e:ci
      - name: Publish results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-creator-vue/test-results
          artifact-name: Creator_Vue_E2E
          junit-file: e2e-junit-results.xml
          title: Creator Vue E2E Tests

  scr:
    name: SCR
    continue-on-error: ${{ !inputs.scr-blocking }}
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-creator@gha-migration
        with:
          creator-ref: ${{ inputs.creator-ref }}
          creator-pr: ${{ inputs.creator-pr }}
          library-ref: ${{ inputs.library-ref }}
          library-pr: ${{ inputs.library-pr }}
          library-ui: survey-vue3-ui
          creator-ui: survey-creator-vue
          example: packages/survey-creator-vue/example
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Build Example
        working-directory: packages/survey-creator-vue
        run: npm run build:example:prod
      - name: Test SCR
        working-directory: packages/survey-creator-vue
        run: npm run test:scr:ci
      - name: Publish results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-creator-vue/test-results
          artifact-name: Creator_Vue_SCR
          junit-file: e2e-junit-results.xml
          title: Creator Vue SCR Tests
```

- [ ] **Step 6: Написать `.github/workflows/creator-js.yml`.**

```yaml
# Port of templates/creator/js/test.yml (keep in sync while it lives).
name: Creator JS (Preact ShadowDOM BoxSizing) Test

on:
  workflow_call:
    inputs:
      creator-ref:
        description: survey-creator ref - the branch the library PR targets
        type: string
        default: ""
      creator-pr:
        description: Companion survey-creator PR number, or empty
        type: string
        default: ""
      library-ref:
        description: survey-library ref; empty = the triggering commit
        type: string
        default: ""
      library-pr:
        description: Companion survey-library PR number, or empty
        type: string
        default: ""
      scr-blocking:
        description: false - a failed screenshot job does not fail the workflow (the baselines belong to survey-creator's own pipeline)
        type: boolean
        default: true

defaults:
  run:
    shell: bash --noprofile --norc {0}

jobs:
  example-a11y:
    name: Example & A11Y
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-creator@gha-migration
        with:
          creator-ref: ${{ inputs.creator-ref }}
          creator-pr: ${{ inputs.creator-pr }}
          library-ref: ${{ inputs.library-ref }}
          library-pr: ${{ inputs.library-pr }}
          library-ui: survey-js-ui
          creator-ui: survey-creator-js
          example: packages/survey-creator-js/example
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Build Example
        working-directory: packages/survey-creator-js/example
        run: npm run build
      # the a11y script pins --reporter dot, so junit is appended back here to get a results file
      - name: Test A11Y
        working-directory: packages/survey-creator-js
        env:
          PLAYWRIGHT_JUNIT_OUTPUT_FILE: ${{ github.workspace }}/packages/survey-creator-js/test-results/a11y-junit-results.xml
        run: npm run test:a11y:ci -- --reporter dot,junit
      - name: Publish A11Y results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-creator-js/test-results
          artifact-name: Creator_JS_A11Y
          junit-file: a11y-junit-results.xml
          title: Creator JS A11Y Tests

  e2e:
    name: E2E
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-creator@gha-migration
        with:
          creator-ref: ${{ inputs.creator-ref }}
          creator-pr: ${{ inputs.creator-pr }}
          library-ref: ${{ inputs.library-ref }}
          library-pr: ${{ inputs.library-pr }}
          library-ui: survey-js-ui
          creator-ui: survey-creator-js
          example: packages/survey-creator-js/example
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Test E2E
        working-directory: packages/survey-creator-js
        run: npm run e2e:ci
      - name: Publish results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-creator-js/test-results
          artifact-name: Creator_JS_E2E
          junit-file: e2e-junit-results.xml
          title: Creator JS E2E Tests

  scr:
    name: SCR
    continue-on-error: ${{ !inputs.scr-blocking }}
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-creator@gha-migration
        with:
          creator-ref: ${{ inputs.creator-ref }}
          creator-pr: ${{ inputs.creator-pr }}
          library-ref: ${{ inputs.library-ref }}
          library-pr: ${{ inputs.library-pr }}
          library-ui: survey-js-ui
          creator-ui: survey-creator-js
          example: packages/survey-creator-js/example
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Test SCR
        working-directory: packages/survey-creator-js
        run: npm run test:scr:ci
      - name: Publish results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: packages/survey-creator-js/test-results
          artifact-name: Creator_JS_SCR
          junit-file: e2e-junit-results.xml
          title: Creator JS SCR Tests
```

- [ ] **Step 7: Сверить с Azure-шаблонами** `templates/creator/*/test.yml` и `build.yml`. Должны совпадать:
  - джобы, скрипты, порядок шагов, имена артефактов и отчётов;
  - каталоги npm install;
  - три копирования в `node_modules`.

  Намеренные отличия:
  - нет «SCR Update»;
  - у джобов нет условий `SCR_UPDATE == ''`: в library.yml это условие проверяется на уровне стадии;
  - у SCR-джобов `continue-on-error` зависит от `scr-blocking`.

- [ ] **Step 8: actionlint**, как в Task 6, Step 8.

---

### Task 8: Action `build-core-consumer`, workflows analytics и pdf

**Files:**
- Create: `.github/actions/build-core-consumer/action.yml`
- Create: `.github/workflows/analytics-test.yml`, `.github/workflows/pdf-test.yml`

**Interfaces:**
- Consumes: `checkout-pr`, `npm-install`, `publish-test-results`.
- Produces:
  - Action `build-core-consumer`, inputs:
    - `repository` — обязательный;
    - `name` — обязательный;
    - `ref`, `pr`;
    - `library-repository`, `library-ref`, `library-pr`;
    - `browsers`, `token`.
  - `analytics-test.yml`: inputs `analytics-ref`, `analytics-pr`, `library-ref`, `library-pr`, `scr-blocking`.
  - `pdf-test.yml`: inputs `pdf-ref`, `pdf-pr`, `library-ref`, `library-pr`.

- [ ] **Step 1: Написать `build-core-consumer`.**

`.github/actions/build-core-consumer/action.yml`:
```yaml
name: Build a survey-core consumer
description: >
  Port of templates/analytics/build.yml and templates/pdf/build.yml - the two are identical (keep
  in sync while they live): the product at the workspace root, survey-library at survey-library/,
  each switched to its companion PR if one is given. Builds survey-core, copies it into the
  product's node_modules and builds the product (`npm run build:all`).
inputs:
  repository:
    description: Product repository (surveyjs/survey-analytics, surveyjs/survey-pdf)
    required: true
  name:
    description: Product name for the log
    required: true
  ref:
    description: Product ref; empty = the triggering commit (own repo) or the default branch
    default: ""
  pr:
    description: Companion product PR number, or empty
    default: ""
  library-repository:
    description: survey-library repository
    default: surveyjs/survey-library
  library-ref:
    description: survey-library ref; empty = the triggering commit (own repo) or the default branch
    default: ""
  library-pr:
    description: Companion survey-library PR number, or empty
    default: ""
  browsers:
    description: "'true' - install the system libraries of Playwright's Chromium"
    default: "false"
  token:
    description: PAT (secrets.SURVEYJS_BOT_TOKEN); empty works for everything public
    default: ""
runs:
  using: composite
  steps:
    - uses: actions/checkout@v5
      with:
        repository: ${{ inputs.repository }}
        ref: ${{ inputs.ref }}
        token: ${{ inputs.token || github.token }}
        persist-credentials: false
        fetch-depth: 1
    - uses: surveyjs/azure-pipelines/.github/actions/checkout-pr@gha-migration
      with:
        pr: ${{ inputs.pr }}
        name: ${{ inputs.name }}
        token: ${{ inputs.token }}
    - uses: actions/checkout@v5
      with:
        repository: ${{ inputs.library-repository }}
        ref: ${{ inputs.library-ref }}
        path: survey-library
        token: ${{ inputs.token || github.token }}
        persist-credentials: false
        fetch-depth: 1
    - uses: surveyjs/azure-pipelines/.github/actions/checkout-pr@gha-migration
      with:
        pr: ${{ inputs.library-pr }}
        path: survey-library
        name: survey-library
        token: ${{ inputs.token }}
    - uses: surveyjs/azure-pipelines/.github/actions/npm-install@gha-migration
      with:
        directories: |
          survey-library
          survey-library/packages/survey-core
          .
        token: ${{ inputs.token }}
        browsers: ${{ inputs.browsers }}
    - name: Build survey-core
      shell: bash --noprofile --norc {0}
      working-directory: survey-library/packages/survey-core
      run: npm run build:all
    - name: Copy survey-core into node_modules
      shell: bash --noprofile --norc {0}
      run: |
        set -e
        echo "Copying survey-library/packages/survey-core/build -> node_modules/survey-core"
        rm -rf node_modules/survey-core
        cp -r survey-library/packages/survey-core/build node_modules/survey-core
    - name: Build
      shell: bash --noprofile --norc {0}
      run: npm run build:all
```

- [ ] **Step 2: Написать `.github/workflows/analytics-test.yml`.**

```yaml
# Port of templates/analytics/test.yml (keep in sync while it lives), without its "SCR Update"
# job: the library pipeline never runs it (no SCR_UPDATE in the analytics stage).
name: Analytics Test

on:
  workflow_call:
    inputs:
      analytics-ref:
        description: survey-analytics ref - the branch the library PR targets
        type: string
        default: ""
      analytics-pr:
        description: Companion survey-analytics PR number, or empty
        type: string
        default: ""
      library-ref:
        description: survey-library ref; empty = the triggering commit
        type: string
        default: ""
      library-pr:
        description: Companion survey-library PR number, or empty
        type: string
        default: ""
      scr-blocking:
        description: false - a failed E2E job (it compares screenshots) does not fail the workflow
        type: boolean
        default: true

defaults:
  run:
    shell: bash --noprofile --norc {0}

jobs:
  unit:
    name: Unit
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-core-consumer@gha-migration
        with:
          repository: surveyjs/survey-analytics
          name: survey-analytics
          ref: ${{ inputs.analytics-ref }}
          pr: ${{ inputs.analytics-pr }}
          library-ref: ${{ inputs.library-ref }}
          library-pr: ${{ inputs.library-pr }}
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Test
        run: npm run test

  e2e:
    name: E2E
    continue-on-error: ${{ !inputs.scr-blocking }}
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-core-consumer@gha-migration
        with:
          repository: surveyjs/survey-analytics
          name: survey-analytics
          ref: ${{ inputs.analytics-ref }}
          pr: ${{ inputs.analytics-pr }}
          library-ref: ${{ inputs.library-ref }}
          library-pr: ${{ inputs.library-pr }}
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Playwright install
        run: npm run pwinst
      - name: Test
        run: npm run e2e:ci
      - name: Publish e2e test results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: test-results
          artifact-name: Analytics_E2E
          junit-file: e2e-junit-results.xml
          title: Publish E2E test results
```

- [ ] **Step 3: Написать `.github/workflows/pdf-test.yml`.**

```yaml
# Port of templates/pdf/test.yml (keep in sync while it lives).
name: PDF Test

on:
  workflow_call:
    inputs:
      pdf-ref:
        description: survey-pdf ref - the branch the library PR targets
        type: string
        default: ""
      pdf-pr:
        description: Companion survey-pdf PR number, or empty
        type: string
        default: ""
      library-ref:
        description: survey-library ref; empty = the triggering commit
        type: string
        default: ""
      library-pr:
        description: Companion survey-library PR number, or empty
        type: string
        default: ""

defaults:
  run:
    shell: bash --noprofile --norc {0}

jobs:
  test:
    name: Test
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-core-consumer@gha-migration
        with:
          repository: surveyjs/survey-pdf
          name: survey-pdf
          ref: ${{ inputs.pdf-ref }}
          pr: ${{ inputs.pdf-pr }}
          library-ref: ${{ inputs.library-ref }}
          library-pr: ${{ inputs.library-pr }}
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Test
        run: npm run test
```

- [ ] **Step 4: Сверить с Azure-шаблонами** `templates/analytics/{test,build}.yml` и `templates/pdf/{test,build}.yml`. Должны совпадать:
  - джобы и скрипты;
  - имя артефакта `Analytics_E2E`;
  - каталоги npm install;
  - копирование core.

  Намеренные отличия: нет «SCR Update», нет условий `SCR_UPDATE` у джобов, `continue-on-error` у E2E.

- [ ] **Step 5: actionlint**, как в Task 6, Step 8.

---

### Task 9: Action `build-theme-adapter-demos` и workflow demos

**Files:**
- Create: `.github/actions/build-theme-adapter-demos/action.yml`
- Create: `.github/workflows/theme-adapter-demos-test.yml`

**Interfaces:**
- Consumes: `checkout-pr`, `npm-install`, `publish-test-results`.
- Produces:
  - Action `build-theme-adapter-demos`, inputs:
    - `demos-repository`, `demos-ref`, `demos-pr`;
    - `library-repository`, `library-ref`, `library-pr`;
    - `creator-repository`, `creator-ref`, `creator-pr`;
    - `token`.

    Раскладка: demos — корень, `survey-library/` и `survey-creator/` рядом.
  - Workflow `theme-adapter-demos-test.yml`, inputs:
    - `demos-ref`, `demos-pr`;
    - `library-ref`, `library-pr`;
    - `creator-ref`, `creator-pr`;
    - `scr-blocking`.

- [ ] **Step 1: Написать `build-theme-adapter-demos`.**

`.github/actions/build-theme-adapter-demos/action.yml`:
```yaml
# Port of templates/theme-adapter-demos/build.yml (keep in sync while it lives).
#
# Checks out theme-adapter-demos plus survey-library / survey-creator, builds all four survey-*
# packages from those sources and replaces the demos' installed copies with them. Every pipeline
# that runs the demos does this - the apps are always exercised against the libraries, never
# against the published packages.
#
# The substitution is all-or-nothing: the demos' builder page runs survey-creator-react, and a
# published creator is compiled against a published survey-core, so mixing a local core with an
# npm creator risks an API mismatch.
#
# Layout matters: the creator packages declare their deps as relative paths
# (`../../../survey-library/packages/survey-core/build`), which resolve only when survey-library
# sits next to the survey-creator root - hence survey-library/ and survey-creator/ side by side
# under the demos checkout.
#
# SURVEYJS_LIBV3 is deliberately NOT set: without it the demos resolve survey-* from node_modules,
# which is exactly what this action overwrites - for the webpack bundle and for the CSS adapters
# that `prebuild` copies out of node_modules/survey-core alike.
name: Build theme-adapter-demos
description: >
  theme-adapter-demos at the workspace root with survey-library/ and survey-creator/ next to each
  other, every one switched to its companion PR if one is given; the four survey-* packages are
  built from source and copied over the demos' installed ones.
inputs:
  demos-repository:
    description: theme-adapter-demos repository
    default: surveyjs/theme-adapter-demos
  demos-ref:
    description: theme-adapter-demos ref; empty = the triggering commit (own repo) or the default branch
    default: ""
  demos-pr:
    description: Companion theme-adapter-demos PR number, or empty
    default: ""
  library-repository:
    description: survey-library repository
    default: surveyjs/survey-library
  library-ref:
    description: survey-library ref; empty = the triggering commit (own repo) or the default branch
    default: ""
  library-pr:
    description: Companion survey-library PR number, or empty
    default: ""
  creator-repository:
    description: survey-creator repository
    default: surveyjs/survey-creator
  creator-ref:
    description: survey-creator ref; empty = the triggering commit (own repo) or the default branch
    default: ""
  creator-pr:
    description: Companion survey-creator PR number, or empty
    default: ""
  token:
    description: PAT (secrets.SURVEYJS_BOT_TOKEN); empty works for everything public
    default: ""
runs:
  using: composite
  steps:
    - uses: actions/checkout@v5
      with:
        repository: ${{ inputs.demos-repository }}
        ref: ${{ inputs.demos-ref }}
        token: ${{ inputs.token || github.token }}
        persist-credentials: false
        fetch-depth: 1
    - uses: surveyjs/azure-pipelines/.github/actions/checkout-pr@gha-migration
      with:
        pr: ${{ inputs.demos-pr }}
        name: theme-adapter-demos
        token: ${{ inputs.token }}
    - uses: actions/checkout@v5
      with:
        repository: ${{ inputs.library-repository }}
        ref: ${{ inputs.library-ref }}
        path: survey-library
        token: ${{ inputs.token || github.token }}
        persist-credentials: false
        fetch-depth: 1
    - uses: surveyjs/azure-pipelines/.github/actions/checkout-pr@gha-migration
      with:
        pr: ${{ inputs.library-pr }}
        path: survey-library
        name: survey-library
        token: ${{ inputs.token }}
    - uses: actions/checkout@v5
      with:
        repository: ${{ inputs.creator-repository }}
        ref: ${{ inputs.creator-ref }}
        path: survey-creator
        token: ${{ inputs.token || github.token }}
        persist-credentials: false
        fetch-depth: 1
    - uses: surveyjs/azure-pipelines/.github/actions/checkout-pr@gha-migration
      with:
        pr: ${{ inputs.creator-pr }}
        path: survey-creator
        name: survey-creator
        token: ${{ inputs.token }}
    - uses: surveyjs/azure-pipelines/.github/actions/npm-install@gha-migration
      with:
        directories: |
          survey-library
          survey-library/packages/survey-core
          survey-library/packages/survey-react-ui
          survey-creator
          survey-creator/packages/survey-creator-core
          survey-creator/packages/survey-creator-react
          .
        token: ${{ inputs.token }}
        browsers: "true"
    - name: Build survey-core
      shell: bash --noprofile --norc {0}
      working-directory: survey-library/packages/survey-core
      run: npm run build:all
    - name: Build survey-react-ui
      shell: bash --noprofile --norc {0}
      working-directory: survey-library/packages/survey-react-ui
      run: npm run build
    - name: Copy the survey-library builds into survey-creator
      shell: bash --noprofile --norc {0}
      run: |
        set -e
        copy() { echo "Copying $1 -> $2"; rm -rf "$2"; cp -r "$1" "$2"; }
        copy survey-library/packages/survey-core/build survey-creator/packages/survey-creator-core/node_modules/survey-core
        copy survey-library/packages/survey-core/build survey-creator/packages/survey-creator-react/node_modules/survey-core
        copy survey-library/packages/survey-react-ui/build survey-creator/packages/survey-creator-react/node_modules/survey-react-ui
    - name: Build survey-creator-core
      shell: bash --noprofile --norc {0}
      working-directory: survey-creator/packages/survey-creator-core
      run: npm run build:all
    - name: Build survey-creator-react
      shell: bash --noprofile --norc {0}
      working-directory: survey-creator/packages/survey-creator-react
      run: npm run build
    - name: Copy the four builds into the demos
      shell: bash --noprofile --norc {0}
      run: |
        set -e
        copy() { echo "Copying $1 -> $2"; rm -rf "$2"; cp -r "$1" "$2"; }
        copy survey-library/packages/survey-core/build node_modules/survey-core
        copy survey-library/packages/survey-react-ui/build node_modules/survey-react-ui
        copy survey-creator/packages/survey-creator-core/build node_modules/survey-creator-core
        copy survey-creator/packages/survey-creator-react/build node_modules/survey-creator-react
```

- [ ] **Step 2: Написать `.github/workflows/theme-adapter-demos-test.yml`.**

```yaml
# Port of templates/theme-adapter-demos/test.yml (keep in sync while it lives): screenshot tests
# of the theme-adapter-demos apps, one job per app, against locally built survey-* packages.
name: Theme Adapter Demos

on:
  workflow_call:
    inputs:
      demos-ref:
        description: theme-adapter-demos ref; empty = its default branch (main)
        type: string
        default: ""
      demos-pr:
        description: Companion theme-adapter-demos PR number, or empty
        type: string
        default: ""
      library-ref:
        description: survey-library ref; empty = the triggering commit
        type: string
        default: ""
      library-pr:
        description: Companion survey-library PR number, or empty
        type: string
        default: ""
      creator-ref:
        description: survey-creator ref - the branch the library PR targets
        type: string
        default: ""
      creator-pr:
        description: Companion survey-creator PR number, or empty
        type: string
        default: ""
      scr-blocking:
        description: false - a failed screenshot job does not fail the workflow (the baselines belong to theme-adapter-demos' own pipeline)
        type: boolean
        default: true

defaults:
  run:
    shell: bash --noprofile --norc {0}

jobs:
  scr:
    name: "SCR: ${{ matrix.app }}"
    strategy:
      fail-fast: false
      matrix:
        app: [bootstrap, shadcn, mui]
    continue-on-error: ${{ !inputs.scr-blocking }}
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/build-theme-adapter-demos@gha-migration
        with:
          demos-ref: ${{ inputs.demos-ref }}
          demos-pr: ${{ inputs.demos-pr }}
          library-ref: ${{ inputs.library-ref }}
          library-pr: ${{ inputs.library-pr }}
          creator-ref: ${{ inputs.creator-ref }}
          creator-pr: ${{ inputs.creator-pr }}
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Playwright install
        env:
          PLAYWRIGHT_SKIP_BROWSER_GC: "1"
        run: npx playwright install chromium
      - name: Test SCR ${{ matrix.app }}
        env:
          APP: ${{ matrix.app }}
          CI: "true"
          PLAYWRIGHT_JUNIT_OUTPUT_FILE: ${{ github.workspace }}/test-results/scr-${{ matrix.app }}-junit.xml
          PLAYWRIGHT_HTML_OUTPUT_DIR: ${{ github.workspace }}/screenshot-tests/.report
        run: npm run "test:scr:$APP" -- --reporter=list,junit,html
      - name: Publish SCR results
        if: ${{ !cancelled() }}
        uses: surveyjs/azure-pipelines/.github/actions/publish-test-results@gha-migration
        with:
          path: test-results
          artifact-name: ThemeAdapterDemos_SCR_${{ matrix.app }}
          junit-file: scr-${{ matrix.app }}-junit.xml
          title: Theme Adapter Demos SCR ${{ matrix.app }}
      - name: Publish SCR report
        if: ${{ !cancelled() }}
        uses: actions/upload-artifact@v4
        with:
          name: ThemeAdapterDemos_SCR_Report_${{ matrix.app }}
          path: screenshot-tests/.report
          # .report is a hidden directory: upload-artifact skips hidden paths unless told otherwise
          include-hidden-files: true
          if-no-files-found: ignore
          overwrite: true
          retention-days: 14
```

- [ ] **Step 3: Сверить с** `templates/theme-adapter-demos/{test,build}.yml`. Должны совпадать:
  - три приложения;
  - имена артефактов;
  - env тестового шага;
  - семь каталогов npm install;
  - два блока копирования.

  Намеренные отличия: matrix вместо `${{ each }}`, `fail-fast: false`, `include-hidden-files`, `continue-on-error` по `scr-blocking`.

- [ ] **Step 4: actionlint**, как в Task 6, Step 8.

---

### Task 10: Оркестратор `.github/workflows/library.yml`

**Files:**
- Create: `.github/workflows/library.yml`

**Interfaces:**
- Consumes:
  - actions `npm-install`, `options`, `result`;
  - workflows из Tasks 6–9 с их inputs, как описано в блоках Interfaces этих задач.
- Produces:
  - reusable workflow `library.yml` с input `cross-repo-scr-blocking` (boolean, по умолчанию `true`);
  - джоб `result`: вместе с джобом вызывающего workflow в survey-library он даёт check `library / result`.

- [ ] **Step 1: Написать оркестратор.**

```yaml
# Port of library.yml (keep in sync while it lives): the survey-library CI. Called by
# survey-library's .github/workflows/library.yml. Sub-project A: Lint, Options and the test jobs;
# Staging and Backport come with sub-projects B and C.
#
# The needs and conditions copy the Azure stages. GitHub skips a job whose `needs` was skipped
# unless its `if` says otherwise - hence `!cancelled() && needs.options.result != 'failure'` on
# the test jobs: options runs on pull_request only and is skipped on a push.
name: Library

on:
  workflow_call:
    inputs:
      cross-repo-scr-blocking:
        description: >
          false - failed screenshot jobs of creator, analytics and theme-adapter-demos do not fail the
          run: their baselines belong to those repositories' own pipelines until they move here.
        type: boolean
        default: true

defaults:
  run:
    shell: bash --noprofile --norc {0}

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v5
        with:
          persist-credentials: false
          fetch-depth: 1
      - uses: surveyjs/azure-pipelines/.github/actions/npm-install@gha-migration
        with:
          directories: .
          # eslint-plugin-surveyjs comes from a git URL (surveyjs/eslint-surveyjs): take its tip
          update: . eslint-plugin-surveyjs
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Lint
        run: npm run lint

  options:
    name: Options
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    outputs:
      scr_update: ${{ steps.options.outputs.scr_update }}
      pr_tags: ${{ steps.options.outputs.pr_tags }}
    steps:
      - id: options
        uses: surveyjs/azure-pipelines/.github/actions/options@gha-migration

  library-core:
    name: Library Core Test
    needs: options
    if: ${{ !cancelled() && needs.options.result != 'failure' && (needs.options.outputs.scr_update || '') == '' }}
    uses: surveyjs/azure-pipelines/.github/workflows/library-core.yml@gha-migration
    secrets: inherit

  library-react:
    name: Library React Test
    needs: options
    if: ${{ !cancelled() && needs.options.result != 'failure' }}
    uses: surveyjs/azure-pipelines/.github/workflows/library-react.yml@gha-migration
    with:
      scr-update: ${{ needs.options.outputs.scr_update || '' }}
    secrets: inherit

  library-angular:
    name: Library Angular Test
    needs: options
    if: ${{ !cancelled() && needs.options.result != 'failure' && (needs.options.outputs.scr_update || '') == '' }}
    uses: surveyjs/azure-pipelines/.github/workflows/library-angular.yml@gha-migration
    secrets: inherit

  library-vue:
    name: Library Vue Test
    needs: options
    if: ${{ !cancelled() && needs.options.result != 'failure' && (needs.options.outputs.scr_update || '') == '' }}
    uses: surveyjs/azure-pipelines/.github/workflows/library-vue.yml@gha-migration
    secrets: inherit

  library-js:
    name: Library JS (Preact ShadowDOM BoxSizing) Test
    needs: options
    if: ${{ !cancelled() && needs.options.result != 'failure' && (needs.options.outputs.scr_update || '') == '' }}
    uses: surveyjs/azure-pipelines/.github/workflows/library-js.yml@gha-migration
    secrets: inherit

  creator-core:
    name: Creator Core Test
    needs: options
    if: ${{ !cancelled() && needs.options.result != 'failure' && (needs.options.outputs.scr_update || '') == '' }}
    uses: surveyjs/azure-pipelines/.github/workflows/creator-core.yml@gha-migration
    with:
      creator-ref: ${{ github.base_ref || github.ref_name }}
      creator-pr: ${{ fromJSON(needs.options.outputs.pr_tags || '{}').CREATOR || '' }}
    secrets: inherit

  creator-react:
    name: Creator React Test
    needs: options
    if: ${{ !cancelled() && needs.options.result != 'failure' && (needs.options.outputs.scr_update || '') == '' }}
    uses: surveyjs/azure-pipelines/.github/workflows/creator-react.yml@gha-migration
    with:
      creator-ref: ${{ github.base_ref || github.ref_name }}
      creator-pr: ${{ fromJSON(needs.options.outputs.pr_tags || '{}').CREATOR || '' }}
      scr-blocking: ${{ inputs.cross-repo-scr-blocking }}
    secrets: inherit

  creator-angular:
    name: Creator Angular Test
    needs: options
    if: ${{ !cancelled() && needs.options.result != 'failure' && (needs.options.outputs.scr_update || '') == '' }}
    uses: surveyjs/azure-pipelines/.github/workflows/creator-angular.yml@gha-migration
    with:
      creator-ref: ${{ github.base_ref || github.ref_name }}
      creator-pr: ${{ fromJSON(needs.options.outputs.pr_tags || '{}').CREATOR || '' }}
      scr-blocking: ${{ inputs.cross-repo-scr-blocking }}
    secrets: inherit

  creator-vue:
    name: Creator Vue Test
    needs: options
    if: ${{ !cancelled() && needs.options.result != 'failure' && (needs.options.outputs.scr_update || '') == '' }}
    uses: surveyjs/azure-pipelines/.github/workflows/creator-vue.yml@gha-migration
    with:
      creator-ref: ${{ github.base_ref || github.ref_name }}
      creator-pr: ${{ fromJSON(needs.options.outputs.pr_tags || '{}').CREATOR || '' }}
      scr-blocking: ${{ inputs.cross-repo-scr-blocking }}
    secrets: inherit

  creator-js:
    name: Creator JS (Preact ShadowDOM BoxSizing) Test
    needs: options
    if: ${{ !cancelled() && needs.options.result != 'failure' && (needs.options.outputs.scr_update || '') == '' }}
    uses: surveyjs/azure-pipelines/.github/workflows/creator-js.yml@gha-migration
    with:
      creator-ref: ${{ github.base_ref || github.ref_name }}
      creator-pr: ${{ fromJSON(needs.options.outputs.pr_tags || '{}').CREATOR || '' }}
      scr-blocking: ${{ inputs.cross-repo-scr-blocking }}
    secrets: inherit

  analytics:
    name: Analytics Test
    needs: options
    if: ${{ !cancelled() && needs.options.result != 'failure' && (needs.options.outputs.scr_update || '') == '' }}
    uses: surveyjs/azure-pipelines/.github/workflows/analytics-test.yml@gha-migration
    with:
      analytics-ref: ${{ github.base_ref || github.ref_name }}
      analytics-pr: ${{ fromJSON(needs.options.outputs.pr_tags || '{}').ANALYTICS || '' }}
      scr-blocking: ${{ inputs.cross-repo-scr-blocking }}
    secrets: inherit

  pdf:
    name: PDF Test
    needs: options
    if: ${{ !cancelled() && needs.options.result != 'failure' && (needs.options.outputs.scr_update || '') == '' }}
    uses: surveyjs/azure-pipelines/.github/workflows/pdf-test.yml@gha-migration
    with:
      pdf-ref: ${{ github.base_ref || github.ref_name }}
      pdf-pr: ${{ fromJSON(needs.options.outputs.pr_tags || '{}').PDF || '' }}
    secrets: inherit

  theme-adapter-demos:
    name: Theme Adapter Demos
    needs: options
    if: ${{ !cancelled() && needs.options.result != 'failure' && (needs.options.outputs.scr_update || '') == '' && github.event_name == 'pull_request' && github.base_ref == 'master' }}
    uses: surveyjs/azure-pipelines/.github/workflows/theme-adapter-demos-test.yml@gha-migration
    with:
      demos-pr: ${{ fromJSON(needs.options.outputs.pr_tags || '{}').ADAPTERS || '' }}
      creator-ref: ${{ github.base_ref || github.ref_name }}
      creator-pr: ${{ fromJSON(needs.options.outputs.pr_tags || '{}').CREATOR || '' }}
      scr-blocking: ${{ inputs.cross-repo-scr-blocking }}
    secrets: inherit

  # The single required status check ("library / result" in survey-library's branch protection).
  result:
    name: result
    if: always()
    needs:
      - lint
      - options
      - library-core
      - library-react
      - library-angular
      - library-vue
      - library-js
      - creator-core
      - creator-react
      - creator-angular
      - creator-vue
      - creator-js
      - analytics
      - pdf
      - theme-adapter-demos
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: surveyjs/azure-pipelines/.github/actions/result@gha-migration
        with:
          needs: ${{ toJSON(needs) }}
```

- [ ] **Step 2: Сверить с [library.yml](../../../library.yml).**
  - Каждая стадия теста в Azure — это джоб с тем же `displayName`, таким же условием и тем же тегом из заголовка PR (`CREATOR`, `ANALYTICS`, `PDF`, `ADAPTERS`).
  - У ThemeAdapterDemos `LIBRARY_PR` пустой, а `CREATOR_PR` берётся из `CREATOR`.
  - Lint ни от чего не зависит.
  - Стадий Staging и Backport нет: они появятся в подпроектах B и C.

- [ ] **Step 3: actionlint**, как в Task 6, Step 8.
Expected: без ошибок. В частности, все `if:`, которые начинаются с `!`, обёрнуты в `${{ }}`.

- [ ] **Step 4: Прогнать тесты.**

Run: `bash tests/run.sh`
Expected: код 0.

---

### Task 11: Вызывающий workflow в survey-library и сценарии тени

**Files:**
- Create: `C:\Users\bsadv\WebstormProjects\survey-library\.github\workflows\library.yml` — в отдельной ветке survey-library, см. Step 1.

**Interfaces:**
- Consumes: `surveyjs/azure-pipelines/.github/workflows/library.yml@gha-migration` (Task 10) и секрет `SURVEYJS_BOT_TOKEN` (Task 0).
- Produces: check `library / result` на PR в survey-library. Пока он не required.

- [ ] **Step 1: Подготовить ветки (выполняет человек).**
  1. Закоммитить и запушить ветку `gha-migration` в azure-pipelines. Убедиться, что CI этого репозитория (`unit`, `actionlint`, `smoke`) зелёный.
  2. В survey-library создать ветку от master: `git switch -c ci/gha-shadow origin/master`. Текущую рабочую ветку survey-library не трогать.

- [ ] **Step 2: Написать вызывающий workflow.** Триггеры сверить с инвентаризацией (Task 0, Step 1). Ниже — значения по умолчанию.

```yaml
# survey-library CI on GitHub Actions. Everything lives in surveyjs/azure-pipelines
# (.github/workflows/library.yml); this file only triggers it.
name: Library

on:
  pull_request:
  push:
    branches: [master, V2, V3]
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: read

concurrency:
  # PRs: a new push cancels the previous run. Pushes: every run is kept - cancelling a pending
  # master run would lose its backport.
  group: ${{ github.event_name == 'pull_request' && format('library-pr-{0}', github.event.pull_request.number) || format('library-run-{0}', github.run_id) }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  library:
    name: library
    # The marker the l10n, docs and release commits carry - the one the Azure pipeline honours.
    # Not [skip ci]: that would also skip tagged-release.yml on the release tag.
    if: ${{ !contains(github.event.head_commit.message, '[azurepipelines skip]') }}
    uses: surveyjs/azure-pipelines/.github/workflows/library.yml@gha-migration
    secrets: inherit
```

- [ ] **Step 3: Открыть draft PR (выполняет человек).** Пользователь коммитит файл в `ci/gha-shadow`, пушит и открывает draft PR в master. Workflow берётся из merge-коммита PR, поэтому он запустится сам.

- [ ] **Step 4: Сценарии.** Выполняются на этом PR или на отдельных draft PR от `ci/gha-shadow`. Для каждого записать в инвентаризацию результат и ссылку на прогон.
  1. **Обычный PR:**
     - джобы `Lint`, `Options` и 13 тестовых, их состав совпадает с Azure-прогоном того же коммита;
     - Theme Adapter Demos запускается, потому что PR идёт в master;
     - `library / result` отражает итог;
     - артефакты называются так же, как в Azure.
  2. **Заголовок с `[creator: <номер открытого PR в survey-creator>]`:**
     - в summary джоба Options есть ссылка на этот PR;
     - в логе Creator-джобов есть строка `survey-creator PR <N> merged into its base branch`.
  3. **Заголовок с `[creator: <номер PR, который конфликтует с базой>]`:** warning `pull/<N>/merge is unavailable`, сборка продолжается на head.
  4. **Коммит с `[scr_update]` в сообщении:**
     - выполняется только `Library React Test / SCR Update` и Lint, остальные тестовые джобы пропущены;
     - `result` зелёный;
     - в логе SCR Update push закомментирован;
     - артефакт `Library_SCR_Update` содержит изменённые эталоны, если они есть.
  5. **Заголовок с `[creator: abc]`:** `Options` красный, тестовые джобы пропущены, `library / result` **красный**.
  6. **Правка заголовка без нового push:** после «Re-run all jobs» Options видит новый заголовок.
  7. **PR из форка** (любой открытый внешний PR после мержа вызывающего workflow в master или ручной PR из личного форка): прогон без секретов, Lint и npm install проходят.
  8. **Push** (после мержа вызывающего workflow в master — шаг 5 ниже):
     - `Options` пропущен;
     - тестовые джобы запущены и не падают на `fromJSON`;
     - Theme Adapter Demos пропущен;
     - `result` зелёный при зелёных тестах.
  9. **Сообщение коммита с `::error::test` на отдельной строке:** в логе Options строка напечатана между `::stop-commands::` и маркером возобновления, аннотации `test` нет.

- [ ] **Step 5: Начать теневой режим (выполняет человек).**
  - Смержить `ci/gha-shadow` в master, а затем cherry-pick'ом перенести файл в V2 и V3.
  - Check `library / result` **не** делать required.
  - Расхождения скриншотов (Library SCR, Creator SCR ×4, Analytics E2E, Theme Adapter Demos) по сравнению с Azure на тех же коммитах фиксировать в инвентаризации. От них зависят решения подпроектов D и E.

---

## Self-Review

1. **Покрытие спецификации в рамках подпроекта A:**

   | Требование | Где реализовано |
   |---|---|
   | Размещение кода | Tasks 1–10 |
   | Вызывающий workflow, метка, concurrency | Task 11 |
   | options только для PR; выходы и проверка номеров | Task 3, Task 10 |
   | Граф и условия Azure | Task 10 |
   | `result` | Task 1, Task 10 |
   | `bash` без `-e` | defaults в каждом workflow |
   | Перенос шагов и имена артефактов | Tasks 6–9 |
   | JUnit-отчёты | Task 5 |
   | `persist-credentials: false` | все checkout |
   | PUPPETEER, зависимости Playwright | Task 4 |
   | Node | Task 0, Task 4 |
   | SCR Update с `# SHADOW-OFF:` и артефактом | Task 6 |
   | Без SCR Update у creator и analytics | Tasks 7–8 |
   | Неблокирующие кросс-репо SCR | `scr-blocking` в Tasks 7–10 |
   | Комментарии «keep in sync» у двойников | шапки файлов |

   Вне подпроекта A остаются кэш (D), Staging (B), Backport и claude (C), переключение, README, release.yml, ai-flaky-fix (E).

   **Уточнение к спецификации.** По спецификации временно неблокирующие кросс-репо SCR «передаются списком и в result игнорируются». Но `needs.<job>.result` у джоба, вызывающего reusable workflow, не различает, упал ли SCR-джоб или E2E внутри. Поэтому в плане неблокирующим делается сам SCR-джоб через `continue-on-error: ${{ !inputs.scr-blocking }}`, а оркестратор управляет этим одним input'ом `cross-repo-scr-blocking`.
2. **Плейсхолдеры:** нет. Единственное значение из инвентаризации — Node, у него задан default `"22"` и явный шаг замены (Task 4, Step 6).
3. **Согласованность имён:**
   - inputs actions и workflows одинаковы во всех задачах: `ref`/`pr`, `creator-ref`/`creator-pr`, `library-ref`/`library-pr`, `analytics-*`, `pdf-*`, `demos-*`, `scr-blocking`, `scr-update`;
   - выходы options — `pr_tags`, `commit_tags`, `scr_update`;
   - input `result` — `needs`.
4. **Review Focus:**
   - пункты 1–4 закреплены тестами в Tasks 1–3;
   - пункт 5 — сценарий 8 в Task 11.
