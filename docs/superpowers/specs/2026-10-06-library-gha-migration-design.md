# Спецификация: перенос library.yml на GitHub Actions

> Статус: одобрена 2026-10-06. План реализации: superpowers:writing-plans, подпроекты A–E (раздел 7).

## 1. Цель и рамки

**Зачем:** уйти от своих Azure-агентов, ускорить PR-прогоны, свести CI на одну платформу (GitHub). Следующими туда же переедут creator, analytics и pdf.

**Что переносим:** весь `library.yml`: Lint, Options, 13 тестовых стадий, Staging, Backport. Переносим на GitHub-hosted раннеры `ubuntu-24.04`.

**Что не переносим:** creator.yml, analytics.yml, pdf.yml, theme-adapter-demos.yml и release.yml остаются в Azure. ai-flaky-fix временно выключается.

**Подход:**
- сначала эталонный перенос один к одному в теневом режиме;
- затем ускорение в той же тени;
- одно переключение.

**Критерии успеха:**
- те же джобы, условия и результаты, что в Azure;
- медиана времени PR-прогона не больше, чем в Azure;
- откат за минуты;
- ни один backport и ни один staging-коммит не потерян и не задвоен.

**Исходные данные:**
- тариф организации — Team, это до 60 параллельных джобов, а бюджет прогона — не больше 40 джобов;
- все затронутые репозитории публичные, кроме `surveyjs/service` и `surveyjs-site-data`;
- git-зависимости `surveyjs/eslint-surveyjs` и `surveyjs/survey-utils` публичные;
- Playwright: в survey-library и survey-creator закреплена версия 1.60.0, в theme-adapter-demos — `^1.62.1`.

**Принятые ограничения:**
- Кросс-репо скриншот-эталоны (creator, analytics, demos) поддерживают их Azure-пайплайны. На GitHub-раннерах их нельзя перегенерировать до переезда этих репозиториев.
- Логи и артефакты публичного репозитория видны всем.

## 2. Размещение кода и вызов

### surveyjs/azure-pipelines (новые каталоги; Azure-шаблоны не меняются)
```
.github/actions/
  npm-install/               ← templates/utils/npm.yml
  checkout-pr/               ← блок «Switch to PR $(PR)»: pull/N/merge → fallback head + ::warning::
  options/                   ← pr_title_parser.yml + commit_message_parser.yml
  publish-test-results/      ← PublishBuildArtifacts(test-results) + PublishTestResults
  build-library/             ← templates/library/*/build.yml (inputs: package, extra dirs, artifact name)
  build-creator/             ← templates/creator/*/build.yml
  build-core-consumer/       ← templates/analytics/build.yml ≡ templates/pdf/build.yml
  build-theme-adapter-demos/ ← templates/theme-adapter-demos/build.yml
  claude/                    ← templates/utils/claude.yml
.github/workflows/
  library.yml                ← library.yml (on: workflow_call, оркестратор)
  library-{core,react,angular,vue,js}.yml   ← templates/library/*/test.yml
  creator-{core,react,angular,vue,js}.yml   ← templates/creator/*/test.yml (без «SCR Update»: в library он не запускается)
  analytics-test.yml (без «SCR Update»), pdf-test.yml, theme-adapter-demos-test.yml
  library-staging.yml        ← templates/library/staging.yml
  backport.yml               ← templates/utils/backport.yml
```
- **Тестовые workflows** — по одному на каждый Azure `test.yml`. Их без изменений переиспользуют будущие переезды creator, analytics и pdf.
- **Файлы-двойники Azure-шаблонов** получают в шапке комментарий «синхронизировать с …». Правило синхронизации описано в README и действует, пока живы Azure-версии.
- **Ссылки.** Все вложенные `uses: surveyjs/azure-pipelines/...` указывают на один статический ref: reusable workflow не умеет ссылаться на свой ref относительно, а `./` указывает на workspace survey-library.
  - Разработка идёт в ветке `gha-migration` со ссылками `@gha-migration`; при мерже `sed` переводит их на `@main`.
  - Принятый риск: composite actions скачиваются при старте каждого джоба, поэтому push в main посреди прогона может смешать версии.
- **Промпт backport** читается с диска, из checkout azure-pipelines, который раннер скачал для action: `$GITHUB_ACTION_PATH/../../../prompts/backport-conflicts.md`.
- **Лимиты:** вложенность 3 при лимите 10, уникальных reusable workflows 16 при лимите 50.

