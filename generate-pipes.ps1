param (
    [string]$TargetBranch = "all" 
)

# --- НАСТРОЙКИ ВЕРСИЙ (ФИЛЬТРЫ) ---
# Теперь мы описываем каждую ветку, её ID проекта и тег публикации NPM
$versions = @(
    @{ BranchName = "master"; BranchNewName = "main"; ProjectId = "d79f2855-7b94-4261-9daf-4cace0a06c03"; NpmPublishTag = "latest" },
    @{ BranchName = "V3";     BranchNewName = "V3";   ProjectId = "2cf848f9-83d5-4ec4-b2e3-ef3321ccc99f"; NpmPublishTag = "next" }
)

# Фильтруем версии, если запущено для конкретной ветки
if ($TargetBranch -ne "all") {
    $versions = $versions | Where-Object { $_.BranchName -eq $TargetBranch }
}
# ---------------------------

# Конфигурация проектов
$projects = @(
    @{
        Name       = "Library"
        SourceDir  = "libraries/library"
        TargetRepo = "../survey-library"
    },
    @{
        Name       = "Creator"
        SourceDir  = "libraries/creator"
        TargetRepo = "../survey-creator"
    },
    @{
        Name       = "Analytics"
        SourceDir  = "libraries/analytics"
        TargetRepo = "../survey-analytics"
    },
    @{
        Name       = "PDF"
        SourceDir  = "libraries/pdf"
        TargetRepo = "../survey-pdf"
    },
    @{
        Name       = "Custom Widgets"
        SourceDir  = "libraries/custom-widgets"
        TargetRepo = "../custom-widgets"
    },
    @{
        Name       = "Angular CLI"
        SourceDir  = "libraries/angular-cli"
        TargetRepo = "../surveyjs_angular_cli"
    },
    @{
        Name       = "React Quickstart"
        SourceDir  = "libraries/react-quickstart"
        TargetRepo = "../surveyjs_react_quickstart"
    },
    @{
        Name       = "Vue3 Quickstart"
        SourceDir  = "libraries/vue3-quickstart"
        TargetRepo = "../surveyjs_vue3_quickstart"
    },
    @{
        Name       = "Service"
        SourceDir  = "libraries/service"
        TargetRepo = "../service"
    },
    @{
        Name       = "Site Demos"
        SourceDir  = "libraries/site-demos"
        TargetRepo = "../surveyjsio-site-tests"
    }
)

Write-Host ">>> Starting generation for branch: $TargetBranch <<<`n" -ForegroundColor Yellow

# ГЛАВНЫЙ ЦИКЛ ПО ВЕРСИЯМ (V3, master и т.д.)
foreach ($ver in $versions) {
    $currentBranch = $ver.BranchName
    $newBranchName = $ver.BranchNewName
    $currentProject = $ver.ProjectId
    $currentNpmTag = $ver.NpmPublishTag

    Write-Host "======================================================" -ForegroundColor Magenta
    Write-Host " TARGET BRANCH (Folder): $currentBranch" -ForegroundColor Magenta
    Write-Host " NEW BRANCH TOKEN:       $newBranchName" -ForegroundColor Magenta
    Write-Host " AZURE PROJECT:          $currentProject" -ForegroundColor Magenta
    Write-Host " NPM TAG:                $currentNpmTag" -ForegroundColor Magenta
    Write-Host "======================================================" -ForegroundColor Magenta

    # Вложенный цикл по проектам (Library, Analytics и т.д.)
    foreach ($project in $projects) {
        Write-Host "Processing: $($project.Name)" -ForegroundColor Cyan
        
        # 1. ПРОВЕРКА: Существует ли целевой репозиторий
        $repoPath = Join-Path $PSScriptRoot $project.TargetRepo
        if (!(Test-Path $repoPath)) {
            Write-Host "  [ERROR] Target repository not found at: $repoPath" -ForegroundColor Red
            continue 
        }

        # Пути к исходным шаблонам и целевой папке
        $sourcePath = Join-Path $PSScriptRoot $project.SourceDir
        $targetPath = Join-Path $repoPath "azure-pipelines/$currentBranch"

        # 2. ПРОВЕРКА: Существует ли папка с исходными шаблонами
        if (!(Test-Path $sourcePath)) {
            Write-Host "  [ERROR] Source template folder not found: $sourcePath" -ForegroundColor Red
            continue
        }

        # Создаем целевую папку, если её нет
        if (!(Test-Path $targetPath)) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
        }

        # Обрабатываем файлы
        $files = Get-ChildItem -Path $sourcePath -Filter "*.yml"
        foreach ($file in $files) {
            $content = Get-Content $file.FullName -Raw
            
            # Замена токенов текущими значениями из цикла версий
            $content = $content -replace "__BRANCH__", $currentBranch
            $content = $content -replace "__NEW_BRANCH__", $newBranchName
            $content = $content -replace "__PROJECT_ID__", $currentProject
            $content = $content -replace "__NPM_PUBLISH_TAG__", $currentNpmTag

            $finalPath = Join-Path $targetPath $file.Name
            
            # Сохранение в UTF-8 без BOM
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($finalPath, $content, $utf8NoBom)
            
            Write-Host "  [OK] Generated: $finalPath" -ForegroundColor Green
        }
        Write-Host "" # Пустая строка для читаемости между проектами
    }
}

# Показываем финальное сообщение только если скрипт запущен вручную (для всех веток)
if ($TargetBranch -eq "all") {
    Write-Host "`nMass generation process finished. Check your Git diffs." -ForegroundColor Yellow
    Write-Host "Press any key to exit..."
    $null = [Console]::ReadKey()
}