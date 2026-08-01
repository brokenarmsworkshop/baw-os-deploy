#requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Broken Arms Workshop
# SPDX-License-Identifier: GPL-3.0-only

<#
.SYNOPSIS
    BAW OS — Assistant de préparation et de contrôle du redéploiement.

.DESCRIPTION
    Cette version :
      - demande le dossier racine d'installation de BAW OS ;
      - crée ou contrôle l'arborescence sans écraser l'existant ;
      - contrôle Git et les deux dépôts locaux ;
      - contrôle Docker Desktop, Docker Engine et Docker Compose ;
      - contrôle l'emplacement des données Docker ;
      - détecte n8n comme service Docker à déployer ;
      - détecte Ollama comme moteur SLM local ;
      - contrôle ou crée le secret technique PostgreSQL ;
      - génère un rapport JSON et un rapport texte ;
      - copie les fichiers réutilisables dans baw-os-deploy pour un futur push.

    Le script n'installe pas encore n8n ou Ollama et ne déploie aucun conteneur
    métier. Il ne remplace aucun secret existant.
#>

[CmdletBinding()]
param(
    [string]$InstallRoot,
    [switch]$NoGui,
    [switch]$SkipDockerSmokeTest,
    [switch]$SkipPrepareDeployRepository
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ExpectedGitOwner = "brokenarmsworkshop"
$ExpectedAppRemote = "https://github.com/$ExpectedGitOwner/baw-os-app.git"
$ExpectedDeployRemote = "https://github.com/$ExpectedGitOwner/baw-os-deploy.git"

# ============================================================
# AFFICHAGE
# ============================================================

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)

    Write-Host ""
    Write-Host ("=" * 72) -ForegroundColor DarkCyan
    Write-Host "▶ $Message" -ForegroundColor Cyan
    Write-Host ("=" * 72) -ForegroundColor DarkCyan
}

function Write-Success {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  ✔ $Message" -ForegroundColor Green
}

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  • $Message" -ForegroundColor Gray
}

function Write-Notice {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  ⚠ $Message" -ForegroundColor Yellow
}

function Write-Failure {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  ✘ $Message" -ForegroundColor Red
}

# ============================================================
# COMMANDES NATIVES
# ============================================================

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure,
        [switch]$Silent
    )

    $OldPreference = $ErrorActionPreference

    try {
        # Sous Windows PowerShell 5.1, certaines commandes natives écrivent
        # sur stderr même pour des états attendus.
        $ErrorActionPreference = "Continue"
        $Output = @(& $FilePath @Arguments 2>&1)
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $OldPreference
    }

    if (-not $Silent -and $Output.Count -gt 0) {
        foreach ($Line in $Output) {
            Write-Host "    $Line"
        }
    }

    if ($ExitCode -ne 0 -and -not $AllowFailure) {
        $Rendered = "$FilePath " + ($Arguments -join " ")
        $RenderedOutput = $Output -join [Environment]::NewLine

        throw @"
La commande suivante a échoué :

$Rendered

Code de sortie : $ExitCode

$RenderedOutput
"@
    }

    return [PSCustomObject]@{
        ExitCode = $ExitCode
        Output   = $Output
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure,
        [switch]$Silent
    )

    return Invoke-Native `
        -FilePath "git" `
        -Arguments (@("-C", $RepositoryPath) + $Arguments) `
        -AllowFailure:$AllowFailure `
        -Silent:$Silent
}

# ============================================================
# FICHIERS ET DOSSIERS
# ============================================================

