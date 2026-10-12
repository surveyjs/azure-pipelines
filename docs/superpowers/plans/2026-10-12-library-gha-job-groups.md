# Группы джобов в панели прогона survey-library CI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** в панели прогона survey-library вместо одной группы `library` показать раскрывающиеся группы SCR Update, Library, Creator, Analytics, PDF, Theme Adapter Demos и Afterparty. Один и тот же workflow должен обслуживать и PR, и push в master, V2, V3.

**Architecture:**
- GitHub строит группы панели только из джобов верхнего уровня запустившего workflow. Поэтому граф джобов переезжает из `azure-pipelines/.github/workflows/library.yml` (его удаляем) в вызывающий `survey-library/.github/workflows/library.yml`.
- Новые групповые workflows в azure-pipelines (`library-test`, `creator-test`, `library-scr-update`, `afterparty`) вызывают существующие тестовые workflows.
- `result` становится первым джобом группы Afterparty. Staging и Backport добавят в неё подпроекты B и C.

**Tech Stack:** GitHub Actions (`workflow_call`, composite actions), bash 5 + jq (тесты `tests/*.test.sh`), actionlint.

**Spec:** [docs/superpowers/specs/2026-10-06-library-gha-migration-design.md](../specs/2026-10-06-library-gha-migration-design.md): разделы 2, 3 и 8 в редакции от 2026-10-12.

## Global Constraints

**Репозитории:**
- `C:\Users\bsadv\WebstormProjects\azure-pipelines`, ветка `gha-migration` — Tasks 1–5 и 7.
- `C:\Users\bsadv\WebstormProjects\survey-library`, ветка `gha-migration` — Task 6. Других веток не трогать.

**Ссылки и окружение:**
- Внутренние ссылки только такие: `surveyjs/azure-pipelines/.github/workflows/<name>.yml@gha-migration` и `surveyjs/azure-pipelines/.github/actions/<name>@gha-migration`.
- Раннер — `runs-on: ubuntu-24.04`. Shell — `defaults.run.shell: bash --noprofile --norc {0}` в каждом workflow, где есть `run:`.
- Во всех вызовах reusable workflow — `secrets: inherit`.

**Условия и безопасность:**
- Метку `[azurepipelines skip]` не менять на `[skip ci]`.
- `if:`, начинающийся с `!`, оборачивается в `${{ }}`.
- Недоверенный текст (заголовок PR, его теги, `toJSON(needs)`) попадает в `run:` только через `env`, никогда через `${{ }}`.

**Имена:**
- У групп верхнего уровня: Lint, Options, SCR Update, Library, Creator, Analytics, PDF, Theme Adapter Demos, Afterparty.
- Промежуточные джобы: Core, React, Angular, Vue, JS.
- Конечные джобы — без префикса области.
- Required check — `Afterparty / result`.

**Коммиты** делает пользователь. Ничего не коммитить и не пушить, изменения оставлять незакоммиченными.

**Инструменты:** на этой машине нет `jq` и `actionlint` (Git Bash и WSL). Перед первым запуском тестов их нужно положить в `$S/bin`, где `S` — scratchpad-каталог текущей сессии. Как — Task 1, Step 1. Тесты запускаются так: `PATH="$S/bin:$PATH" bash tests/run.sh`.

## Review Focus

1. **PR с `[scr_update]`.**
   - Должно быть: тестовые группы пропущены, выполняются Lint, Options, SCR Update и `Afterparty / result`, а `result` зелёный.
   - Тест: Task 5, Step 1 (`result.test.sh`, ключи новых групп). Плюс сценарий в Task 7.
2. **Невалидный тег `[creator: abc]`.**
   - Должно быть: Options красный, группы пропущены, Afterparty всё равно запускается (`always()`), а `result` красный.
   - Тест: проверка `always()` в Task 6, Step 3 и существующий случай в `result.test.sh`. Плюс сценарий в Task 7.
3. **Битая ссылка `uses:`** после удаления оркестратора или опечатка в групповом workflow. GitHub отвергает такой workflow целиком при старте прогона, а actionlint удалённые ссылки не проверяет.
   - Тест: Task 1 (`workflows.test.sh`) и его запуск с `EXTRA_WORKFLOWS` по вызывающему файлу в Task 6.
4. **Push-прогон.**
   - Должно быть: Options вне PR отдаёт `{}` и пустой `scr_update`, группы идут без ошибки `fromJSON('')`.
   - Тест: существующий случай «outside a PR» в `tests/options.test.sh`. Полностью проверяется только после мержа в master, сценарий в Task 7.