### survey-library: `.github/workflows/library.yml`, на master, V2 и V3
`pull_request` берёт workflow из merge-коммита, поэтому файл нужен на каждой базовой ветке.
- **Триггеры:** `pull_request` и `push` копируются из UI-настроек Azure, плюс `workflow_dispatch`.
- **Единственный джоб** `library`:
  - `uses: surveyjs/azure-pipelines/.github/workflows/library.yml@main`, `secrets: inherit`, `permissions: contents: read`;
  - `if: ${{ !contains(github.event.head_commit.message, '[azurepipelines skip]') }}`: прогон с меткой пропускается целиком. Метка **не** меняется на `[skip ci]`, иначе на релизном теге пропустился бы и `tagged-release.yml`.
- **Concurrency:**
  - для PR — группа `library-pr-<N>`, `cancel-in-progress: true`;
  - для push — уникальная группа на прогон (`github.run_id`), иначе отменится ожидающий прогон master вместе с его backport;
  - в вызываемых workflow своих групп concurrency нет.

## 3. Граф джобов и условия (эталонный перенос)

**Значения, которые раньше задавал variables.yml**, теперь вычисляются в выражениях:
- `is_stage` = `github.event_name == 'push' && contains(fromJSON('["master","main","V3","V2"]'), github.ref_name)`;
- `branch` = `github.base_ref || github.ref_name`;
- `siteDataRef` = `github.ref_name == 'master' && 'V3' || 'V2'` — переносим как есть, вместе со странностью «V3 → site-data V2».

**options** — только для PR: `if: github.event_name == 'pull_request'`.
- Заголовок PR и сообщение head-коммита читаются через API с `github.token`, а не из payload: так «Re-run all jobs» видит изменённый заголовок, и запросы работают в fork PR.
- Выходы:
  - `scr_update`;
  - `pr_tags` — JSON со всеми тегами `[name: value]`.
- Номера companion PR проверяются по `^[0-9]+$` до подстановки в скрипт.
- Ссылки на companion PR публикуются в `$GITHUB_STEP_SUMMARY`.
- На push джоба нет, потребители подставляют значения сами: `fromJSON(needs.options.outputs.pr_tags || '{}')`, `(needs.options.outputs.scr_update || '') == ''`.

**Граф** — `needs` и условия стадий как в Azure.

Общее правило для тестовых джобов: `needs: options` и `if: ${{ !cancelled() && needs.options.result != 'failure' && <условие> }}`. Обычное `success()` пропускает джоб, если пропущена зависимость.

| Джоб | needs | условие |
|---|---|---|
| lint | — | — (`npm update eslint-plugin-surveyjs` + `npm run lint`) |
| library-core, -angular, -vue, -js; creator-*; analytics; pdf | options | `scr_update == ''`; creator, analytics, pdf, demos получают `pr` из `pr_tags` (CREATOR / ANALYTICS / PDF / ADAPTERS) |
| library-react | options | всегда; `scr_update` на вход. Внутренние джобы: при пустом — Markup / A11Y & E2E / SCR Test; при непустом — SCR Update, только `pull_request` и `head.repo.full_name == github.repository` |
| theme-adapter-demos | options | `scr_update == ''` и `pull_request` в master; `LIBRARY_PR` пустой, `CREATOR_PR` из CREATOR |
| staging | 5 джобов library | `is_stage` и `!contains(needs.*.result, 'failure')` |
| backport | library ×5, creator ×5, analytics, pdf (без demos) | `github.ref_name == 'master'` и `!contains(needs.*.result, 'failure')` |
| result | options, lint, все тестовые | `always()` |

**result** — единственный required check `library / result`.
- Красный, если любой джоб из `needs` упал или был отменён. Сюда же относится упавший options: иначе тесты бы пропустились, а check вышел бы ложно-зелёным.
- `skipped` — норма: пропуск по `scr_update`, options на push.
- Список временно неблокирующих кросс-репо SCR передаётся input'ом и в проверке игнорируется. На самих джобах-вызовах `continue-on-error` недоступен.