function New-SafeDirectory {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        Write-Info "Dossier conservé : $Path"
        return
    }

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Write-Success "Dossier créé : $Path"
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    $Parent = Split-Path -Parent $Path

    if ($Parent -and -not (Test-Path -LiteralPath $Parent)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Set-FileIfMissing {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    if (Test-Path -LiteralPath $Path) {
        Write-Info "Fichier conservé : $Path"
        return $false
    }

    Write-Utf8NoBom -Path $Path -Content $Content
    Write-Success "Fichier créé : $Path"
    return $true
}

function Set-FileIfDifferent {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    if (Test-Path -LiteralPath $Path) {
        $Existing = Get-Content -LiteralPath $Path -Raw

        if ($Existing -eq $Content) {
            Write-Info "Fichier déjà à jour : $Path"
            return $false
        }
    }

    Write-Utf8NoBom -Path $Path -Content $Content
    Write-Success "Fichier actualisé : $Path"
    return $true
}

function Copy-FileIfDifferent {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Fichier source introuvable : $Source"
    }

    $Parent = Split-Path -Parent $Destination

    if ($Parent -and -not (Test-Path -LiteralPath $Parent)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $Destination) {
        $SourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
        $DestinationHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash

        if ($SourceHash -eq $DestinationHash) {
            Write-Info "Fichier déjà à jour : $Destination"
            return $false
        }
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    Write-Success "Fichier copié : $Destination"
    return $true
}

function Get-NormalizedPath {
    param([Parameter(Mandatory)][string]$Path)

    try {
        return [System.IO.Path]::GetFullPath($Path).TrimEnd("\")
    }
    catch {
        return $Path.TrimEnd("\")
    }
}

function New-RandomSecret {
    param([int]$ByteLength = 48)

    $Bytes = New-Object byte[] $ByteLength
    $Generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $Generator.GetBytes($Bytes)
    }
    finally {
        $Generator.Dispose()
    }

    return [Convert]::ToBase64String($Bytes).
        TrimEnd("=").
        Replace("+", "A").
        Replace("/", "B")
}

# ============================================================
# CHOIX DU DOSSIER D'INSTALLATION
# ============================================================

function Get-DefaultInstallRoot {
    try {
        $DevVolume = Get-Volume |
            Where-Object {
                $_.FileSystemLabel -eq "DEV" -and
                $_.DriveLetter
            } |
            Select-Object -First 1

        if ($DevVolume) {
            return "$($DevVolume.DriveLetter):\BAW_OS"
        }
    }
    catch {
    }

    if (Test-Path -LiteralPath "G:\") {
        return "G:\BAW_OS"
    }

    return (Join-Path $env:USERPROFILE "BAW_OS")
}

function Select-InstallRootWithDialog {
    param([Parameter(Mandatory)][string]$DefaultPath)

    try {
        Add-Type -AssemblyName System.Windows.Forms

        $Dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $Dialog.Description = @"
Choisissez le dossier racine de BAW OS.

Exemple recommandé :
G:\BAW_OS
"@
        $Dialog.ShowNewFolderButton = $true

        if (Test-Path -LiteralPath $DefaultPath) {
            $Dialog.SelectedPath = $DefaultPath
        }
        else {
            $DefaultParent = Split-Path -Parent $DefaultPath

            if ($DefaultParent -and (Test-Path -LiteralPath $DefaultParent)) {
                $Dialog.SelectedPath = $DefaultParent
            }
        }

        $Result = $Dialog.ShowDialog()

        if ($Result -eq [System.Windows.Forms.DialogResult]::OK) {
            return $Dialog.SelectedPath
        }

        return $null
    }
    catch {
        Write-Notice "La fenêtre de sélection n'est pas disponible."
        return $null
    }
}

function Resolve-InstallRoot {
    param(
        [string]$RequestedPath,
        [switch]$DisableGui
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        return (Get-NormalizedPath -Path $RequestedPath)
    }

    $DefaultPath = Get-DefaultInstallRoot

    if (-not $DisableGui) {
        $SelectedPath = Select-InstallRootWithDialog -DefaultPath $DefaultPath

        if (-not [string]::IsNullOrWhiteSpace($SelectedPath)) {
            return (Get-NormalizedPath -Path $SelectedPath)
        }
    }

    Write-Host ""
    $EnteredPath = Read-Host "Dossier racine BAW OS [$DefaultPath]"

    if ([string]::IsNullOrWhiteSpace($EnteredPath)) {
        return (Get-NormalizedPath -Path $DefaultPath)
    }

    return (Get-NormalizedPath -Path $EnteredPath)
}

# ============================================================
# RAPPORTS DE DÉPENDANCES
# ============================================================

function New-DependencyResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][bool]$Ready,
        [string]$Version = "",
        [string]$Details = ""
    )

    return [PSCustomObject]@{
        Name    = $Name
        Status  = $Status
        Ready   = $Ready
        Version = $Version
        Details = $Details
    }
}