5. **PR из форка с `[scr_update]`.**
   - Должно быть: SCR Update не пытается пушить в форк.
   - Тест: условие джоба в Task 2 и существующий случай в `tests/options.test.sh` (Options на нём падает).

---

### Task 1: Инструменты и статическая проверка ссылок между workflows

**Files:**
- Create: `tests/workflows.test.sh`

**Interfaces:**
- Produces:
  - `tests/workflows.test.sh` — Tasks 2–5 дописывают в него проверки перед строкой `finish`;
  - env `EXTRA_WORKFLOWS` — пути к workflow-файлам вне репозитория, их ссылки тоже проверяются. Используется в Task 6.

- [ ] **Step 1: Положить `jq` и `actionlint` в `$S/bin`.**

Сначала проверить, не лежат ли они в scratchpad прошлой сессии:

```bash
S="<scratchpad текущей сессии>"
mkdir -p "$S/bin"
OLD="$(ls -d /c/Users/bsadv/AppData/Local/Temp/claude/c--Users-bsadv-WebstormProjects-azure-pipelines/*/scratchpad/bin 2>/dev/null | while read -r D; do [ -f "$D/jq.exe" ] && [ -f "$D/actionlint.exe" ] && echo "$D"; done | head -n1)"
[ -n "$OLD" ] && cp "$OLD/jq.exe" "$OLD/actionlint.exe" "$S/bin/"
ls "$S/bin"
```

Если `jq.exe` или `actionlint.exe` нет, скачать официальные сборки:

```bash
curl -sSL -o "$S/bin/jq.exe" https://github.com/jqlang/jq/releases/latest/download/jq-windows-amd64.exe
URL="$(curl -sSL https://api.github.com/repos/rhysd/actionlint/releases/latest | grep -o 'https://[^"]*_windows_amd64\.zip' | head -n1)"
curl -sSL -o "$S/bin/al.zip" "$URL"
powershell.exe -NoProfile -Command "Expand-Archive -Force '$(cygpath -w "$S/bin/al.zip")' '$(cygpath -w "$S/bin")'"
```

Expected: `"$S/bin/jq.exe" --version` и `"$S/bin/actionlint.exe" -version` печатают версии. Системно ничего не ставить.

- [ ] **Step 2: Прогнать текущие тесты.**

Run: `PATH="$S/bin:$PATH" bash tests/run.sh`
Expected: код 0. Это исходная точка, все тесты зелёные.

- [ ] **Step 3: Написать `tests/workflows.test.sh`.**

```bash
# Static checks of the workflows in .github/workflows. actionlint treats
# `uses: surveyjs/azure-pipelines/...@ref` as a remote reference and does not follow it, while
# GitHub rejects the whole run at start when such a reference points at a missing file.
# EXTRA_WORKFLOWS - space-separated workflow files of other repositories (survey-library's caller
# workflow) whose references are checked too.
source tests/lib.sh

MISSING=""
while IFS= read -r REF; do
  P="${REF#surveyjs/azure-pipelines/}"
  P="${P%@*}"
  case "$P" in
    .github/workflows/*) [ -f "$P" ] || MISSING="$MISSING $REF" ;;
    .github/actions/*) [ -f "$P/action.yml" ] || MISSING="$MISSING $REF" ;;
    *) MISSING="$MISSING $REF" ;;
  esac
done < <(grep -ho 'surveyjs/azure-pipelines/\.github/[^ ]*@[A-Za-z0-9._-]*' \
  .github/workflows/*.yml .github/actions/*/action.yml ${EXTRA_WORKFLOWS:-} | sort -u)
assert_eq "every internal uses: points at an existing workflow or action" "" "$MISSING"

finish
```

- [ ] **Step 4: Запустить и проверить, что тест ловит битую ссылку.**

Run: `PATH="$S/bin:$PATH" bash tests/workflows.test.sh`
Expected: `ok    every internal uses: points at an existing workflow or action`, код 0.

Затем проверка на отрицательном примере:

```bash
printf 'uses: surveyjs/azure-pipelines/.github/workflows/nope.yml@gha-migration\n' > "$S/bad.yml"
EXTRA_WORKFLOWS="$S/bad.yml" PATH="$S/bin:$PATH" bash tests/workflows.test.sh
```

