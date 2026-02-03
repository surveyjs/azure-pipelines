# --- НАСТРОЙКИ ПАРАМЕТРОВ ---
$BranchName = "V3"
$ProjectId  = "12345-abcde-67890"
# ---------------------------

# Конфигурация проектов
$projects = @(
    @{
        Name       = "Library"
        SourceDir  = "libraries/library"
        TargetRepo = "../survey-library"
    },
    @{
        Name       = "Analytics"
        SourceDir  = "libraries/analytics"
        TargetRepo = "../survey-analytics"
    }
)

Write-Host ">>> Starting generation for Branch: $BranchName and ProjectId: $ProjectId <<<`n" -ForegroundColor Yellow

foreach ($project in $projects) {
    Write-Host "Processing: $($project.Name)" -ForegroundColor Cyan
    
    # 1. ПРОВЕРКА: Существует ли целевой репозиторий (папка проекта)
    # Resolve-Path преобразует относительный путь (../) в полный для наглядности ошибки
    $repoPath = Join-Path $PSScriptRoot $project.TargetRepo
    if (!(Test-Path $repoPath)) {
        Write-Host "  [ERROR] Target repository not found at: $repoPath" -ForegroundColor Red
        Write-Host "          Please ensure the repository is cloned correctly." -ForegroundColor Red
        continue # Переход к следующему проекту в массиве
    }

    # Пути к исходным шаблонам и целевой папке для YAML
    $sourcePath = Join-Path $PSScriptRoot $project.SourceDir
    $targetPath = Join-Path $repoPath "azure-pipelines/$BranchName"

    # 2. ПРОВЕРКА: Существует ли папка с исходными шаблонами
    if (!(Test-Path $sourcePath)) {
        Write-Host "  [ERROR] Source template folder not found: $sourcePath" -ForegroundColor Red
        continue
    }

    # Создаем целевую папку внутри репозитория, если её нет
    if (!(Test-Path $targetPath)) {
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
    }

    # Обрабатываем файлы
    $files = Get-ChildItem -Path $sourcePath -Filter "*.yml"
    foreach ($file in $files) {
        $content = Get-Content $file.FullName -Raw
        
        # Замена токенов
        $content = $content -replace "__BRANCH__", $BranchName
        $content = $content -replace "__PROJECT_ID__", $ProjectId

        $finalPath = Join-Path $targetPath $file.Name
        
        # Сохранение в UTF-8 без BOM
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($finalPath, $content, $utf8NoBom)
        
        Write-Host "  [OK] Generated: $finalPath" -ForegroundColor Green
    }
}

Write-Host "`nGeneration process finished. Press any key to exit..." -ForegroundColor Yellow
$null = [Console]::ReadKey()