function Test-GitDependency {
    param(
        [Parameter(Mandatory)][string]$AppPath,
        [Parameter(Mandatory)][string]$DeployPath
    )

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return New-DependencyResult `
            -Name "Git" `
            -Status "Absent" `
            -Ready $false `
            -Details "Git n'est pas accessible dans le PATH."
    }

    $VersionResult = Invoke-Native `
        -FilePath "git" `
        -Arguments @("--version") `
        -AllowFailure `
        -Silent

    $Version = ($VersionResult.Output -join " ").Trim()
    $Issues = New-Object System.Collections.Generic.List[string]

    $GitName = Invoke-Native `
        -FilePath "git" `
        -Arguments @("config", "--global", "--get", "user.name") `
        -AllowFailure `
        -Silent

    $GitEmail = Invoke-Native `
        -FilePath "git" `
        -Arguments @("config", "--global", "--get", "user.email") `
        -AllowFailure `
        -Silent

    if ($GitName.ExitCode -ne 0 -or $GitEmail.ExitCode -ne 0) {
        $Issues.Add("Identité Git globale incomplète")
    }

    foreach ($Repository in @(
        [PSCustomObject]@{
            Name = "baw-os-app"
            Path = $AppPath
            ExpectedRemote = $ExpectedAppRemote
        },
        [PSCustomObject]@{
            Name = "baw-os-deploy"
            Path = $DeployPath
            ExpectedRemote = $ExpectedDeployRemote
        }
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $Repository.Path ".git"))) {
            $Issues.Add("$($Repository.Name) n'est pas initialisé localement")
            continue
        }

        $Origin = Invoke-Git `
            -RepositoryPath $Repository.Path `
            -Arguments @("remote", "get-url", "origin") `
            -AllowFailure `
            -Silent

        if ($Origin.ExitCode -ne 0) {
            $Issues.Add("$($Repository.Name) n'a pas de remote origin")
            continue
        }

        $OriginUrl = ($Origin.Output -join "").Trim()

        if ($OriginUrl -ne $Repository.ExpectedRemote) {
            $Issues.Add("$($Repository.Name) utilise un autre remote")
        }
    }

    if ($Issues.Count -eq 0) {
        return New-DependencyResult `
            -Name "Git" `
            -Status "Prêt" `
            -Ready $true `
            -Version $Version `
            -Details "Les deux dépôts locaux sont reliés à GitHub."
    }

    return New-DependencyResult `
        -Name "Git" `
        -Status "À vérifier" `
        -Ready $false `
        -Version $Version `
        -Details ($Issues -join " ; ")
}