**Перенос шагов:**
- `defaults.run.shell: bash --noprofile --norc {0}` (без `-e`, как в Azure), в composite actions `shell:` задаётся явно;
- `pwsh`-шаги идут как `shell: pwsh`;
- `timeout-minutes: 60` внутри вызываемых workflow;
- `##vso[task.setvariable;isOutput]` заменяется на `$GITHUB_OUTPUT` + `jobs.<id>.outputs`;
- `logissue` заменяется на `::warning::`/`::error::`;
- `uploadsummary` и `complete SucceededWithIssues` заменяются на `$GITHUB_STEP_SUMMARY` (+ warning);
- `$(Build.SourcesDirectory)` → `$GITHUB_WORKSPACE`, `$(Agent.TempDirectory)` → `$RUNNER_TEMP`;
- для PR-переменных используется `github.event.pull_request.*`.

**Checkout:**
- Продукт кладётся в корень workspace, вложенные репозитории — в `path: survey-library` и `path: survey-creator`, как в Azure-раскладке `s/…`.
- Companion-репозитории берутся с `ref: branch`, затем `checkout-pr` при наличии тега.

**Артефакты:**
- `actions/upload-artifact@v4` с прежними именами (`Library_React_E2E`, `SurveyJSLibraryBuild*` и т. д.), `overwrite: true`;
- для `.report` у demos — `include-hidden-files: true`;
- отчёты: `mikepenz/action-junit-report` с `annotate_only` — аннотации плюс полный отчёт в job summary.

## 4. Окружение, кэш, секреты, безопасность

**Окружение:**
- `runs-on: ubuntu-24.04`;
- `actions/setup-node` с Node той же версии, что на агентах Azure, и `package-manager-cache: false`, потому что lock-файлов нет;
- `PUPPETEER_SKIP_DOWNLOAD=true`;
- браузеры ставит существующий `postinstall: playwright install chromium`, к нему добавляется `npx playwright install-deps chromium`;
- `~/.cache/ms-playwright` кэшируется по версии Playwright;
- Chrome для Karma — тот, что есть в образе раннера;
- контейнер Playwright не используем из-за разных версий и Karma под root. Вернёмся к нему, только если в тени пиксели будут меняться от прогона к прогону.

**Кэш npm** (action `npm-install`):
- логика npm.yml сохраняется: параллельная установка по каталогам, git-auth через `GIT_CONFIG_*`, ssh переписывается на https;
- кэшируется `~/.npm/_cacache` через явные `actions/cache/restore` и `actions/cache/save`, потому что post-шаги вложенных composite actions не выполняются;
- ключ — `npm-<семейство>-<ISO-неделя>-<hash набора package.json>` (`cache-key.sh`); семейства по имени основного репозитория: survey-library, survey-creator, survey-analytics, survey-pdf, theme-adapter-demos;
- сохраняет сам `npm-install` после успешной установки, если не было точного совпадения. У джобов с разным набором каталогов ключи разные, и каждый набор получает свою запись. PR, который не трогает `package.json`, точно попадает в запись базовой ветки и ничего не сохраняет. Отдельного джоба прогрева нет;
- при промахе `restore-keys` — `npm-<семейство>-<неделя>-`: только записи семейства за эту же неделю. Каждая неделя начинается с пустого кэша и не копит устаревшие tarball;
- неделя в ключе нужна потому, что записи кэша неизменяемы, а без lock-файла версии зависимостей уходят вперёд;
- PR видит кэш своего merge-ref, базовой ветки и master: PR в V2 сначала берёт кэш V2, потом master;
- если записи всех наборов × 3 ветки не укладываются в 10 ГБ, переходим на один общий `~/.npm` на ветку.

**Секреты организации:**
- `SURVEYJS_BOT_TOKEN` — бывший PAT `GITHUB_TOKEN` из pipeline-secrets; внутри шагов экспортируется как env `GITHUB_TOKEN`, поэтому скрипты не меняются;
- `ANTHROPIC_API_KEY`;
- `TRANSLATION_API_KEY`.

**Токены и права:**
- Workflow `GITHUB_TOKEN` только на чтение.
- PAT используется на чтение приватных service и site-data и на всю запись: push, `gh pr create`, метки. PAT нужен, чтобы push перезапускал CI.
- `actions/checkout` всегда с `persist-credentials: false`. PAT получают только нужные шаги, через env и `GIT_CONFIG_*`.
- Fork PR и Dependabot работают без секретов: git-зависимости публичные, а токен для них нужен только из-за лимитов на анонимный доступ.