Expected: `FAIL`, в `actual:` есть `nope.yml@gha-migration`, код 1. Удалить `"$S/bad.yml"`.

- [ ] **Step 5: Полный прогон.**

Run: `PATH="$S/bin:$PATH" bash tests/run.sh`
Expected: код 0, в выводе есть `== tests/workflows.test.sh`.

---

### Task 2: Отдельная группа SCR Update

**Files:**
- Create: `.github/workflows/library-scr-update.yml`
- Modify: `.github/workflows/library-react.yml`
- Modify: `tests/workflows.test.sh`

**Interfaces:**
- Produces:
  - `.github/workflows/library-scr-update.yml` — `on: workflow_call` без inputs, джоб `scr-update` с именем «Library React». Вызывается из survey-library в Task 6.
  - У `library-react.yml` больше нет input'а `scr-update`. Task 4 вызывает его без `with:`.

- [ ] **Step 1: Дописать проверки в `tests/workflows.test.sh` перед `finish`.**

```bash
# SCR Update is a group of its own (library-scr-update.yml): library-react.yml only tests.
assert_not_contains "library-react.yml has no SCR Update job" \
  "$(cat .github/workflows/library-react.yml)" "scr-update"
GUARD="$(grep -c "if: github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository" \
  .github/workflows/library-scr-update.yml 2>/dev/null)"
assert_eq "SCR Update pushes only to a PR branch of this repository" 1 "${GUARD:-0}"
```

- [ ] **Step 2: Убедиться, что проверки падают.**

Run: `PATH="$S/bin:$PATH" bash tests/workflows.test.sh`
Expected: `FAIL  library-react.yml has no SCR Update job` и `FAIL  SCR Update pushes only to a PR branch of this repository`, код 1.

- [ ] **Step 3: Создать `.github/workflows/library-scr-update.yml`.**

Шаги перенесены из джоба `scr-update` в `library-react.yml` один к одному. Убраны только `ref`/`pr` у сборки: значения по умолчанию у `build-library` и так означают коммит прогона.

