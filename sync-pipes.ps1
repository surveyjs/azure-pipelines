param ([string]$TargetBranch)

# Проверка наличия параметра
if ([string]::IsNullOrEmpty($TargetBranch)) {
    Write-Host "Error: Please specify -TargetBranch (master or V3)" -ForegroundColor Red
    return
}

# Конфигурация проектов (пути должны совпадать с генератором)
$projects = @(
    @{ Name = "Library";          Path = "../survey-library" },
    @{ Name = "Creator";          Path = "../survey-creator" },
    @{ Name = "Analytics";        Path = "../survey-analytics" },
    @{ Name = "PDF";              Path = "../survey-pdf" },
    @{ Name = "Custom Widgets";   Path = "../custom-widgets" },
    @{ Name = "Angular CLI";      Path = "../surveyjs_angular_cli" },
    @{ Name = "React Quickstart"; Path = "../surveyjs_react_quickstart" },
    @{ Name = "Vue3 Quickstart";  Path = "../surveyjs_vue3_quickstart" },
    @{ Name = "Service";          Path = "../service" },
    @{ Name = "Site Demos";       Path = "../surveyjsio-site-tests" }
)

$commitMessage = "generated azure pipes [azurepipelines skip]"

foreach ($project in $projects) {
    $repoPath = Join-Path $PSScriptRoot $project.Path
    
    if (!(Test-Path $repoPath)) {
        Write-Host "[SKIP] Repository not found: $($project.Name)" -ForegroundColor Yellow
        continue
    }

    Write-Host "`n>>> SYNCING: $($project.Name) ON BRANCH: $TargetBranch <<<" -ForegroundColor Cyan
    
    # 1. Переход в папку репозитория
    Set-Location $repoPath

    # 2. Принудительное переключение ветки и обновление из origin
    git checkout -f $TargetBranch
    git pull origin $TargetBranch

    # 3. Возврат в корень для запуска генератора (только для целевой ветки)
    Set-Location $PSScriptRoot
    .\generate-pipes.ps1 -TargetBranch $TargetBranch

    # 4. Возврат в репо для коммита и пуша
    Set-Location $repoPath
    
    # Добавляем только папку текущей ветки
    git add "azure-pipelines/$TargetBranch"
    
    # Проверка наличия изменений
    $status = git status --porcelain
    if ($null -ne $status) {
        # Коммит и пуш с байпасом хуков (--no-verify)
        git commit -m $commitMessage --no-verify
        git push origin $TargetBranch --no-verify
        Write-Host "  [SUCCESS] Pushed to $TargetBranch (hooks bypassed)" -ForegroundColor Green
    } else {
        Write-Host "  [INFO] No changes detected in $TargetBranch" -ForegroundColor White
    }
}

# Возвращаемся в исходную папку
Set-Location $PSScriptRoot
Write-Host "`nMass sync process finished!" -ForegroundColor Yellow