**Безопасность вывода:**
- Шаги, которые печатают текст из репозитория или от агента, заворачиваются в `::stop-commands::<random>`; `::warning::` выводится через помощник, который на время включает команды.
- Для приватных репозиториев в логах только число изменённых файлов.

**Агент Claude** (action `claude`) работает в `docker run`:
- внутри только копия рабочего дерева, у которой `.git` доступен лишь на чтение, и промпт; сеть открыта для API;
- агент не видит `$GITHUB_ENV`/`$GITHUB_OUTPUT`, `_actions`, `_temp` и файл с токеном;
- ключ вычищается из артефактов, потому что GitHub маскирует секреты только в логах;
- шаг с агентом никогда не завершается ошибкой, решение принимает вызывающий шаг: та же семантика `skipped.txt`/`done.txt`/`result.json`.

## 5. Скриншоты, Staging, Backport

**Скриншоты:**
- В тени SCR-тесты гоняются на текущих эталонах. Фиксируем, какие наборы расходятся с Azure, и стабильны ли пиксели между прогонами.
- **Эталоны survey-library** перегенерирует GitHub-джоб SCR Update; в тени берём их из его артефакта. При переключении на master, V2 и V3 мержим PR с эталонами сразу после смены required check.
- **Кросс-репо SCR** (Creator SCR ×4, Analytics E2E, Theme Adapter Demos): если расходятся, они только сигналят и не учитываются в `result`, пока их репозиторий не переедет.

**Staging** (`library-staging.yml`):
- checkout survey-library, `surveyjs-site-data` (ref `siteDataRef`, PAT) и `surveyjs/service` (ref `branch`, PAT) через `path:`;
- шаги staging.yml переносятся один в один;
- в коммитах остаётся `[azurepipelines skip]`.

**Backport** (`backport.yml`):
- переносится один в один: уровни 1, 1a, 2, 3, recover, тексты PR, лейблы, назначение исполнителей;
- Detect выдаёт `matrix` в виде `{"include":[{"target":"V2","leg":"V2"}]}` и `should_backport`;
- джоб Backport: `strategy: { matrix: ${{ fromJSON(...) }}, fail-fast: false }`, гейт по `should_backport`;
- логика «спрятать и вернуть extraheader» удаляется, так как PAT нет в `.git/config`;
- Guard забирает из docker-копии только AI-файлы и сохраняет проверки маркеров, VERDICT, пустого разрешения и посторонних изменений;
- артефакт `Backport_AI_<leg>_${{ github.run_attempt }}`, ссылка `$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID`;
- тело PR всегда дублируется в summary.

**Теневой режим через `# SHADOW-OFF:`.** Шаги, которые меняют репозитории, переносятся полностью, но пишущие строки закомментированы с меткой `# SHADOW-OFF:`:
- все `git push` — SCR Update, Staging (survey-library, site-data, service), ветка backport;
- в backport `gh pr create`, `gh label create` и назначение исполнителей;
- `build:translate` — платный API, результат которого нужен только для коммита.

Всё до записи выполняется, а в summary попадают тело PR и число изменённых файлов. Переключение — один коммит в azure-pipelines, снимающий метки; найти их можно `grep '# SHADOW-OFF:'`. Откат — revert этого коммита.

## 6. Ускорение (в тени, после совпадения эталона с Azure)

**Метрика:**
- медиана и 90-й перцентиль времени PR-прогона в GitHub против Azure за тот же период;
- отдельно — критический путь;
- бюджет — не больше 40 джобов на прогон.

**Рычаги по порядку, каждый сверяется с эталоном:**
1. Кэши npm и Playwright (раздел 4).
2. Шардирование самых длинных Playwright-джобов через matrix `--shard i/N`.
   - Каждый шард выкладывает артефакт `<прежнее имя>_<i>`, и шаблон `Library_React_*/results.json` по-прежнему его находит.
   - JUnit собирается из всех шардов.
3. Воркеры Playwright: 3–4 вместо 2 по умолчанию на 4 vCPU; следим за flaky.
4. Сборка «один раз»: build-джобы и артефакты для тестовых джобов. Включаем, только если по замерам медиана не растёт: цепочка build → build → test может удлинить критический путь.

**Критерий переключения:** результаты совпадают с Azure, и медиана времени PR ≤ Azure.

**Вне рамок:** изменения состава тестов, платные larger runners, retries.