```yaml
# Port of the "SCR Update" job of templates/library/react/test.yml (keep in sync while it lives).
# A group of its own in the survey-library CI run: with [scr_update] in the commit message the
# caller workflow skips the test groups, and this is the only thing that runs.
name: SCR Update

on: workflow_call

defaults:
  run:
    shell: bash --noprofile --norc {0}

jobs:
  scr-update:
    name: Library React
    # Pushes back to the PR branch, so only for a PR from this repository.
    if: github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - name: Build survey-library
        uses: surveyjs/azure-pipelines/.github/actions/build-library@gha-migration
        with:
          package: survey-react-ui
          browsers: "true"
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Update SCR
        working-directory: packages/survey-react-ui
        run: npm run scr:update -- --workers=100%
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

- [ ] **Step 4: Убрать SCR Update из `.github/workflows/library-react.yml`.**

1. Строку 1 шапки заменить на две:

```yaml
# Port of templates/library/react/test.yml (keep in sync while it lives), without its "SCR Update"
# job: that one is library-scr-update.yml, a group of its own in the survey-library CI run.
```

2. Удалить input `scr-update` целиком — это строки 15–18, от `      scr-update:` до его `default: ""`.
3. Удалить три строки `    if: inputs.scr-update == ''`: у джобов `markup`, `a11y-e2e` и `scr`.
4. Удалить джоб `scr-update` целиком, от строки `  scr-update:` до конца файла, и пустую строку перед ним. Файл должен заканчиваться шагом `Publish SCR results` джоба `scr`.

Проверка: `grep -n "scr-update\|scr_update" .github/workflows/library-react.yml` ничего не выводит.

- [ ] **Step 5: Тесты и actionlint.**

Run: `PATH="$S/bin:$PATH" bash tests/workflows.test.sh`
Expected: все `ok`, код 0.

Run: `"$S/bin/actionlint.exe" .github/workflows/library-react.yml .github/workflows/library-scr-update.yml`
Expected: без вывода, код 0.

---

### Task 3: Короткие имена конечных джобов

**Files:**
- Modify: `.github/workflows/library-{core,react,angular,vue,js}.yml`, `.github/workflows/creator-{core,react,angular,vue,js}.yml`, `.github/workflows/analytics-test.yml`, `.github/workflows/pdf-test.yml`, `.github/workflows/theme-adapter-demos-test.yml`
- Modify: `tests/workflows.test.sh`

**Interfaces:**
- Produces: имена конечных джобов без префикса области. Полное имя check'а — `<Группа> / <Промежуточный> / <Конечный>`, например `Library / React / Markup`.

- [ ] **Step 1: Дописать проверку в `tests/workflows.test.sh` перед `finish`.**

```bash
# Job names carry no area prefix: the group in the run's sidebar already names the area, so the
# check reads "Library / React / Markup", not "Library / React / Library React · Markup".
PREFIXED="$(grep -n '^    name: .*·' .github/workflows/*.yml)"
assert_eq "no job name repeats its area" "" "$PREFIXED"
```

- [ ] **Step 2: Убедиться, что проверка падает.**

Run: `PATH="$S/bin:$PATH" bash tests/workflows.test.sh`
Expected: `FAIL  no job name repeats its area`, в `actual:` около 28 строк, например `library-core.yml:22:    name: Library Core · Unit PostCSS`.

- [ ] **Step 3: Переименовать.**

Имена джобов в workflow — это строки `name:` с отступом ровно 4 пробела. У шагов отступ больше. В оркестраторе `library.yml` префиксов с `·` нет, его замена не затронет.

```bash
sed -i -E \
  -e 's/^(    name: "?)(Library|Creator) [A-Za-z]+ · /\1/' \
  -e 's/^(    name: "?)(Analytics|PDF|Theme Adapter Demos) · /\1/' \
  .github/workflows/*.yml
```

Ожидаемый результат — `grep -n '^    name:' .github/workflows/{library,creator}-*.yml .github/workflows/{analytics,pdf,theme-adapter-demos}-test.yml`:

| Файл | Имена джобов |
|---|---|
| library-core | Unit PostCSS |
| library-react | Markup; A11Y & E2E; SCR Test |
| library-angular | A11Y & E2E; Markup & SCR |
| library-vue | A11Y & E2E; SCR |
| library-js | A11Y & E2E; SCR |
| creator-core | Unit & Presets & PostCSS |
| creator-react | Example & A11Y; E2E; SCR Test; SCR Legacy |
| creator-angular | Markup & Example & A11Y; E2E; SCR |
| creator-vue | Example & A11Y; E2E; SCR |
| creator-js | Example & A11Y; E2E; SCR |
| analytics-test | Unit; E2E |
| pdf-test | Test |
| theme-adapter-demos-test | `"SCR: ${{ matrix.app }}"` (кавычки остаются: в значении есть `:`) |

- [ ] **Step 4: Тесты и actionlint.**

Run: `PATH="$S/bin:$PATH" bash tests/workflows.test.sh`
Expected: все `ok`, код 0.

Run: `"$S/bin/actionlint.exe" .github/workflows/*.yml`
Expected: без вывода, код 0.

---

### Task 4: Групповые workflows Library и Creator

**Files:**
- Create: `.github/workflows/library-test.yml`, `.github/workflows/creator-test.yml`
- Modify: `tests/workflows.test.sh`

**Interfaces:**
- Consumes: `library-react.yml` без input'а `scr-update` (Task 2).
- Produces:
  - `library-test.yml` — `on: workflow_call` без inputs;
  - `creator-test.yml` — inputs `creator-ref` (string), `creator-pr` (string), `scr-blocking` (boolean, по умолчанию `true`).
  
  Оба вызываются из survey-library в Task 6.

- [ ] **Step 1: Дописать проверки в `tests/workflows.test.sh` перед `finish`.**

```bash
# The Library and Creator groups call every workflow of their area.
for AREA in library creator; do
  for PART in core react angular vue js; do
    assert_contains "$AREA-test.yml calls $AREA-$PART.yml" \
      "$(cat ".github/workflows/$AREA-test.yml" 2>/dev/null)" "/.github/workflows/$AREA-$PART.yml@"
  done
done
# creator-core has no screenshot job, the other four take the switch.
BLOCKING="$(grep -c 'scr-blocking: ${{ inputs.scr-blocking }}' .github/workflows/creator-test.yml 2>/dev/null)"
assert_eq "creator-test.yml passes scr-blocking to the four screenshot workflows" 4 "${BLOCKING:-0}"
```

- [ ] **Step 2: Убедиться, что проверки падают.**

Run: `PATH="$S/bin:$PATH" bash tests/workflows.test.sh`
Expected: 10 × `FAIL  … calls …` и `FAIL  creator-test.yml passes scr-blocking …`, код 1.

- [ ] **Step 3: Создать `.github/workflows/library-test.yml`.**

```yaml
# The Library group of the survey-library CI run. GitHub groups the run's sidebar by the top-level
# jobs of the caller workflow, so the library-* workflows are called from here. Port of the
# Library*Test stages of library.yml (keep in sync while it lives).
name: Library

on: workflow_call

jobs:
  core:
    name: Core
    uses: surveyjs/azure-pipelines/.github/workflows/library-core.yml@gha-migration
    secrets: inherit

  react:
    name: React
    uses: surveyjs/azure-pipelines/.github/workflows/library-react.yml@gha-migration
    secrets: inherit

  angular:
    name: Angular
    uses: surveyjs/azure-pipelines/.github/workflows/library-angular.yml@gha-migration
    secrets: inherit

  vue:
    name: Vue
    uses: surveyjs/azure-pipelines/.github/workflows/library-vue.yml@gha-migration
    secrets: inherit

  js:
    name: JS
    uses: surveyjs/azure-pipelines/.github/workflows/library-js.yml@gha-migration
    secrets: inherit
```

- [ ] **Step 4: Создать `.github/workflows/creator-test.yml`.**

```yaml
# The Creator group of the survey-library CI run (library-test.yml says why groups exist). Port of
# the Creator*Test stages of library.yml (keep in sync while it lives).
name: Creator

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
      scr-blocking:
        description: false - failed screenshot jobs do not fail the group (the baselines belong to survey-creator's own pipeline)
        type: boolean
        default: true

jobs:
  core:
    name: Core
    uses: surveyjs/azure-pipelines/.github/workflows/creator-core.yml@gha-migration
    with:
      creator-ref: ${{ inputs.creator-ref }}
      creator-pr: ${{ inputs.creator-pr }}
    secrets: inherit

  react:
    name: React
    uses: surveyjs/azure-pipelines/.github/workflows/creator-react.yml@gha-migration
    with:
      creator-ref: ${{ inputs.creator-ref }}
      creator-pr: ${{ inputs.creator-pr }}
      scr-blocking: ${{ inputs.scr-blocking }}
    secrets: inherit

  angular:
    name: Angular
    uses: surveyjs/azure-pipelines/.github/workflows/creator-angular.yml@gha-migration
    with:
      creator-ref: ${{ inputs.creator-ref }}
      creator-pr: ${{ inputs.creator-pr }}
      scr-blocking: ${{ inputs.scr-blocking }}
    secrets: inherit

  vue:
    name: Vue
    uses: surveyjs/azure-pipelines/.github/workflows/creator-vue.yml@gha-migration
    with:
      creator-ref: ${{ inputs.creator-ref }}
      creator-pr: ${{ inputs.creator-pr }}
      scr-blocking: ${{ inputs.scr-blocking }}
    secrets: inherit

  js:
    name: JS
    uses: surveyjs/azure-pipelines/.github/workflows/creator-js.yml@gha-migration
    with:
      creator-ref: ${{ inputs.creator-ref }}
      creator-pr: ${{ inputs.creator-pr }}
      scr-blocking: ${{ inputs.scr-blocking }}
    secrets: inherit
```

- [ ] **Step 5: Тесты и actionlint.**

Run: `PATH="$S/bin:$PATH" bash tests/workflows.test.sh`
Expected: все `ok`, код 0.

Run: `"$S/bin/actionlint.exe" .github/workflows/*.yml`
Expected: без вывода, код 0. actionlint проверяет входы локальных вызовов, но эти вызовы удалённые (`surveyjs/azure-pipelines/...@ref`). Поэтому имена inputs нужно сверить глазами с `on.workflow_call.inputs` вызываемых файлов.

---

### Task 5: Afterparty с `result` и удаление оркестратора

**Files:**
- Create: `.github/workflows/afterparty.yml`
- Delete: `.github/workflows/library.yml`
- Modify: `.github/actions/result/action.yml`, `.github/actions/result/check.sh` (только комментарии)
- Modify: `tests/result.test.sh`, `tests/workflows.test.sh`

**Interfaces:**
- Consumes: action `result` — input `needs` (строка `toJSON(needs)`), внутри передаётся в `check.sh` через env `NEEDS`.
- Produces: `afterparty.yml` — `on: workflow_call`, input `needs` (string, required), джоб `result` с именем `result`. Check в PR: `Afterparty / result`. Вызывается из survey-library в Task 6.

- [ ] **Step 1: Дописать тесты.**

В `tests/result.test.sh` перед `finish`:

```bash
# [scr_update]: the test groups are skipped by their own condition, SCR Update ran.
run '{"lint":{"result":"success"},"options":{"result":"success"},"scr-update":{"result":"success"},"library":{"result":"skipped"},"creator":{"result":"skipped"},"analytics":{"result":"skipped"},"pdf":{"result":"skipped"},"theme-adapter-demos":{"result":"skipped"}}'
assert_eq "[scr_update]: skipped test groups pass" 0 "$STATUS"

run '{"lint":{"result":"success"},"options":{"result":"success"},"scr-update":{"result":"skipped"},"library":{"result":"success"},"creator":{"result":"failure"}}'
assert_eq "a failed group fails the check" 1 "$STATUS"
assert_contains "the failed group is named" "$OUT" "::error::creator=failure"
```

В `tests/workflows.test.sh` перед `finish`:

```bash
# Afterparty carries the single required check. The orchestrator is gone: the graph lives in
# survey-library's caller workflow, where its top-level jobs become the run's groups.
assert_contains "afterparty.yml runs the result action" \
  "$(cat .github/workflows/afterparty.yml 2>/dev/null)" "/.github/actions/result@"
assert_eq "the orchestrator library.yml is gone" "no" \
  "$([ -e .github/workflows/library.yml ] && echo yes || echo no)"
```

- [ ] **Step 2: Убедиться, что новые проверки `workflows.test.sh` падают.**

Run: `PATH="$S/bin:$PATH" bash tests/workflows.test.sh`
Expected: `FAIL  afterparty.yml runs the result action` и `FAIL  the orchestrator library.yml is gone`, код 1.

Run: `PATH="$S/bin:$PATH" bash tests/result.test.sh`
Expected: код 0. Логика `check.sh` не меняется, новые случаи закрепляют её на ключах групп.

- [ ] **Step 3: Создать `.github/workflows/afterparty.yml`.**

```yaml
# The Afterparty group of the survey-library CI run: everything after the tests. result - the single
# required status check, "Afterparty / result" - runs on every run; Staging and Backport
# (sub-projects B and C) will follow it on pushes, so they run only when everything passed.
name: Afterparty

on:
  workflow_call:
    inputs:
      needs:
        description: toJSON(needs) of the calling job - every top-level job of the caller workflow before it
        type: string
        required: true

jobs:
  result:
    name: result
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - name: Result
        uses: surveyjs/azure-pipelines/.github/actions/result@gha-migration
        with:
          needs: ${{ inputs.needs }}
```

- [ ] **Step 4: Удалить оркестратор.**

Run: `rm .github/workflows/library.yml`

Индекс git не трогать: удаление попадёт в коммит пользователя.

- [ ] **Step 5: Обновить комментарии action `result`.**

В `.github/actions/result/action.yml` поле `description` заменить на:

```yaml
description: >
  The single required status check of the survey-library CI ("Afterparty / result"): fails when a
  job of the caller workflow failed or was cancelled. A job skipped by its own condition
  (scr_update, Theme Adapter Demos outside a PR to master) is fine.
```

В `.github/actions/result/check.sh` строки 2–5 заменить на:

```bash
# Usage (env): NEEDS - toJSON(needs) of the caller workflow's afterparty job.
# Fails when a needed job ended as failure or cancelled. A job skipped by its own condition
# (scr_update, Theme Adapter Demos outside a PR to master) is fine. A failed options job is not: it
# skips every test group, and without this check the run would go green having tested nothing.
```

- [ ] **Step 6: Тесты и actionlint.**

Run: `PATH="$S/bin:$PATH" bash tests/run.sh`
Expected: код 0.

Run: `"$S/bin/actionlint.exe" .github/workflows/*.yml`
Expected: без вывода, код 0.

Run: `grep -rn "workflows/library\.yml" .github tests README.md`
Expected: пусто.

---

### Task 6: Граф в вызывающем workflow survey-library

**Files:**
- Modify: `C:\Users\bsadv\WebstormProjects\survey-library\.github\workflows\library.yml` (ветка `gha-migration` survey-library)

**Interfaces:**
- Consumes:
  - `library-scr-update.yml` (Task 2), `library-test.yml`, `creator-test.yml` (Task 4), `afterparty.yml` (Task 5);
  - без изменений: `analytics-test.yml` (`analytics-ref`, `analytics-pr`), `pdf-test.yml` (`pdf-ref`, `pdf-pr`), `theme-adapter-demos-test.yml` (`demos-pr`, `creator-ref`, `creator-pr`);
  - actions `options` и `npm-install`.
- Produces: check `Afterparty / result` и группы в панели прогона.

- [ ] **Step 1: Проверить ветку survey-library.**

Run: `git -C /c/Users/bsadv/WebstormProjects/survey-library branch --show-current`
Expected: `gha-migration`. Если ветка другая, остановиться и спросить пользователя.

- [ ] **Step 2: Заменить содержимое файла целиком.**

```yaml
# survey-library CI on GitHub Actions. The jobs live in surveyjs/azure-pipelines; this file holds
# their graph - a port of azure-pipelines' library.yml (keep in sync while it lives). GitHub groups
# the run's sidebar by the top-level jobs of the workflow that started the run, so every top-level
# job here that calls a workflow is a group: SCR Update, Library, Creator, ..., Afterparty.
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

defaults:
  run:
    shell: bash --noprofile --norc {0}

jobs:
  lint:
    name: Lint
    # The marker the l10n, docs and release commits carry - the one the Azure pipeline honours.
    # Not [skip ci]: that would also skip tagged-release.yml on the release tag.
    if: ${{ !contains(github.event.head_commit.message, '[azurepipelines skip]') }}
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v5
        with:
          persist-credentials: false
          fetch-depth: 1
      - name: Install
        uses: surveyjs/azure-pipelines/.github/actions/npm-install@gha-migration
        with:
          directories: .
          cache: survey-library
          # eslint-plugin-surveyjs comes from a git URL (surveyjs/eslint-surveyjs): take its tip
          update: . eslint-plugin-surveyjs
          token: ${{ secrets.SURVEYJS_BOT_TOKEN }}
      - name: Lint
        run: npm run lint

  # The gate of the graph. It runs on every event - outside a PR its outputs are {} and "" - so the
  # groups after it are skipped only when it failed (a bad tag) or the run carries the marker. A job
  # skipped on a push would skip everything after it, Afterparty with Staging and Backport included.
  options:
    name: Options
    if: ${{ !contains(github.event.head_commit.message, '[azurepipelines skip]') }}
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    outputs:
      scr_update: ${{ steps.options.outputs.scr_update }}
      pr_tags: ${{ steps.options.outputs.pr_tags }}
    steps:
      - id: options
        uses: surveyjs/azure-pipelines/.github/actions/options@gha-migration

  scr-update:
    name: SCR Update
    needs: options
    if: (needs.options.outputs.scr_update || '') != ''
    uses: surveyjs/azure-pipelines/.github/workflows/library-scr-update.yml@gha-migration
    secrets: inherit

  library:
    name: Library
    needs: options
    if: (needs.options.outputs.scr_update || '') == ''
    uses: surveyjs/azure-pipelines/.github/workflows/library-test.yml@gha-migration
    secrets: inherit

  creator:
    name: Creator
    needs: options
    if: (needs.options.outputs.scr_update || '') == ''
    uses: surveyjs/azure-pipelines/.github/workflows/creator-test.yml@gha-migration
    with:
      creator-ref: ${{ github.base_ref || github.ref_name }}
      creator-pr: ${{ fromJSON(needs.options.outputs.pr_tags || '{}').CREATOR || '' }}
    secrets: inherit

  analytics:
    name: Analytics
    needs: options
    if: (needs.options.outputs.scr_update || '') == ''
    uses: surveyjs/azure-pipelines/.github/workflows/analytics-test.yml@gha-migration
    with:
      analytics-ref: ${{ github.base_ref || github.ref_name }}
      analytics-pr: ${{ fromJSON(needs.options.outputs.pr_tags || '{}').ANALYTICS || '' }}
    secrets: inherit

  pdf:
    name: PDF
    needs: options
    if: (needs.options.outputs.scr_update || '') == ''
    uses: surveyjs/azure-pipelines/.github/workflows/pdf-test.yml@gha-migration
    with:
      pdf-ref: ${{ github.base_ref || github.ref_name }}
      pdf-pr: ${{ fromJSON(needs.options.outputs.pr_tags || '{}').PDF || '' }}
    secrets: inherit

  theme-adapter-demos:
    name: Theme Adapter Demos
    needs: options
    if: (needs.options.outputs.scr_update || '') == '' && github.event_name == 'pull_request' && github.base_ref == 'master'
    uses: surveyjs/azure-pipelines/.github/workflows/theme-adapter-demos-test.yml@gha-migration
    with:
      demos-pr: ${{ fromJSON(needs.options.outputs.pr_tags || '{}').ADAPTERS || '' }}
      creator-ref: ${{ github.base_ref || github.ref_name }}
      creator-pr: ${{ fromJSON(needs.options.outputs.pr_tags || '{}').CREATOR || '' }}
    secrets: inherit

  # Everything after the tests: result - the single required status check, "Afterparty / result" -
  # then Staging and Backport on pushes. always(): result reports on every run, a failed or
  # cancelled one included.
  afterparty:
    name: Afterparty
    needs: [lint, options, scr-update, library, creator, analytics, pdf, theme-adapter-demos]
    if: ${{ always() && !contains(github.event.head_commit.message, '[azurepipelines skip]') }}
    uses: surveyjs/azure-pipelines/.github/workflows/afterparty.yml@gha-migration
    with:
      needs: ${{ toJSON(needs) }}
    secrets: inherit
```

- [ ] **Step 3: Сверить и проверить.**

Run (из azure-pipelines): `EXTRA_WORKFLOWS=../survey-library/.github/workflows/library.yml PATH="$S/bin:$PATH" bash tests/workflows.test.sh`
Expected: все `ok`. Ссылки вызывающего файла указывают на существующие файлы.

Run: `cd ../survey-library && "$S/bin/actionlint.exe" .github/workflows/library.yml`
Expected: без вывода, код 0.

Run: `grep -n "always()" ../survey-library/.github/workflows/library.yml`
Expected: одна строка — `if:` джоба `afterparty`.

Сверка с оркестратором, удалённым в Task 5: `git -C /c/Users/bsadv/WebstormProjects/azure-pipelines show HEAD:.github/workflows/library.yml`. Нужно, чтобы совпадали:
- шаги Lint;
- outputs Options;
- `*-ref` и теги `pr_tags` у Creator, Analytics, PDF и Theme Adapter Demos;
- условие `base_ref == 'master'` у Demos.

Намеренно отличаются только три вещи: нет `!cancelled() && needs.options.result != 'failure'`, нет `cross-repo-scr-blocking`, а `result` переехал в Afterparty.

---

### Task 7: Итоговая проверка и передача пользователю

**Files:** нет изменений.

- [ ] **Step 1: Полный прогон.**

Run: `PATH="$S/bin:$PATH" bash tests/run.sh`
Expected: код 0.

Run: `"$S/bin/actionlint.exe" .github/workflows/*.yml` и `cd ../survey-library && "$S/bin/actionlint.exe" .github/workflows/library.yml`
Expected: без вывода.

Run: `git status --short` в обоих репозиториях.
Expected:
- в azure-pipelines — `library-test.yml`, `creator-test.yml`, `library-scr-update.yml`, `afterparty.yml`, удалённый `library.yml`, 13 тестовых workflows, `actions/result/*`, `tests/*`, спецификация и этот план;
- в survey-library — только `.github/workflows/library.yml`.

- [ ] **Step 2: Передать пользователю шаги выкладки и сценарии.** Их выполняет человек.

Выкладка:
1. Закоммитить и запушить azure-pipelines `gha-migration`.
2. Сразу за ним закоммитить и запушить survey-library `gha-migration`. Между двумя push прогон PR #11969 падает: старый вызывающий файл ссылается на удалённый `library.yml`.

Сценарии на PR #11969 («Re-run all jobs» или новый push):
1. **Обычный прогон.**
   - В панели: Lint, Options и группы SCR Update (пропущена), Library, Creator, Analytics, PDF, Theme Adapter Demos (если PR в master), Afterparty.
   - Внутри Library: Core / Unit PostCSS, React / Markup и т. д.
   - Набор конечных джобов совпадает с прошлым прогоном.
   - `Afterparty / result` отражает итог.
2. **Коммит с `[scr_update]`.** Выполняются Lint, Options, SCR Update / Library React и Afterparty / result. Тестовые группы пропущены, `result` зелёный.
3. **Заголовок с `[creator: abc]`.** Options красный, группы пропущены, `Afterparty / result` красный.

После мержа в master (сценарий 8 подпроекта A):
1. **Push.** Options выполняется с `{}`, Theme Adapter Demos и SCR Update пропущены, тестовые группы проходят, `result` зелёный.
2. **Коммит с `[azurepipelines skip]`.** Пропущено всё.