function Get-DockerSettingsStatus {
    param([Parameter(Mandatory)][string]$DockerDataPath)

    $SettingsFile = Join-Path $env:APPDATA "Docker\settings-store.json"
    $ExpectedWslPath = Join-Path $DockerDataPath "DockerDesktopWSL"

    if (-not (Test-Path -LiteralPath $SettingsFile)) {
        return [PSCustomObject]@{
            Ready = $false
            ConfiguredPath = ""
            ExpectedPath = $ExpectedWslPath
            Details = "settings-store.json introuvable"
        }
    }

    try {
        $Settings = Get-Content -LiteralPath $SettingsFile -Raw |
            ConvertFrom-Json

        $ConfiguredPath = [string]$Settings.CustomWslDistroDir

        $Ready = (
            -not [string]::IsNullOrWhiteSpace($ConfiguredPath) -and
            (Get-NormalizedPath $ConfiguredPath) -ieq
            (Get-NormalizedPath $ExpectedWslPath)
        )

        return [PSCustomObject]@{
            Ready = $Ready
            ConfiguredPath = $ConfiguredPath
            ExpectedPath = $ExpectedWslPath
            Details = if ($Ready) {
                "Emplacement Docker correct"
            }
            else {
                "Emplacement Docker différent de la racine choisie"
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            Ready = $false
            ConfiguredPath = ""
            ExpectedPath = $ExpectedWslPath
            Details = "Impossible de lire settings-store.json"
        }
    }
}

function Test-DockerDependency {
    param(
        [Parameter(Mandatory)][string]$DockerDataPath,
        [switch]$SkipSmokeTest
    )

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        return New-DependencyResult `
            -Name "Docker" `
            -Status "Absent" `
            -Ready $false `
            -Details "Docker CLI n'est pas accessible."
    }

    $ClientVersion = Invoke-Native `
        -FilePath "docker" `
        -Arguments @("--version") `
        -AllowFailure `
        -Silent

    $VersionText = ($ClientVersion.Output -join " ").Trim()

    $Server = Invoke-Native `
        -FilePath "docker" `
        -Arguments @("version", "--format", "{{.Server.Version}}") `
        -AllowFailure `
        -Silent

    if ($Server.ExitCode -ne 0) {
        return New-DependencyResult `
            -Name "Docker" `
            -Status "Installé, arrêté" `
            -Ready $false `
            -Version $VersionText `
            -Details "Docker Desktop est installé mais le moteur ne répond pas."
    }

    $Compose = Invoke-Native `
        -FilePath "docker" `
        -Arguments @("compose", "version") `
        -AllowFailure `
        -Silent

    if ($Compose.ExitCode -ne 0) {
        return New-DependencyResult `
            -Name "Docker" `
            -Status "Compose absent" `
            -Ready $false `
            -Version $VersionText `
            -Details "Le moteur répond mais Docker Compose n'est pas disponible."
    }

    $SettingsStatus = Get-DockerSettingsStatus -DockerDataPath $DockerDataPath

    if (-not $SettingsStatus.Ready) {
        return New-DependencyResult `
            -Name "Docker" `
            -Status "Chemin à corriger" `
            -Ready $false `
            -Version $VersionText `
            -Details ("Attendu : {0} ; configuré : {1}" -f `
                $SettingsStatus.ExpectedPath,
                $SettingsStatus.ConfiguredPath)
    }

    if (-not $SkipSmokeTest) {
        $HelloWasPresent = Invoke-Native `
            -FilePath "docker" `
            -Arguments @("image", "inspect", "hello-world:latest") `
            -AllowFailure `
            -Silent

        $TestResult = Invoke-Native `
            -FilePath "docker" `
            -Arguments @("run", "--rm", "hello-world") `
            -AllowFailure `
            -Silent

        if ($TestResult.ExitCode -ne 0) {
            return New-DependencyResult `
                -Name "Docker" `
                -Status "Test échoué" `
                -Ready $false `
                -Version $VersionText `
                -Details "Le conteneur hello-world n'a pas pu être exécuté."
        }

        if ($HelloWasPresent.ExitCode -ne 0) {
            Invoke-Native `
                -FilePath "docker" `
                -Arguments @("image", "rm", "hello-world:latest") `
                -AllowFailure `
                -Silent |
                Out-Null
        }
    }

    $ServerVersion = ($Server.Output -join "").Trim()
    $ComposeVersion = ($Compose.Output -join " ").Trim()

    return New-DependencyResult `
        -Name "Docker" `
        -Status "Prêt" `
        -Ready $true `
        -Version "Engine $ServerVersion" `
        -Details "$ComposeVersion ; données sur $($SettingsStatus.ExpectedPath)"
}

function Test-N8nDependency {
    param(
        [Parameter(Mandatory)][string]$DeployPath,
        [Parameter(Mandatory)][bool]$DockerReady
    )

    $Signals = New-Object System.Collections.Generic.List[string]
    $Running = $false
    $Stopped = $false
    $ImagePresent = $false
    $ComposePrepared = $false
    $CliInstalled = $false
    $Version = ""

    $N8nCommand = Get-Command n8n -ErrorAction SilentlyContinue

    if ($N8nCommand) {
        $CliInstalled = $true

        $CliVersion = Invoke-Native `
            -FilePath "n8n" `
            -Arguments @("--version") `
            -AllowFailure `
            -Silent

        if ($CliVersion.ExitCode -eq 0) {
            $Version = ($CliVersion.Output -join " ").Trim()
            $Signals.Add("CLI local : $Version")
        }
        else {
            $Signals.Add("CLI local détecté")
        }
    }

    $ComposeFiles = @(
        Join-Path $DeployPath "compose.yaml"
        Join-Path $DeployPath "compose.yml"
        Join-Path $DeployPath "docker-compose.yaml"
        Join-Path $DeployPath "docker-compose.yml"
    )

    foreach ($ComposeFile in $ComposeFiles) {
        if (-not (Test-Path -LiteralPath $ComposeFile)) {
            continue
        }

        $Content = Get-Content -LiteralPath $ComposeFile -Raw

        if ($Content -match "(?im)^\s*n8n\s*:" -or $Content -match "n8nio/n8n") {
            $ComposePrepared = $true
            $Signals.Add("Compose préparé : $ComposeFile")
            break
        }
    }

    if ($DockerReady) {
        $Containers = Invoke-Native `
            -FilePath "docker" `
            -Arguments @(
                "ps",
                "-a",
                "--format",
                "{{.Names}}|{{.Image}}|{{.Status}}"
            ) `
            -AllowFailure `
            -Silent

        if ($Containers.ExitCode -eq 0) {
            foreach ($LineObject in $Containers.Output) {
                $Line = [string]$LineObject

                if ($Line -notmatch "(?i)n8n") {
                    continue
                }

                if ($Line -match "\|Up ") {
                    $Running = $true
                    $Signals.Add("Conteneur actif : $Line")
                }
                else {
                    $Stopped = $true
                    $Signals.Add("Conteneur arrêté : $Line")
                }
            }
        }

        $Images = Invoke-Native `
            -FilePath "docker" `
            -Arguments @(
                "image",
                "ls",
                "--format",
                "{{.Repository}}:{{.Tag}}"
            ) `
            -AllowFailure `
            -Silent

        if ($Images.ExitCode -eq 0) {
            foreach ($ImageObject in $Images.Output) {
                $Image = [string]$ImageObject

                if ($Image -match "(?i)^n8nio/n8n:") {
                    $ImagePresent = $true
                    $Signals.Add("Image présente : $Image")
                }
            }
        }
    }

    if ($Running) {
        return New-DependencyResult `
            -Name "n8n" `
            -Status "Déployé et actif" `
            -Ready $true `
            -Version $Version `
            -Details ($Signals -join " ; ")
    }

    if ($Stopped) {
        return New-DependencyResult `
            -Name "n8n" `
            -Status "Déployé, arrêté" `
            -Ready $false `
            -Version $Version `
            -Details ($Signals -join " ; ")
    }

    if ($ComposePrepared) {
        return New-DependencyResult `
            -Name "n8n" `
            -Status "Prêt à déployer" `
            -Ready $false `
            -Version $Version `
            -Details ($Signals -join " ; ")
    }

    if ($ImagePresent -or $CliInstalled) {
        return New-DependencyResult `
            -Name "n8n" `
            -Status "Partiellement présent" `
            -Ready $false `
            -Version $Version `
            -Details ($Signals -join " ; ")
    }

    return New-DependencyResult `
        -Name "n8n" `
        -Status "Non déployé" `
        -Ready $false `
        -Details "État attendu à ce stade : n8n sera installé comme service Docker."
}

function Test-OllamaDependency {
    $OllamaCommand = Get-Command ollama -ErrorAction SilentlyContinue

    if (-not $OllamaCommand) {
        return New-DependencyResult `
            -Name "Ollama / SLM" `
            -Status "Absent" `
            -Ready $false `
            -Details "La commande ollama n'est pas accessible dans le PATH."
    }

    $VersionResult = Invoke-Native `
        -FilePath "ollama" `
        -Arguments @("--version") `
        -AllowFailure `
        -Silent

    $Version = ($VersionResult.Output -join " ").Trim()
    $ApiReady = $false
    $ApiVersion = ""
    $Models = @()

    try {
        $ApiResponse = Invoke-RestMethod `
            -Uri "http://127.0.0.1:11434/api/version" `
            -Method Get `
            -TimeoutSec 3

        if ($ApiResponse.version) {
            $ApiReady = $true
            $ApiVersion = [string]$ApiResponse.version
        }
    }
    catch {
        $ApiReady = $false
    }

    if ($ApiReady) {
        $ModelList = Invoke-Native `
            -FilePath "ollama" `
            -Arguments @("list") `
            -AllowFailure `
            -Silent

        if ($ModelList.ExitCode -eq 0 -and $ModelList.Output.Count -gt 1) {
            $Models = @(
                $ModelList.Output |
                    Select-Object -Skip 1 |
                    ForEach-Object {
                        $Text = ([string]$_).Trim()

                        if (-not [string]::IsNullOrWhiteSpace($Text)) {
                            ($Text -split "\s+")[0]
                        }
                    } |
                    Where-Object {
                        -not [string]::IsNullOrWhiteSpace($_)
                    }
            )
        }

        $ModelText = if ($Models.Count -gt 0) {
            "Modèles : " + ($Models -join ", ")
        }
        else {
            "Aucun modèle téléchargé"
        }

        return New-DependencyResult `
            -Name "Ollama / SLM" `
            -Status "Prêt" `
            -Ready $true `
            -Version $ApiVersion `
            -Details "API locale active sur 127.0.0.1:11434 ; $ModelText"
    }

    return New-DependencyResult `
        -Name "Ollama / SLM" `
        -Status "Installé, arrêté" `
        -Ready $false `
        -Version $Version `
        -Details "La commande existe, mais l'API locale ne répond pas."
}

# ============================================================
# ARBORESCENCE ET SECRET POSTGRESQL
# ============================================================

function Ensure-BawStructure {
    param([Parameter(Mandatory)][string]$Root)

    $Paths = [ordered]@{
        Root             = $Root
        Repositories     = Join-Path $Root "repositories"
        AppRepository    = Join-Path $Root "repositories\baw-os-app"
        DeployRepository = Join-Path $Root "repositories\baw-os-deploy"
        Runtime          = Join-Path $Root "runtime"
        DockerData       = Join-Path $Root "docker-data"
        Secrets          = Join-Path $Root "secrets"
        Backups          = Join-Path $Root "backups"
        Recovery         = Join-Path $Root "recovery"
        RecoveryLog      = Join-Path $Root "recovery-log"
    }

    $Directories = @(
        $Paths.Root
        $Paths.Repositories
        $Paths.AppRepository
        $Paths.DeployRepository
        $Paths.Runtime
        (Join-Path $Paths.Runtime "postgres")
        (Join-Path $Paths.Runtime "n8n")
        (Join-Path $Paths.Runtime "hum-bridge")
        (Join-Path $Paths.Runtime "services")
        $Paths.DockerData
        $Paths.Secrets
        (Join-Path $Paths.Secrets "postgres")
        (Join-Path $Paths.Secrets "n8n")
        (Join-Path $Paths.Secrets "hum-bridge")
        (Join-Path $Paths.Secrets "ollama")
        $Paths.Backups
        (Join-Path $Paths.Backups "postgres")
        (Join-Path $Paths.Backups "n8n")
        (Join-Path $Paths.Backups "configuration")
        (Join-Path $Paths.Backups "repositories")
        $Paths.Recovery
        $Paths.RecoveryLog
    )

    foreach ($Directory in $Directories) {
        New-SafeDirectory -Path $Directory
    }

    return [PSCustomObject]$Paths
}

function Ensure-PostgresSecret {
    param([Parameter(Mandatory)][string]$SecretsRoot)

    $SecretDirectory = Join-Path $SecretsRoot "postgres"
    $SecretFile = Join-Path `
        $SecretDirectory `
        "postgres_admin_password.txt"
    $NonSecretFile = Join-Path `
        $SecretDirectory `
        "postgres.nonsecret.env"

    New-SafeDirectory -Path $SecretDirectory

    if (Test-Path -LiteralPath $SecretFile) {
        $ExistingPassword = (
            [System.IO.File]::ReadAllText($SecretFile)
        ).Trim()

        if ($ExistingPassword.Length -ne 64) {
            throw @"
Le secret PostgreSQL existant n'est pas conforme.

Fichier :
$SecretFile

Longueur attendue : 64 caractères.
Le script refuse de modifier automatiquement un secret existant.
"@
        }

        $ExistingPassword = $null
        Write-Success "Secret PostgreSQL existant conservé"
    }
    else {
        $Password = New-RandomSecret -ByteLength 48

        if ($Password.Length -ne 64) {
            throw "La génération du secret PostgreSQL a échoué."
        }

        Write-Utf8NoBom -Path $SecretFile -Content $Password
        $Password = $null

        Write-Success "Secret PostgreSQL créé sans afficher sa valeur"
    }

    $NonSecretContent = @"
POSTGRES_DB=baw_core
POSTGRES_USER=baw_admin
TZ=Europe/Paris
"@

    Write-Utf8NoBom `
        -Path $NonSecretFile `
        -Content $NonSecretContent

    Write-Success "Configuration PostgreSQL non sensible préparée"

    return $SecretFile
}

# ============================================================
# PRÉPARATION DES FICHIERS POUR LE FUTUR PUSH
# ============================================================

function Prepare-DeployRepositoryFiles {
    param(
        [Parameter(Mandatory)][string]$DeployPath,
        [Parameter(Mandatory)][string]$CurrentScriptPath
    )

    $ScriptsPath = Join-Path $DeployPath "scripts"
    $DocsPath = Join-Path $DeployPath "docs"
    $ConfigPath = Join-Path $DeployPath "config"

    foreach ($Directory in @($ScriptsPath, $DocsPath, $ConfigPath)) {
        New-SafeDirectory -Path $Directory
    }

    $DestinationScript = Join-Path $ScriptsPath "Install-BAW-OS.ps1"

    if (
        -not [string]::IsNullOrWhiteSpace($CurrentScriptPath) -and
        (Test-Path -LiteralPath $CurrentScriptPath)
    ) {
        Copy-FileIfDifferent `
            -Source $CurrentScriptPath `
            -Destination $DestinationScript |
            Out-Null
    }
    else {
        Write-Notice "Le script courant ne peut pas être copié automatiquement."
    }

    $LauncherContent = @'
@echo off
title BAW OS - Assistant de redeploiement
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-BAW-OS.ps1"
set EXITCODE=%ERRORLEVEL%
echo.
if not "%EXITCODE%"=="0" (
    echo Le script s'est termine avec le code %EXITCODE%.
) else (
    echo Le script s'est termine correctement.
)
echo.
pause
exit /b %EXITCODE%
'@

    Set-FileIfDifferent `
        -Path (Join-Path $ScriptsPath "Lancer-Installation-BAW-OS.cmd") `
        -Content $LauncherContent |
        Out-Null

    $DependenciesDocument = @'
# Dépendances du redéploiement BAW OS

## Git

Git est utilisé pour restaurer et versionner :

- `baw-os-app` ;
- `baw-os-deploy`.

Les données actives, sauvegardes et secrets restent hors Git.

## Docker Desktop

Docker Desktop fournit le moteur Linux et Docker Compose.

Les données Docker doivent être placées dans le dossier `docker-data` de la
racine BAW OS sélectionnée.

## n8n

n8n est prévu comme service Docker. Une installation globale avec npm n'est
donc pas requise pour BAW OS.

Le simple état « Non déployé » est normal avant la création du fichier Compose
complet.

## Ollama

Ollama est le moteur SLM local prévu à ce stade.

Le contrôle porte sur :

- la commande `ollama` ;
- l'API locale sur le port 11434 ;
- les modèles déjà téléchargés.

Le choix du ou des modèles BAW OS sera documenté séparément.
'@

    Set-FileIfDifferent `
        -Path (Join-Path $DocsPath "DEPENDANCES.md") `
        -Content $DependenciesDocument |
        Out-Null

    $InstallerDocument = @'
# Assistant de redéploiement BAW OS

Lancer sous Windows :

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\Install-BAW-OS.ps1
```

Le script :

1. demande le dossier d'installation ;
2. crée l'arborescence manquante ;
3. contrôle Git et les dépôts ;
4. contrôle Docker Desktop et Compose ;
5. détecte l'état de n8n ;
6. détecte Ollama et les modèles locaux ;
7. conserve ou crée le secret PostgreSQL ;
8. génère les rapports dans `recovery-log`.

Il n'installe pas encore automatiquement les dépendances absentes.
'@

    Set-FileIfDifferent `
        -Path (Join-Path $DocsPath "ASSISTANT-REDEPLOIEMENT.md") `
        -Content $InstallerDocument |
        Out-Null

    $DependencyManifest = @'
{
  "schemaVersion": 1,
  "dependencies": [
    {
      "id": "git",
      "required": true,
      "mode": "windows-host"
    },
    {
      "id": "docker-desktop",
      "required": true,
      "mode": "windows-host"
    },
    {
      "id": "docker-compose",
      "required": true,
      "mode": "docker-plugin"
    },
    {
      "id": "n8n",
      "required": true,
      "mode": "docker-service"
    },
    {
      "id": "ollama",
      "required": true,
      "mode": "windows-host",
      "role": "local-slm-engine"
    }
  ]
}
'@

    Set-FileIfDifferent `
        -Path (Join-Path $ConfigPath "dependencies.json") `
        -Content $DependencyManifest |
        Out-Null

    Write-Success "Fichiers de déploiement préparés pour un futur commit"
}

# ============================================================
# EXÉCUTION PRINCIPALE
# ============================================================

$TranscriptStarted = $false
$ResolvedRoot = $null
$Paths = $null

try {
    Write-Step "Choix du dossier d'installation"

    $ResolvedRoot = Resolve-InstallRoot `
        -RequestedPath $InstallRoot `
        -DisableGui:$NoGui

    if ([string]::IsNullOrWhiteSpace($ResolvedRoot)) {
        throw "Aucun dossier d'installation n'a été choisi."
    }

    Write-Success "Racine sélectionnée : $ResolvedRoot"

    Write-Step "Création et contrôle de l'arborescence"

    $Paths = Ensure-BawStructure -Root $ResolvedRoot

    $LogStamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $TranscriptFile = Join-Path `
        $Paths.RecoveryLog `
        "BAW-REDEPLOY-CHECK-$LogStamp.log"

    try {
        Start-Transcript -LiteralPath $TranscriptFile -Force | Out-Null
        $TranscriptStarted = $true
    }
    catch {
        Write-Notice "Le journal PowerShell détaillé n'a pas pu être démarré."
    }

    Write-Step "Contrôle et préparation du secret PostgreSQL"

    $PostgresSecretFile = Ensure-PostgresSecret `
        -SecretsRoot $Paths.Secrets

    Write-Info $PostgresSecretFile

    Write-Step "Contrôle des dépendances"

    $GitResult = Test-GitDependency `
        -AppPath $Paths.AppRepository `
        -DeployPath $Paths.DeployRepository

    $DockerResult = Test-DockerDependency `
        -DockerDataPath $Paths.DockerData `
        -SkipSmokeTest:$SkipDockerSmokeTest

    $N8nResult = Test-N8nDependency `
        -DeployPath $Paths.DeployRepository `
        -DockerReady $DockerResult.Ready

    $OllamaResult = Test-OllamaDependency

    $DependencyResults = @(
        $GitResult
        $DockerResult
        $N8nResult
        $OllamaResult
    )

    Write-Host ""
    $DependencyResults |
        Select-Object Name, Status, Ready, Version |
        Format-Table -AutoSize

    foreach ($Dependency in $DependencyResults) {
        Write-Host ""
        Write-Host "$($Dependency.Name) — $($Dependency.Status)" `
            -ForegroundColor Cyan
        Write-Host "  $($Dependency.Details)"
    }

    Write-Step "Création des rapports"

    $State = [ordered]@{
        schemaVersion = 2
        generatedAt = (Get-Date).ToString("o")
        installRoot = $ResolvedRoot
        paths = [ordered]@{
            appRepository = $Paths.AppRepository
            deployRepository = $Paths.DeployRepository
            dockerData = $Paths.DockerData
            secrets = $Paths.Secrets
            backups = $Paths.Backups
            recoveryLog = $Paths.RecoveryLog
        }
        postgresSecret = [ordered]@{
            present = (Test-Path -LiteralPath $PostgresSecretFile)
            path = $PostgresSecretFile
        }
        dependencies = @(
            $DependencyResults |
                ForEach-Object {
                    [ordered]@{
                        name = $_.Name
                        status = $_.Status
                        ready = $_.Ready
                        version = $_.Version
                        details = $_.Details
                    }
                }
        )
        nextStep = "Compléter le BAW Secrets Bootstrap, puis préparer PostgreSQL et n8n dans Docker Compose."
    }

    $JsonReport = Join-Path $Paths.RecoveryLog "REDEPLOY-STATE.json"

    $State |
        ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $JsonReport -Encoding UTF8

    $TextReport = Join-Path `
        $Paths.RecoveryLog `
        "STEP-03-DEPENDENCIES.txt"

    $TextLines = New-Object System.Collections.Generic.List[string]
    $TextLines.Add("BAW OS — Contrôle des dépendances")
    $TextLines.Add("Date : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $TextLines.Add("Racine : $ResolvedRoot")
    $TextLines.Add("")

    foreach ($Dependency in $DependencyResults) {
        $TextLines.Add("[$($Dependency.Name)]")
        $TextLines.Add("Statut  : $($Dependency.Status)")
        $TextLines.Add("Prêt    : $($Dependency.Ready)")
        $TextLines.Add("Version : $($Dependency.Version)")
        $TextLines.Add("Détails : $($Dependency.Details)")
        $TextLines.Add("")
    }

    $TextLines |
        Set-Content -LiteralPath $TextReport -Encoding UTF8

    Write-Success "Rapport JSON : $JsonReport"
    Write-Success "Rapport texte : $TextReport"

    if (-not $SkipPrepareDeployRepository) {
        Write-Step "Préparation des fichiers pour baw-os-deploy"

        Prepare-DeployRepositoryFiles `
            -DeployPath $Paths.DeployRepository `
            -CurrentScriptPath $PSCommandPath

        if (Get-Command git -ErrorAction SilentlyContinue) {
            if (Test-Path -LiteralPath (Join-Path $Paths.DeployRepository ".git")) {
                Write-Host ""
                Write-Host "Modifications Git prêtes pour examen :" `
                    -ForegroundColor Cyan

                Invoke-Git `
                    -RepositoryPath $Paths.DeployRepository `
                    -Arguments @("status", "--short") |
                    Out-Null
            }
        }
    }

    Write-Step "Résumé"

    foreach ($Dependency in $DependencyResults) {
        if ($Dependency.Ready) {
            Write-Success "$($Dependency.Name) : $($Dependency.Status)"
        }
        elseif ($Dependency.Name -eq "n8n" -and $Dependency.Status -eq "Non déployé") {
            Write-Notice "n8n : non déployé — état normal avant l'étape Compose"
        }
        else {
            Write-Notice "$($Dependency.Name) : $($Dependency.Status)"
        }
    }

    Write-Host ""
    Write-Host "Aucune dépendance absente n'a été installée automatiquement." `
        -ForegroundColor Yellow

    Write-Host "Aucun conteneur métier n'a été déployé." `
        -ForegroundColor Yellow

    Write-Host ""
    Write-Host "Prochaine étape :" -ForegroundColor Cyan
    Write-Host "  traiter une dépendance à la fois, puis construire le coffre de secrets." `
        -ForegroundColor White
}
catch {
    Write-Host ""
    Write-Host "✘ ÉCHEC DU SCRIPT" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
finally {
    if ($TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
        }
    }
}