## 7. Этапы

**Подпроекты для планов реализации**, по порядку; каждый проверяется в тени отдельно:
- **A** — общие actions (npm-install, checkout-pr, options, publish-test-results, build-*), оркестратор, тестовые workflows, `result`, вызывающий workflow;
- **B** — Staging;
- **C** — Backport и action `claude` в docker;
- **D** — ускорение (раздел 6);
- **E** — переключение: release.yml, ai-flaky-fix, README, настройки.

**0. Инвентаризация.**
- Из Azure:
  - триггеры, фильтры, сборка draft PR, auto-cancel, batching;
  - UI-переменные;
  - состав pipeline-secrets;
  - версия Node на агентах;
  - время PR-прогонов: медиана и 90-й перцентиль.
- В GitHub:
  - секреты организации;
  - разрешённые actions: `surveyjs/*`, `actions/*`, `mikepenz/action-junit-report`;
  - approval для fork PR.

**1. Эталонный перенос** в ветке `gha-migration` (разделы 2–5).

**2. Тень.**
- Вызывающий workflow на master, V2 и V3 survey-library; check не required.
- Сначала добиваемся совпадения с Azure: состав джобов, результаты, вывод staging и backport, скриншоты.
- Затем ускорение (раздел 6), пока не выполнится критерий.

**3. Переключение** (одно окно):
1. Перевести ссылки `@gha-migration` на `@main` и смержить.
2. Снять `# SHADOW-OFF:` отдельным коммитом.
3. Branch protection на master, V2 и V3: убрать Azure Library, добавить `library / result`. Check должен хотя бы раз отработать. Проверить bypass для прямых push бота (l10n, release).
4. Выключить Azure-пайплайн Library (не удалять) и перезапустить открытые PR.
5. Смержить PR с эталонами скриншотов, если они нужны.
6. `release.yml`:
   - убрать `resources.pipelines.Library` и `Library` из `$pipelines`;
   - добавить проверку через GitHub REST `/repos/surveyjs/survey-library/actions/workflows/library.yml/runs?branch=$(projectsBranch)&event=push` с токеном `$(GITHUB_TOKEN)`;
   - прогоны, у которых в `head_commit.message` есть `[azurepipelines skip]`, не учитываются;
   - последний оставшийся прогон должен быть `success`;
   - не должно быть прогонов в статусах `queued`, `in_progress`, `waiting`, `requested`, `pending`;
   - фильтр по ветке — осознанное отличие от текущей проверки Azure.
7. `ai-flaky-fix.yml`: `resources.pipelines.Library.trigger: none` и комментарий о паузе до переноса на GitHub.
8. README: где теперь CI, правило синхронизации двойников, «Re-run all jobs» для изменённого заголовка PR.

**4. Вывод из эксплуатации** через 2–4 стабильные недели:
- удалить `azure-pipelines/library.yml` в survey-library, Azure-пайплайн Library, а также `library.yml` и `templates/library/**` здесь;
- шаблоны creator, analytics, pdf, demos, backport и claude остаются: ими пользуются другие пайплайны.

**Откат:**
1. Revert коммита, который снял `# SHADOW-OFF:`.
2. Вернуть required check Azure Library и включить пайплайн.
3. Revert PR с эталонами.

## 8. Проверка

- `actionlint` по всем новым `.github/**` в azure-pipelines и по вызывающему workflow.
- **Тестовые PR в тени:**
  1. обычный PR в master;
  2. `[creator: N]` и `[adapters: N]`, в том числе конфликтующий companion: fallback на head с warning;
  3. коммит `[scr_update]`: только SCR Update, `result` зелёный;
  4. невалидный тег: `result` красный;
  5. PR в V2: Creator SCR Legacy;
  6. PR из форка;
  7. правка заголовка + «Re-run all jobs».
- **Push в master:**
  - Staging: в summary изменения docs;
  - Backport `[backport:V2]`: чистый вариант, конфликт через агента в docker с принятием и отказом Guard, несколько флагов;
  - коммит `[azurepipelines skip]`: прогон пропущен.
- **Безопасность:** строки `::set-output` и `::warning::` в cherry-pick'нутом файле ничего не выполняют.
- **После переключения:**
  - первые реальные backport и staging-коммиты проверяются вручную;
  - release с `npmPublishArgs --dry-run` проходит новую проверку.
