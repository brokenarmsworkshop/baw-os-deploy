#requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Broken Arms Workshop
# SPDX-License-Identifier: GPL-3.0-only

<#
.SYNOPSIS
    BAW OS — Assistant central de création, conservation et restauration
    des secrets du projet.

.DESCRIPTION
    Ce script Windows PowerShell :
      - demande ou détecte la racine BAW OS ;
      - affiche une fenêtre unique pour les secrets du projet ;
      - conserve les secrets existants lorsque les champs restent vides ;
      - génère les secrets techniques manquants ;
      - conserve aussi les identifiants techniques nécessaires à la reconstruction ;
      - écrit un fichier séparé par secret pour Docker Compose ;
      - protège le dossier avec des ACL NTFS restrictives ;
      - crée une sauvegarde locale chiffrée par DPAPI ;
      - permet un export portable AES-256 + HMAC protégé par mot de passe ;
      - permet de restaurer cet export sur un nouveau déploiement ;
      - crée dans baw-os-deploy les fichiers documentaires et le manifeste
        destinés à un futur commit Git.

    Aucun secret n'est écrit dans Git, dans le journal PowerShell ou dans
    le manifeste versionnable.
#>

[CmdletBinding()]
param(
    [string]$InstallRoot,
    [switch]$NoGuiRootSelection
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Supprime automatiquement la marque Windows « téléchargé depuis Internet »
# sur les fichiers du paquet. Cela évite d'avoir à débloquer chaque fichier
# manuellement après extraction.
try {
    if (
        -not [string]::IsNullOrWhiteSpace($PSScriptRoot) -and
        (Test-Path -LiteralPath $PSScriptRoot)
    ) {
        Get-ChildItem `
            -LiteralPath $PSScriptRoot `
            -Recurse `
            -File `
            -ErrorAction SilentlyContinue |
            Unblock-File -ErrorAction SilentlyContinue
    }
}
catch {
    # Le déblocage est une amélioration de confort et ne doit jamais
    # empêcher le coffre de démarrer.
}

# ============================================================
# CONFIGURATION DU COFFRE
# ============================================================

$VaultSchemaVersion = 1
$BootstrapVersion = "1.9"
$DefaultOwner = "Broken Arms Workshop"

$SecretDefinitions = @(
    [ordered]@{
        id          = "POSTGRES_ADMIN_PASSWORD"
        label       = "PostgreSQL — mot de passe administrateur"
        category    = "Socle technique"
        kind        = "generated"
        required    = $true
        relativePath = "postgres\postgres_admin_password.txt"
        description = "Mot de passe administrateur du serveur PostgreSQL."
        legacyFilePath = ""
        legacyEnv   = ""
        legacyKey   = ""
    },
    [ordered]@{
        id          = "BAW_AUTOMATION_DB_PASSWORD"
        label       = "PostgreSQL — mot de passe du compte d'automatisation"
        category    = "Socle technique"
        kind        = "generated"
        required    = $true
        relativePath = "postgres\baw_automation_password.txt"
        description = "Mot de passe du rôle PostgreSQL baw_automation utilisé par les workflows n8n."
        legacyFilePath = ""
        legacyEnv   = ""
        legacyKey   = ""
    },
    [ordered]@{
        id          = "N8N_DB_PASSWORD"
        label       = "n8n — mot de passe de base de données"
        category    = "Socle technique"
        kind        = "generated"
        required    = $true
        relativePath = "n8n\db_password.txt"
        description = "Mot de passe du compte PostgreSQL dédié à n8n."
        legacyFilePath = ""
        legacyEnv   = ""
        legacyKey   = ""
    },
    [ordered]@{
        id          = "N8N_ENCRYPTION_KEY"
        label       = "n8n — clé de chiffrement principale"
        category    = "Socle technique"
        kind        = "generated"
        required    = $true
        relativePath = "n8n\encryption_key.txt"
        description = "Clé stable utilisée pour chiffrer les credentials n8n."
        legacyFilePath = ""
        legacyEnv   = "n8n\n8n.env"
        legacyKey   = "N8N_ENCRYPTION_KEY"
    },
    [ordered]@{
        id          = "HUM_BRIDGE_SECRET"
        label       = "HUM Bridge — secret de service"
        category    = "Socle technique"
        kind        = "generated"
        required    = $true
        relativePath = "hum-bridge\service_secret.txt"
        description = "Secret partagé pour authentifier HUM Bridge."
        legacyFilePath = ""
        legacyEnv   = ""
        legacyKey   = ""
    },
    [ordered]@{
        id          = "BAW_INTERNAL_API_KEY"
        label       = "BAW OS — clé API interne"
        category    = "Socle technique"
        kind        = "generated"
        required    = $true
        relativePath = "baw\internal_api_key.txt"
        description = "Clé pour les appels internes entre services BAW OS."
        legacyFilePath = ""
        legacyEnv   = ""
        legacyKey   = ""
    },
    [ordered]@{
        id          = "WSL_BAWOPS_USERNAME"
        label       = "WSL — identifiant opérateur BAW"
        category    = "Environnement WSL"
        kind        = "entered"
        required    = $true
        sensitive   = $false
        defaultValue = "bawops"
        relativePath = "wsl\bawops_username.txt"
        description = "Identifiant Linux du compte opérateur BAW dans la distribution WSL."
        legacyFilePath = ""
        legacyEnv   = ""
        legacyKey   = ""
    },
    [ordered]@{
        id          = "WSL_BAWOPS_PASSWORD"
        label       = "WSL — mot de passe du compte bawops"
        category    = "Environnement WSL"
        kind        = "generated"
        required    = $true
        sensitive   = $true
        defaultValue = ""
        relativePath = "wsl\bawops_password.txt"
        description = "Mot de passe technique du compte Linux bawops utilisé dans WSL."
        legacyFilePath = ""
        legacyEnv   = ""
        legacyKey   = ""
    },
    [ordered]@{
        id          = "MISTRAL_API_KEY"
        label       = "Mistral — clé API"
        category    = "Services externes"
        kind        = "entered"
        required    = $false
        relativePath = "mistral\api_key.txt"
        description = "Clé API canonique unique utilisée par BAW OS et n8n."
        legacyFilePath = "providers\mistral_api_key.txt"
        legacyEnv   = ""
        legacyKey   = ""
    },
    [ordered]@{
        id          = "NOTION_TOKEN"
        label       = "Notion — jeton d'intégration"
        category    = "Services externes"
        kind        = "entered"
        required    = $false
        relativePath = "notion\api_token.txt"
        description = "Jeton canonique unique de l'intégration Notion BAW OS."
        legacyFilePath = "providers\notion_token.txt"
        legacyEnv   = ""
        legacyKey   = ""
    },
    [ordered]@{
        id          = "OPENAI_API_KEY"
        label       = "OpenAI — clé API"
        category    = "Services externes"
        kind        = "entered"
        required    = $false
        relativePath = "openai\api_key.txt"
        description = "Clé API canonique unique pour les services OpenAI."
        legacyFilePath = "providers\openai_api_key.txt"
        legacyEnv   = ""
        legacyKey   = ""
    },
    [ordered]@{
        id          = "GITHUB_TOKEN"
        label       = "GitHub — jeton applicatif"
        category    = "Services externes"
        kind        = "entered"
        required    = $false
        relativePath = "github\token.txt"
        description = "Jeton canonique unique pour les automatisations GitHub."
        legacyFilePath = "providers\github_token.txt"
        legacyEnv   = ""
        legacyKey   = ""
    },
    [ordered]@{
        id          = "SMTP_PASSWORD"
        label       = "Messagerie SMTP — mot de passe"
        category    = "Services externes"
        kind        = "entered"
        required    = $false
        relativePath = "smtp\password.txt"
        description = "Mot de passe canonique unique pour la messagerie SMTP."
        legacyFilePath = "providers\smtp_password.txt"
        legacyEnv   = ""
        legacyKey   = ""
    }
)

function Test-DefinitionSensitive {
    param([Parameter(Mandatory)][hashtable]$Definition)

    if ($Definition.ContainsKey("sensitive")) {
        return [bool]$Definition.sensitive
    }

    # Compatibilité : les définitions historiques sont sensibles par défaut.
    return $true
}

function Get-DefinitionDefaultValue {
    param([Parameter(Mandatory)][hashtable]$Definition)

    if ($Definition.ContainsKey("defaultValue")) {
        return [string]$Definition.defaultValue
    }

    return ""
}

# ============================================================
# AFFICHAGE CONSOLE
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

# ============================================================
# OUTILS DE FICHIERS
# ============================================================

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

function Write-SecretFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Refus d'écrire un secret vide : $Path"
    }

    Write-Utf8NoBom -Path $Path -Content $Value
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

function Select-Folder {
    param(
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$DefaultPath
    )

    Add-Type -AssemblyName System.Windows.Forms

    $Dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $Dialog.Description = $Description
    $Dialog.ShowNewFolderButton = $true

    if (Test-Path -LiteralPath $DefaultPath) {
        $Dialog.SelectedPath = $DefaultPath
    }
    else {
        $Parent = Split-Path -Parent $DefaultPath

        if ($Parent -and (Test-Path -LiteralPath $Parent)) {
            $Dialog.SelectedPath = $Parent
        }
    }

    if ($Dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $Dialog.SelectedPath
    }

    return $null
}

function Resolve-InstallRoot {
    param(
        [string]$RequestedRoot,
        [switch]$DisableGui
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
        return (Get-NormalizedPath -Path $RequestedRoot)
    }

    $DefaultRoot = Get-DefaultInstallRoot

    if (-not $DisableGui) {
        $Selected = Select-Folder `
            -Description "Choisissez la racine de BAW OS, par exemple G:\BAW_OS" `
            -DefaultPath $DefaultRoot

        if (-not [string]::IsNullOrWhiteSpace($Selected)) {
            return (Get-NormalizedPath -Path $Selected)
        }
    }

    $Entered = Read-Host "Racine BAW OS [$DefaultRoot]"

    if ([string]::IsNullOrWhiteSpace($Entered)) {
        return (Get-NormalizedPath -Path $DefaultRoot)
    }

    return (Get-NormalizedPath -Path $Entered)
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-ValueFingerprint {
    param([Parameter(Mandatory)][string]$Value)

    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $Sha = [System.Security.Cryptography.SHA256]::Create()

    try {
        $Hash = $Sha.ComputeHash($Bytes)
    }
    finally {
        $Sha.Dispose()
        [Array]::Clear($Bytes, 0, $Bytes.Length)
    }

    return ([BitConverter]::ToString($Hash).Replace("-", "").Substring(0, 12))
}

# ============================================================
# GÉNÉRATION ET CHARGEMENT DES SECRETS
# ============================================================

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

function Get-EnvValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key
    )

    if (
        [string]::IsNullOrWhiteSpace($Path) -or
        [string]::IsNullOrWhiteSpace($Key) -or
        -not (Test-Path -LiteralPath $Path)
    ) {
        return $null
    }

    foreach ($LineObject in Get-Content -LiteralPath $Path) {
        $Line = [string]$LineObject

        if ($Line -match "^\s*#") {
            continue
        }

        if ($Line -match ("^\s*" + [Regex]::Escape($Key) + "\s*=(.*)$")) {
            return $Matches[1].Trim()
        }
    }

    return $null
}

function Get-ExistingSecretValue {
    param(
        [Parameter(Mandatory)][hashtable]$Definition,
        [Parameter(Mandatory)][string]$SecretsRoot
    )

    $SecretPath = Join-Path $SecretsRoot $Definition.relativePath

    if (Test-Path -LiteralPath $SecretPath) {
        $Value = Get-Content -LiteralPath $SecretPath -Raw

        if (-not [string]::IsNullOrWhiteSpace($Value)) {
            return $Value.Trim()
        }
    }

    if (
        -not [string]::IsNullOrWhiteSpace(
            [string]$Definition.legacyFilePath
        )
    ) {
        $LegacyFilePath = Join-Path `
            $SecretsRoot `
            $Definition.legacyFilePath

        if (Test-Path -LiteralPath $LegacyFilePath) {
            $LegacyFileValue = (
                Get-Content `
                    -LiteralPath $LegacyFilePath `
                    -Raw
            )

            if (
                -not [string]::IsNullOrWhiteSpace(
                    $LegacyFileValue
                )
            ) {
                return $LegacyFileValue.Trim()
            }
        }
    }

    if (
        -not [string]::IsNullOrWhiteSpace($Definition.legacyEnv) -and
        -not [string]::IsNullOrWhiteSpace($Definition.legacyKey)
    ) {
        $LegacyPath = Join-Path $SecretsRoot $Definition.legacyEnv

        $LegacyValue = Get-EnvValue `
            -Path $LegacyPath `
            -Key $Definition.legacyKey

        if (-not [string]::IsNullOrWhiteSpace($LegacyValue)) {
            return $LegacyValue
        }
    }

    return $null
}

function Get-AllExistingSecrets {
    param([Parameter(Mandatory)][string]$SecretsRoot)

    $Values = @{}

    foreach ($DefinitionObject in $SecretDefinitions) {
        $Definition = [hashtable]$DefinitionObject
        $Value = Get-ExistingSecretValue `
            -Definition $Definition `
            -SecretsRoot $SecretsRoot

        if (-not [string]::IsNullOrWhiteSpace($Value)) {
            $Values[$Definition.id] = $Value
        }
    }

    return $Values
}

# ============================================================
# ACL DU DOSSIER DE SECRETS
# ============================================================

function Protect-SecretsDirectoryAcl {
    param([Parameter(Mandatory)][string]$SecretsRoot)

    if (-not (Test-Path -LiteralPath $SecretsRoot)) {
        New-Item -ItemType Directory -Path $SecretsRoot -Force | Out-Null
    }

    try {
        $CurrentIdentity = (
            [System.Security.Principal.WindowsIdentity]::GetCurrent()
        )

        $CurrentSid = $CurrentIdentity.User.Value
        $UserGrant = "*${CurrentSid}:(OI)(CI)F"

        # Mode sûr V1.6 :
        # - ne retire plus jamais l'héritage NTFS ;
        # - ne remplace plus les ACL existantes du dossier ;
        # - ajoute seulement le contrôle total au compte courant ;
        # - évite ainsi tout verrouillage du coffre.
        $AclOutput = @(
            & icacls.exe `
                $SecretsRoot `
                /inheritance:e `
                /grant `
                $UserGrant `
                /T `
                /C `
                /Q `
                2>&1
        )

        $AclExitCode = $LASTEXITCODE

        if ($AclExitCode -ne 0) {
            Write-Notice (
                "Les permissions Windows n'ont pas pu être ajustées " +
                "(code $AclExitCode)."
            )

            return $false
        }

        # Test réel d'accès après l'ajustement.
        $ProbeFile = Get-ChildItem `
            -LiteralPath $SecretsRoot `
            -File `
            -Recurse `
            -ErrorAction Stop |
            Select-Object -First 1

        if ($ProbeFile) {
            $Stream = [System.IO.File]::Open(
                $ProbeFile.FullName,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite
            )

            $Stream.Dispose()
        }
        else {
            Get-ChildItem `
                -LiteralPath $SecretsRoot `
                -Force `
                -ErrorAction Stop |
                Select-Object -First 1 |
                Out-Null
        }

        Write-Success (
            "Accès au coffre vérifié pour " +
            $CurrentIdentity.Name +
            " ; héritage NTFS conservé"
        )

        return $true
    }
    catch {
        # L'échec du réglage ACL ne doit jamais invalider ou supprimer
        # les secrets déjà enregistrés.
        Write-Notice "Vérification des permissions non concluante."
        Write-Notice $_.Exception.Message
        return $false
    }
}


# ============================================================
# SAUVEGARDE LOCALE DPAPI
# ============================================================

function Protect-ValueWithDpapi {
    param([Parameter(Mandatory)][string]$Value)

    $Secure = ConvertTo-SecureString $Value -AsPlainText -Force
    return ConvertFrom-SecureString $Secure
}

function Unprotect-ValueWithDpapi {
    param([Parameter(Mandatory)][string]$ProtectedValue)

    $Secure = ConvertTo-SecureString $ProtectedValue
    $Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)

    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer)
    }
}

function Save-DpapiVault {
    param(
        [Parameter(Mandatory)][hashtable]$Values,
        [Parameter(Mandatory)][string]$Path
    )

    $ProtectedValues = [ordered]@{}

    foreach ($Key in ($Values.Keys | Sort-Object)) {
        $ProtectedValues[$Key] = Protect-ValueWithDpapi -Value $Values[$Key]
    }

    $Payload = [ordered]@{
        schemaVersion = $VaultSchemaVersion
        protection    = "Windows-DPAPI-CurrentUser"
        createdAt     = (Get-Date).ToString("o")
        machine       = $env:COMPUTERNAME
        user          = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        values        = $ProtectedValues
    }

    $Json = $Payload | ConvertTo-Json -Depth 8
    Write-Utf8NoBom -Path $Path -Content $Json
}

# ============================================================
# COFFRE PORTABLE AES-256-CBC + HMAC-SHA256
# ============================================================

function Join-ByteArrays {
    param([Parameter(Mandatory)][byte[][]]$Arrays)

    $Length = 0

    foreach ($Array in $Arrays) {
        $Length += $Array.Length
    }

    $Result = New-Object byte[] $Length
    $Offset = 0

    foreach ($Array in $Arrays) {
        [Array]::Copy($Array, 0, $Result, $Offset, $Array.Length)
        $Offset += $Array.Length
    }

    return $Result
}

function Test-FixedTimeEqual {
    param(
        [Parameter(Mandatory)][byte[]]$A,
        [Parameter(Mandatory)][byte[]]$B
    )

    if ($A.Length -ne $B.Length) {
        return $false
    }

    $Difference = 0

    for ($Index = 0; $Index -lt $A.Length; $Index++) {
        $Difference = $Difference -bor ($A[$Index] -bxor $B[$Index])
    }

    return ($Difference -eq 0)
}

function New-Pbkdf2Bytes {
    param(
        [Parameter(Mandatory)][string]$Passphrase,
        [Parameter(Mandatory)][byte[]]$Salt,
        [Parameter(Mandatory)][int]$Length,
        [int]$Iterations = 250000
    )

    $Deriver = $null

    try {
        try {
            $Deriver = New-Object `
                System.Security.Cryptography.Rfc2898DeriveBytes(
                    $Passphrase,
                    $Salt,
                    $Iterations,
                    [System.Security.Cryptography.HashAlgorithmName]::SHA256
                )
        }
        catch {
            # Compatibilité de secours avec des environnements .NET anciens.
            $Deriver = New-Object `
                System.Security.Cryptography.Rfc2898DeriveBytes(
                    $Passphrase,
                    $Salt,
                    $Iterations
                )
        }

        return $Deriver.GetBytes($Length)
    }
    finally {
        if ($Deriver) {
            $Deriver.Dispose()
        }
    }
}

function Protect-PortableVault {
    param(
        [Parameter(Mandatory)][hashtable]$Values,
        [Parameter(Mandatory)][string]$Passphrase,
        [Parameter(Mandatory)][string]$OutputPath
    )

    if ($Passphrase.Length -lt 12) {
        throw "Le mot de passe maître doit contenir au moins 12 caractères."
    }

    $PlainPayload = [ordered]@{
        schemaVersion = $VaultSchemaVersion
        createdAt     = (Get-Date).ToString("o")
        owner         = $DefaultOwner
        values        = $Values
    } | ConvertTo-Json -Depth 8 -Compress

    $PlainBytes = [System.Text.Encoding]::UTF8.GetBytes($PlainPayload)
    $Salt = New-Object byte[] 16
    $Iv = New-Object byte[] 16
    $Random = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $Random.GetBytes($Salt)
        $Random.GetBytes($Iv)
    }
    finally {
        $Random.Dispose()
    }

    $Derived = New-Pbkdf2Bytes `
        -Passphrase $Passphrase `
        -Salt $Salt `
        -Length 64

    $EncryptionKey = New-Object byte[] 32
    $MacKey = New-Object byte[] 32

    [Array]::Copy($Derived, 0, $EncryptionKey, 0, 32)
    [Array]::Copy($Derived, 32, $MacKey, 0, 32)

    $Aes = [System.Security.Cryptography.Aes]::Create()

    try {
        $Aes.KeySize = 256
        $Aes.BlockSize = 128
        $Aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $Aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $Aes.Key = $EncryptionKey
        $Aes.IV = $Iv

        $Encryptor = $Aes.CreateEncryptor()

        try {
            $CipherBytes = $Encryptor.TransformFinalBlock(
                $PlainBytes,
                0,
                $PlainBytes.Length
            )
        }
        finally {
            $Encryptor.Dispose()
        }
    }
    finally {
        $Aes.Dispose()
    }

    $AuthenticatedBytes = Join-ByteArrays -Arrays @($Salt, $Iv, $CipherBytes)
    $Hmac = [System.Security.Cryptography.HMACSHA256]::new([byte[]]$MacKey)

    try {
        $Mac = $Hmac.ComputeHash($AuthenticatedBytes)
    }
    finally {
        $Hmac.Dispose()
    }

    $Envelope = [ordered]@{
        format      = "BAW-PORTABLE-VAULT"
        version     = 1
        cipher      = "AES-256-CBC"
        integrity   = "HMAC-SHA256"
        kdf         = "PBKDF2"
        iterations  = 250000
        salt        = [Convert]::ToBase64String($Salt)
        iv          = [Convert]::ToBase64String($Iv)
        ciphertext  = [Convert]::ToBase64String($CipherBytes)
        mac         = [Convert]::ToBase64String($Mac)
    }

    Write-Utf8NoBom `
        -Path $OutputPath `
        -Content ($Envelope | ConvertTo-Json -Depth 5)

    # Contrôle structurel immédiat du fichier créé.
    $WrittenEnvelope = Get-Content -LiteralPath $OutputPath -Raw |
        ConvertFrom-Json

    if (
        $WrittenEnvelope.format -ne "BAW-PORTABLE-VAULT" -or
        [string]::IsNullOrWhiteSpace([string]$WrittenEnvelope.ciphertext) -or
        [string]::IsNullOrWhiteSpace([string]$WrittenEnvelope.mac)
    ) {
        throw "Le coffre portable a été écrit, mais sa structure est invalide."
    }

    [Array]::Clear($PlainBytes, 0, $PlainBytes.Length)
    [Array]::Clear($Derived, 0, $Derived.Length)
    [Array]::Clear($EncryptionKey, 0, $EncryptionKey.Length)
    [Array]::Clear($MacKey, 0, $MacKey.Length)
}

function Unprotect-PortableVault {
    param(
        [Parameter(Mandatory)][string]$VaultPath,
        [Parameter(Mandatory)][string]$Passphrase
    )

    $Envelope = Get-Content -LiteralPath $VaultPath -Raw |
        ConvertFrom-Json

    if ($Envelope.format -ne "BAW-PORTABLE-VAULT") {
        throw "Le fichier sélectionné n'est pas un coffre portable BAW OS."
    }

    $Salt = [Convert]::FromBase64String([string]$Envelope.salt)
    $Iv = [Convert]::FromBase64String([string]$Envelope.iv)
    $CipherBytes = [Convert]::FromBase64String([string]$Envelope.ciphertext)
    $ExpectedMac = [Convert]::FromBase64String([string]$Envelope.mac)
    $Iterations = [int]$Envelope.iterations

    $Derived = New-Pbkdf2Bytes `
        -Passphrase $Passphrase `
        -Salt $Salt `
        -Length 64 `
        -Iterations $Iterations

    $EncryptionKey = New-Object byte[] 32
    $MacKey = New-Object byte[] 32

    [Array]::Copy($Derived, 0, $EncryptionKey, 0, 32)
    [Array]::Copy($Derived, 32, $MacKey, 0, 32)

    $AuthenticatedBytes = Join-ByteArrays -Arrays @($Salt, $Iv, $CipherBytes)
    $Hmac = [System.Security.Cryptography.HMACSHA256]::new([byte[]]$MacKey)

    try {
        $ActualMac = $Hmac.ComputeHash($AuthenticatedBytes)
    }
    finally {
        $Hmac.Dispose()
    }

    if (-not (Test-FixedTimeEqual -A $ExpectedMac -B $ActualMac)) {
        throw "Mot de passe incorrect ou coffre endommagé."
    }

    $Aes = [System.Security.Cryptography.Aes]::Create()

    try {
        $Aes.KeySize = 256
        $Aes.BlockSize = 128
        $Aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $Aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $Aes.Key = $EncryptionKey
        $Aes.IV = $Iv

        $Decryptor = $Aes.CreateDecryptor()

        try {
            $PlainBytes = $Decryptor.TransformFinalBlock(
                $CipherBytes,
                0,
                $CipherBytes.Length
            )
        }
        finally {
            $Decryptor.Dispose()
        }
    }
    finally {
        $Aes.Dispose()
    }

    $Json = [System.Text.Encoding]::UTF8.GetString($PlainBytes)
    $Payload = $Json | ConvertFrom-Json
    $Values = @{}

    foreach ($Property in $Payload.values.PSObject.Properties) {
        $Values[$Property.Name] = [string]$Property.Value
    }

    [Array]::Clear($PlainBytes, 0, $PlainBytes.Length)
    [Array]::Clear($Derived, 0, $Derived.Length)
    [Array]::Clear($EncryptionKey, 0, $EncryptionKey.Length)
    [Array]::Clear($MacKey, 0, $MacKey.Length)

    return $Values
}

# ============================================================
# MIGRATION SÛRE DES ANCIENS CHEMINS DE SECRETS
# ============================================================

function Remove-MigratedLegacySecretFiles {
    param(
        [Parameter(Mandatory)][hashtable]$Values,
        [Parameter(Mandatory)][string]$SecretsRoot
    )

    foreach ($DefinitionObject in $SecretDefinitions) {
        $Definition = [hashtable]$DefinitionObject
        $LegacyRelativePath = [string]$Definition.legacyFilePath

        if ([string]::IsNullOrWhiteSpace($LegacyRelativePath)) {
            continue
        }

        if (
            -not $Values.ContainsKey($Definition.id) -or
            [string]::IsNullOrWhiteSpace($Values[$Definition.id])
        ) {
            continue
        }

        $CanonicalPath = Join-Path `
            $SecretsRoot `
            $Definition.relativePath

        $LegacyPath = Join-Path `
            $SecretsRoot `
            $LegacyRelativePath

        if (-not (Test-Path -LiteralPath $LegacyPath)) {
            continue
        }

        try {
            $CanonicalValue = (
                [System.IO.File]::ReadAllText($CanonicalPath)
            ).Trim()

            $LegacyValue = (
                [System.IO.File]::ReadAllText($LegacyPath)
            ).Trim()

            if ($CanonicalValue -cne $LegacyValue) {
                Write-Notice (
                    "Ancien chemin conservé car sa valeur diffère : " +
                    $LegacyRelativePath
                )

                continue
            }

            Remove-Item `
                -LiteralPath $LegacyPath `
                -Force `
                -ErrorAction Stop

            Write-Success (
                "Ancien chemin migré et supprimé : " +
                $LegacyRelativePath
            )
        }
        catch {
            Write-Notice (
                "Impossible de nettoyer l'ancien chemin : " +
                $LegacyRelativePath
            )
        }
        finally {
            $CanonicalValue = $null
            $LegacyValue = $null
        }
    }

    $LegacyProvidersDirectory = Join-Path `
        $SecretsRoot `
        "providers"

    if (Test-Path -LiteralPath $LegacyProvidersDirectory) {
        $RemainingItems = @(
            Get-ChildItem `
                -LiteralPath $LegacyProvidersDirectory `
                -Force `
                -ErrorAction SilentlyContinue
        )

        if ($RemainingItems.Count -eq 0) {
            Remove-Item `
                -LiteralPath $LegacyProvidersDirectory `
                -Force `
                -ErrorAction SilentlyContinue

            Write-Success "Ancien dossier providers vide supprimé"
        }
    }
}

# ============================================================
# ÉCRITURE DES SECRETS ET INDEX NON SENSIBLE
# ============================================================

function Save-Secrets {
    param(
        [Parameter(Mandatory)][hashtable]$Values,
        [Parameter(Mandatory)][string]$SecretsRoot,
        [Parameter(Mandatory)][string]$BackupsRoot
    )

    $MissingRequired = New-Object System.Collections.Generic.List[string]

    foreach ($DefinitionObject in $SecretDefinitions) {
        $Definition = [hashtable]$DefinitionObject

        if (
            $Definition.required -and
            (
                -not $Values.ContainsKey($Definition.id) -or
                [string]::IsNullOrWhiteSpace($Values[$Definition.id])
            )
        ) {
            $MissingRequired.Add($Definition.label)
        }
    }

    if ($MissingRequired.Count -gt 0) {
        throw (
            "Secrets techniques manquants :`n`n" +
            ($MissingRequired -join "`n")
        )
    }

    $IndexEntries = New-Object System.Collections.Generic.List[object]

    foreach ($DefinitionObject in $SecretDefinitions) {
        $Definition = [hashtable]$DefinitionObject

        if (
            -not $Values.ContainsKey($Definition.id) -or
            [string]::IsNullOrWhiteSpace($Values[$Definition.id])
        ) {
            $IndexEntries.Add([ordered]@{
                id          = $Definition.id
                category    = $Definition.category
                sensitive   = Test-DefinitionSensitive -Definition $Definition
                present     = $false
                fingerprint = ""
                path        = $Definition.relativePath.Replace("\", "/")
            })

            continue
        }

        $Value = [string]$Values[$Definition.id]
        $Path = Join-Path $SecretsRoot $Definition.relativePath

        Write-SecretFile -Path $Path -Value $Value

        $IndexEntries.Add([ordered]@{
            id          = $Definition.id
            category    = $Definition.category
            sensitive   = Test-DefinitionSensitive -Definition $Definition
            present     = $true
            fingerprint = Get-ValueFingerprint -Value $Value
            path        = $Definition.relativePath.Replace("\", "/")
        })
    }

    Remove-MigratedLegacySecretFiles `
        -Values $Values `
        -SecretsRoot $SecretsRoot

    # Configuration non sensible destinée au futur Compose.
    $PostgresNonSecret = @'
POSTGRES_DB=baw_core
POSTGRES_USER=baw_admin
TZ=Europe/Paris
'@

    Write-Utf8NoBom `
        -Path (Join-Path $SecretsRoot "postgres\postgres.nonsecret.env") `
        -Content $PostgresNonSecret

    $N8nNonSecret = @'
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n
N8N_HOST=localhost
N8N_PORT=5678
N8N_PROTOCOL=http
GENERIC_TIMEZONE=Europe/Paris
TZ=Europe/Paris
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
'@

    Write-Utf8NoBom `
        -Path (Join-Path $SecretsRoot "n8n\n8n.nonsecret.env") `
        -Content $N8nNonSecret

    $Index = [ordered]@{
        schemaVersion = $VaultSchemaVersion
        generatedAt   = (Get-Date).ToString("o")
        containsSecretValues = $false
        entries       = $IndexEntries
    }

    Write-Utf8NoBom `
        -Path (Join-Path $SecretsRoot ".secrets-index.json") `
        -Content ($Index | ConvertTo-Json -Depth 8)

    $DpapiDirectory = Join-Path $BackupsRoot "secrets"
    New-Item -ItemType Directory -Path $DpapiDirectory -Force | Out-Null

    $DpapiPath = Join-Path $DpapiDirectory "BAW-secrets-local.dpapi.json"

    Save-DpapiVault `
        -Values $Values `
        -Path $DpapiPath

    Protect-SecretsDirectoryAcl -SecretsRoot $SecretsRoot | Out-Null

    return [PSCustomObject]@{
        DpapiPath = $DpapiPath
        IndexPath = Join-Path $SecretsRoot ".secrets-index.json"
    }
}

# ============================================================
# FICHIERS VERSIONNABLES POUR BAW-OS-DEPLOY
# ============================================================

function Prepare-DeployRepository {
    param(
        [Parameter(Mandatory)][string]$DeployRepository,
        [Parameter(Mandatory)][string]$CurrentScript
    )

    $ScriptsPath = Join-Path $DeployRepository "scripts"
    $ConfigPath = Join-Path $DeployRepository "config"
    $DocsPath = Join-Path $DeployRepository "docs"

    foreach ($Path in @($ScriptsPath, $ConfigPath, $DocsPath)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    if (
        -not [string]::IsNullOrWhiteSpace($CurrentScript) -and
        (Test-Path -LiteralPath $CurrentScript)
    ) {
        Copy-Item `
            -LiteralPath $CurrentScript `
            -Destination (Join-Path $ScriptsPath "BAW-Secrets-Bootstrap.ps1") `
            -Force
    }

    $Launcher = @'
@echo off
title BAW OS - Secrets Bootstrap
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -File -ErrorAction SilentlyContinue ^| Unblock-File -ErrorAction SilentlyContinue"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0BAW-Secrets-Bootstrap.ps1"
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

    Write-Utf8NoBom `
        -Path (Join-Path $ScriptsPath "Lancer-BAW-Secrets-Bootstrap.cmd") `
        -Content $Launcher

    $ManifestEntries = @(
        foreach ($DefinitionObject in $SecretDefinitions) {
            $Definition = [hashtable]$DefinitionObject

            [ordered]@{
                id           = $Definition.id
                label        = $Definition.label
                category     = $Definition.category
                kind         = $Definition.kind
                required     = $Definition.required
                sensitive    = Test-DefinitionSensitive -Definition $Definition
                relativePath = $Definition.relativePath.Replace("\", "/")
                description  = $Definition.description
            }
        }
    )

    $Manifest = [ordered]@{
        schemaVersion = $VaultSchemaVersion
        containsSecretValues = $false
        entries = $ManifestEntries
    }

    Write-Utf8NoBom `
        -Path (Join-Path $ConfigPath "secrets-manifest.json") `
        -Content ($Manifest | ConvertTo-Json -Depth 8)

    $Documentation = @'
# BAW Secrets Bootstrap

## Objectif

Le bootstrap centralise la création et la restauration des secrets nécessaires
à BAW OS.

Les valeurs sensibles sont écrites hors Git, dans le dossier `secrets` de la
racine d'installation.

## Protections

- un fichier distinct par secret ;
- un seul secret canonique par application ;
- compte PostgreSQL d'administration séparé du compte d'automatisation ;
- secret d'automatisation : `postgres\baw_automation_password.txt` ;
- chemins dédiés : `notion`, `mistral`, `openai`, `github`, `smtp`, `wsl` ;
- migration sûre des anciens fichiers du dossier `providers` ;
- les valeurs sensibles sont masquées ; les identifiants non sensibles restent visibles ;
- identifiants WSL : utilisateur `bawops` et mot de passe technique généré ;
- affichage temporaire et copie avec effacement automatique du presse-papiers ;
- héritage NTFS conservé et contrôle total explicitement accordé au compte courant ;
- copie locale DPAPI liée au compte Windows ;
- export portable AES-256 protégé par mot de passe maître ;
- index documentaire sans aucune valeur sensible ;
- aucun secret dans le dépôt `baw-os-deploy`.

## Restauration

Le coffre portable permet de restaurer les secrets sur un nouveau disque ou un
nouveau poste, à condition de conserver son mot de passe maître.

La sauvegarde DPAPI locale ne doit pas être considérée comme portable : elle est
liée au compte Windows qui l'a créée.

Les coffres portables de schéma 1 créés avant la V1.9 restent compatibles.
Lorsqu'une nouvelle entrée WSL est absente d'un ancien coffre, elle peut être
complétée dans l'interface puis enregistrée sans migration destructive.

## n8n

La clé `N8N_ENCRYPTION_KEY` doit rester stable pendant la durée de vie de
l'instance. Elle est sauvegardée avec les autres secrets, séparément de la base
PostgreSQL.

Les fichiers secrets seront montés dans les conteneurs via Docker Compose et
lus avec les variables de configuration suffixées par `_FILE` lorsque le
service le permet.
'@

    Write-Utf8NoBom `
        -Path (Join-Path $DocsPath "SECRETS-BOOTSTRAP.md") `
        -Content $Documentation
}

# ============================================================
# DIALOGUES DE MOT DE PASSE
# ============================================================

function Show-PassphraseDialog {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Instruction,
        [switch]$Confirm
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = $Title
    $Form.StartPosition = "CenterParent"
    $Form.Size = New-Object System.Drawing.Size(520, 245)
    $Form.FormBorderStyle = "FixedDialog"
    $Form.MaximizeBox = $false
    $Form.MinimizeBox = $false

    $Label = New-Object System.Windows.Forms.Label
    $Label.Text = $Instruction
    $Label.Location = New-Object System.Drawing.Point(20, 18)
    $Label.Size = New-Object System.Drawing.Size(470, 45)
    $Form.Controls.Add($Label)

    $PassLabel = New-Object System.Windows.Forms.Label
    $PassLabel.Text = "Mot de passe maître :"
    $PassLabel.Location = New-Object System.Drawing.Point(20, 75)
    $PassLabel.AutoSize = $true
    $Form.Controls.Add($PassLabel)

    $PassBox = New-Object System.Windows.Forms.TextBox
    $PassBox.Location = New-Object System.Drawing.Point(190, 72)
    $PassBox.Size = New-Object System.Drawing.Size(290, 24)
    $PassBox.UseSystemPasswordChar = $true
    $Form.Controls.Add($PassBox)

    $ConfirmBox = $null

    if ($Confirm) {
        $ConfirmLabel = New-Object System.Windows.Forms.Label
        $ConfirmLabel.Text = "Confirmation :"
        $ConfirmLabel.Location = New-Object System.Drawing.Point(20, 112)
        $ConfirmLabel.AutoSize = $true
        $Form.Controls.Add($ConfirmLabel)

        $ConfirmBox = New-Object System.Windows.Forms.TextBox
        $ConfirmBox.Location = New-Object System.Drawing.Point(190, 109)
        $ConfirmBox.Size = New-Object System.Drawing.Size(290, 24)
        $ConfirmBox.UseSystemPasswordChar = $true
        $Form.Controls.Add($ConfirmBox)
    }

    $OkButton = New-Object System.Windows.Forms.Button
    $OkButton.Text = "Valider"
    $OkButton.Location = New-Object System.Drawing.Point(300, 160)
    $OkButton.Size = New-Object System.Drawing.Size(85, 30)

    $CancelButton = New-Object System.Windows.Forms.Button
    $CancelButton.Text = "Annuler"
    $CancelButton.Location = New-Object System.Drawing.Point(395, 160)
    $CancelButton.Size = New-Object System.Drawing.Size(85, 30)

    $OkButton.Add_Click({
        if ($PassBox.Text.Length -lt 12) {
            [System.Windows.Forms.MessageBox]::Show(
                "Le mot de passe doit contenir au moins 12 caractères.",
                "Mot de passe trop court",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null

            return
        }

        if ($Confirm -and $PassBox.Text -ne $ConfirmBox.Text) {
            [System.Windows.Forms.MessageBox]::Show(
                "Les deux mots de passe ne correspondent pas.",
                "Confirmation incorrecte",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null

            return
        }

        $Form.Tag = $PassBox.Text
        $Form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $Form.Close()
    })

    $CancelButton.Add_Click({
        $Form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $Form.Close()
    })

    $Form.AcceptButton = $OkButton
    $Form.CancelButton = $CancelButton
    $Form.Controls.Add($OkButton)
    $Form.Controls.Add($CancelButton)

    if ($Form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return [string]$Form.Tag
    }

    return $null
}

# ============================================================
# INTERFACE PRINCIPALE
# ============================================================

function Get-SecretsFormValues {
    param(
        [Parameter(Mandatory)][object[]]$Definitions,
        [Parameter(Mandatory)][hashtable]$TextBoxes,
        [Parameter(Mandatory)][hashtable]$WorkingValues
    )

    $Values = @{}

    foreach ($DefinitionObject in $Definitions) {
        $Definition = [hashtable]$DefinitionObject
        $Id = [string]$Definition.id
        $Entered = [string]$TextBoxes[$Id].Text

        if (-not [string]::IsNullOrWhiteSpace($Entered)) {
            $Values[$Id] = $Entered
        }
        elseif ($WorkingValues.ContainsKey($Id)) {
            # Par sécurité, un champ accidentellement vidé conserve
            # la valeur déjà enregistrée.
            $Values[$Id] = [string]$WorkingValues[$Id]
        }
    }

    return $Values
}


function Set-SecretsFormValues {
    param(
        [Parameter(Mandatory)][object[]]$Definitions,
        [Parameter(Mandatory)][hashtable]$TextBoxes,
        [Parameter(Mandatory)][hashtable]$Values
    )

    foreach ($DefinitionObject in $Definitions) {
        $Definition = [hashtable]$DefinitionObject
        $Id = [string]$Definition.id
        $TextBox = $TextBoxes[$Id]
        $IsSensitive = Test-DefinitionSensitive -Definition $Definition
        $DefaultValue = Get-DefinitionDefaultValue -Definition $Definition

        $TextBox.UseSystemPasswordChar = $IsSensitive

        if ($Values.ContainsKey($Id)) {
            $TextBox.Text = [string]$Values[$Id]
        }
        elseif (-not [string]::IsNullOrWhiteSpace($DefaultValue)) {
            $TextBox.Text = $DefaultValue
        }
        else {
            $TextBox.Clear()
        }
    }
}


function Update-SecretsFormStatuses {
    param(
        [Parameter(Mandatory)][object[]]$Definitions,
        [Parameter(Mandatory)][hashtable]$TextBoxes,
        [Parameter(Mandatory)][hashtable]$StatusLabels,
        [Parameter(Mandatory)][hashtable]$WorkingValues
    )

    foreach ($DefinitionObject in $Definitions) {
        $Definition = [hashtable]$DefinitionObject
        $Id = [string]$Definition.id
        $Status = $StatusLabels[$Id]
        $CurrentValue = [string]$TextBoxes[$Id].Text

        if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
            $Fingerprint = Get-ValueFingerprint -Value $CurrentValue

            if (
                $WorkingValues.ContainsKey($Id) -and
                ([string]$WorkingValues[$Id] -ceq $CurrentValue)
            ) {
                $Status.Text = "Présent et enregistré — empreinte : $Fingerprint"
                $Status.ForeColor = [System.Drawing.Color]::DarkGreen
            }
            elseif ($WorkingValues.ContainsKey($Id)) {
                $Status.Text = (
                    "Modifié dans la fenêtre — non enregistré — empreinte : " +
                    $Fingerprint
                )
                $Status.ForeColor = [System.Drawing.Color]::DarkBlue
            }
            else {
                $Status.Text = (
                    "Nouvelle valeur — non enregistrée — empreinte : " +
                    $Fingerprint
                )
                $Status.ForeColor = [System.Drawing.Color]::DarkBlue
            }

            continue
        }

        if ($WorkingValues.ContainsKey($Id)) {
            $Status.Text = (
                "Valeur existante conservée même si le champ est vide"
            )
            $Status.ForeColor = [System.Drawing.Color]::DarkGreen
        }
        elseif ($Definition.kind -eq "generated") {
            $Status.Text = "Absent — peut être généré automatiquement"
            $Status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        elseif ($Definition.required) {
            $Status.Text = "Absent — valeur requise"
            $Status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        else {
            $Status.Text = "Absent — facultatif à ce stade"
            $Status.ForeColor = [System.Drawing.Color]::DimGray
        }
    }
}


function Show-SecretsBootstrapForm {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$SecretsRoot,
        [Parameter(Mandatory)][string]$BackupsRoot,
        [Parameter(Mandatory)][string]$DeployRepository
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    [System.Windows.Forms.Application]::EnableVisualStyles()

    try {
        $ExistingValues = Get-AllExistingSecrets -SecretsRoot $SecretsRoot
    }
    catch [System.UnauthorizedAccessException] {
        throw @"
L'accès au coffre est refusé.

Répare d'abord les permissions du dossier :
$SecretsRoot

Puis relance BAW Secrets Bootstrap V$BootstrapVersion.
"@
    }

    $WorkingValues = @{}

    foreach ($Key in $ExistingValues.Keys) {
        $WorkingValues[$Key] = [string]$ExistingValues[$Key]
    }

    $TextBoxes = @{}
    $StatusLabels = @{}

    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "BAW OS — Secrets Bootstrap V$BootstrapVersion"
    $Form.StartPosition = "CenterScreen"
    $Form.Size = New-Object System.Drawing.Size(960, 790)
    $Form.MinimumSize = New-Object System.Drawing.Size(860, 680)

    $Header = New-Object System.Windows.Forms.Label
    $Header.Text = "Coffre central des secrets BAW OS"
    $Header.Font = New-Object System.Drawing.Font(
        "Segoe UI",
        16,
        [System.Drawing.FontStyle]::Bold
    )
    $Header.Location = New-Object System.Drawing.Point(22, 18)
    $Header.AutoSize = $true
    $Form.Controls.Add($Header)

    $RootLabel = New-Object System.Windows.Forms.Label
    $RootLabel.Text = "Racine : $Root"
    $RootLabel.Location = New-Object System.Drawing.Point(25, 55)
    $RootLabel.Size = New-Object System.Drawing.Size(890, 22)
    $Form.Controls.Add($RootLabel)

    $Instruction = New-Object System.Windows.Forms.Label
    $Instruction.Text = @"
Les valeurs sensibles restent masquées ; les identifiants non sensibles restent visibles.
« Voir » révèle un secret 10 secondes. « Copier » vide le presse-papiers après 30 secondes.
"@
    $Instruction.Location = New-Object System.Drawing.Point(25, 82)
    $Instruction.Size = New-Object System.Drawing.Size(890, 42)
    $Form.Controls.Add($Instruction)

    $Panel = New-Object System.Windows.Forms.Panel
    $Panel.Location = New-Object System.Drawing.Point(20, 130)
    $Panel.Size = New-Object System.Drawing.Size(905, 515)
    $Panel.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Top -bor
        [System.Windows.Forms.AnchorStyles]::Bottom -bor
        [System.Windows.Forms.AnchorStyles]::Left -bor
        [System.Windows.Forms.AnchorStyles]::Right
    )
    $Panel.AutoScroll = $true
    $Panel.BorderStyle = "FixedSingle"
    $Form.Controls.Add($Panel)

    $Y = 12
    $CurrentCategory = ""

    foreach ($DefinitionObject in $SecretDefinitions) {
        $Definition = [hashtable]$DefinitionObject
        $Id = [string]$Definition.id

        if ($Definition.category -ne $CurrentCategory) {
            $CurrentCategory = [string]$Definition.category

            $CategoryLabel = New-Object System.Windows.Forms.Label
            $CategoryLabel.Text = $CurrentCategory
            $CategoryLabel.Font = New-Object System.Drawing.Font(
                "Segoe UI",
                11,
                [System.Drawing.FontStyle]::Bold
            )
            $CategoryLabel.Location = New-Object System.Drawing.Point(15, $Y)
            $CategoryLabel.Size = New-Object System.Drawing.Size(850, 25)
            $Panel.Controls.Add($CategoryLabel)

            $Y += 34
        }

        $Label = New-Object System.Windows.Forms.Label
        $Label.Text = [string]$Definition.label
        $Label.Location = New-Object System.Drawing.Point(20, $Y)
        $Label.Size = New-Object System.Drawing.Size(290, 22)
        $Panel.Controls.Add($Label)

        $TextBox = New-Object System.Windows.Forms.TextBox
        $TextBox.Location = New-Object System.Drawing.Point(315, ($Y - 3))
        $TextBox.Size = New-Object System.Drawing.Size(390, 24)
        $IsSensitive = Test-DefinitionSensitive -Definition $Definition
        $DefaultValue = Get-DefinitionDefaultValue -Definition $Definition
        $TextBox.UseSystemPasswordChar = $IsSensitive
        $TextBox.Tag = $Id

        if ($WorkingValues.ContainsKey($Id)) {
            $TextBox.Text = [string]$WorkingValues[$Id]
        }
        elseif (-not [string]::IsNullOrWhiteSpace($DefaultValue)) {
            $TextBox.Text = $DefaultValue
        }

        $Panel.Controls.Add($TextBox)
        $TextBoxes[$Id] = $TextBox

        $Status = New-Object System.Windows.Forms.Label
        $Status.Location = New-Object System.Drawing.Point(315, ($Y + 24))
        $Status.Size = New-Object System.Drawing.Size(540, 18)
        $Status.Font = New-Object System.Drawing.Font(
            "Segoe UI",
            8,
            [System.Drawing.FontStyle]::Italic
        )
        $Panel.Controls.Add($Status)
        $StatusLabels[$Id] = $Status

        # ----------------------------------------------------
        # Affichage temporaire
        # ----------------------------------------------------

        $ShowButton = New-Object System.Windows.Forms.Button
        $ShowButton.Text = "Voir"
        $ShowButton.Location = New-Object System.Drawing.Point(715, ($Y - 4))
        $ShowButton.Size = New-Object System.Drawing.Size(58, 26)
        $ShowButton.Visible = $IsSensitive
        $ShowButton.Enabled = $IsSensitive

        $RevealTimer = New-Object System.Windows.Forms.Timer
        $RevealTimer.Interval = 10000

        $RevealContext = [PSCustomObject]@{
            TextBox = $TextBox
            Button  = $ShowButton
            Timer   = $RevealTimer
        }

        $ShowButton.Tag = $RevealContext
        $RevealTimer.Tag = $RevealContext

        $RevealTimer.Add_Tick({
            param($Sender, $EventArgs)

            $Context = $Sender.Tag
            $Context.TextBox.UseSystemPasswordChar = $true
            $Context.Button.Text = "Voir"
            $Sender.Stop()
        })

        $ShowButton.Add_Click({
            param($Sender, $EventArgs)

            $Context = $Sender.Tag
            $Box = $Context.TextBox

            if ([string]::IsNullOrWhiteSpace($Box.Text)) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Aucune valeur n'est disponible pour ce secret.",
                    "Secret absent",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null

                return
            }

            if (-not $Box.UseSystemPasswordChar) {
                $Context.Timer.Stop()
                $Box.UseSystemPasswordChar = $true
                $Sender.Text = "Voir"
                return
            }

            $Confirmation = [System.Windows.Forms.MessageBox]::Show(
                "Afficher cette valeur pendant 10 secondes ?",
                "Afficher temporairement le secret",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning,
                [System.Windows.Forms.MessageBoxDefaultButton]::Button2
            )

            if ($Confirmation -ne [System.Windows.Forms.DialogResult]::Yes) {
                return
            }

            $Box.UseSystemPasswordChar = $false
            $Sender.Text = "Masquer"
            $Context.Timer.Stop()
            $Context.Timer.Start()
        })

        $Panel.Controls.Add($ShowButton)

        # ----------------------------------------------------
        # Copie temporaire dans le presse-papiers
        # ----------------------------------------------------

        $CopyButton = New-Object System.Windows.Forms.Button
        $CopyButton.Text = "Copier"
        $CopyButton.Location = New-Object System.Drawing.Point(780, ($Y - 4))
        $CopyButton.Size = New-Object System.Drawing.Size(68, 26)

        $ClipboardTimer = New-Object System.Windows.Forms.Timer
        $ClipboardTimer.Interval = 30000

        $CopyContext = [PSCustomObject]@{
            TextBox = $TextBox
            Status  = $Status
            Timer   = $ClipboardTimer
            Value   = $null
        }

        $CopyButton.Tag = $CopyContext
        $ClipboardTimer.Tag = $CopyContext

        $ClipboardTimer.Add_Tick({
            param($Sender, $EventArgs)

            $Context = $Sender.Tag

            try {
                if (
                    [System.Windows.Forms.Clipboard]::ContainsText() -and
                    [System.Windows.Forms.Clipboard]::GetText() -ceq
                    [string]$Context.Value
                ) {
                    [System.Windows.Forms.Clipboard]::Clear()
                }
            }
            catch {
                # Le presse-papiers peut être brièvement verrouillé
                # par une autre application. Aucun secret n'est journalisé.
            }
            finally {
                $Context.Value = $null
                $Sender.Stop()
                $Context.Status.Text = "Presse-papiers sécurisé après copie"
                $Context.Status.ForeColor = [System.Drawing.Color]::DarkGreen
            }
        })

        $CopyButton.Add_Click({
            param($Sender, $EventArgs)

            $Context = $Sender.Tag
            $Value = [string]$Context.TextBox.Text

            if ([string]::IsNullOrWhiteSpace($Value)) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Aucune valeur n'est disponible pour ce secret.",
                    "Secret absent",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null

                return
            }

            try {
                [System.Windows.Forms.Clipboard]::SetText($Value)
                $Context.Value = $Value
                $Context.Timer.Stop()
                $Context.Timer.Start()
                $Context.Status.Text = (
                    "Copié — le presse-papiers sera vidé dans 30 secondes"
                )
                $Context.Status.ForeColor = [System.Drawing.Color]::DarkBlue
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show(
                    "Le presse-papiers Windows est momentanément indisponible.",
                    "Copie impossible",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                ) | Out-Null
            }
        })

        $Panel.Controls.Add($CopyButton)

        $Y += 58
    }

    $UiState = [PSCustomObject]@{
        Definitions    = $SecretDefinitions
        TextBoxes      = $TextBoxes
        StatusLabels   = $StatusLabels
        WorkingValues  = $WorkingValues
        SecretsRoot    = $SecretsRoot
        BackupsRoot    = $BackupsRoot
        DeployRepository = $DeployRepository
        Form           = $Form
    }

    # Les événements TextChanged utilisent le même état central,
    # ce qui évite les problèmes de portée des variables dans WinForms.
    foreach ($DefinitionObject in $SecretDefinitions) {
        $Definition = [hashtable]$DefinitionObject
        $Id = [string]$Definition.id
        $TextBox = $TextBoxes[$Id]
        $TextBox.Tag = [PSCustomObject]@{
            Id    = $Id
            State = $UiState
        }

        $TextBox.Add_TextChanged({
            param($Sender, $EventArgs)

            $State = $Sender.Tag.State

            Update-SecretsFormStatuses `
                -Definitions $State.Definitions `
                -TextBoxes $State.TextBoxes `
                -StatusLabels $State.StatusLabels `
                -WorkingValues $State.WorkingValues
        })
    }

    $GenerateButton = New-Object System.Windows.Forms.Button
    $GenerateButton.Text = "Générer les secrets techniques manquants"
    $GenerateButton.Location = New-Object System.Drawing.Point(25, 660)
    $GenerateButton.Size = New-Object System.Drawing.Size(270, 36)
    $GenerateButton.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Bottom -bor
        [System.Windows.Forms.AnchorStyles]::Left
    )
    $GenerateButton.Tag = $UiState
    $Form.Controls.Add($GenerateButton)

    $SaveButton = New-Object System.Windows.Forms.Button
    $SaveButton.Text = "Enregistrer le coffre"
    $SaveButton.Location = New-Object System.Drawing.Point(305, 660)
    $SaveButton.Size = New-Object System.Drawing.Size(170, 36)
    $SaveButton.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Bottom -bor
        [System.Windows.Forms.AnchorStyles]::Left
    )
    $SaveButton.Tag = $UiState
    $Form.Controls.Add($SaveButton)

    $ExportButton = New-Object System.Windows.Forms.Button
    $ExportButton.Text = "Exporter un coffre portable"
    $ExportButton.Location = New-Object System.Drawing.Point(485, 660)
    $ExportButton.Size = New-Object System.Drawing.Size(200, 36)
    $ExportButton.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Bottom -bor
        [System.Windows.Forms.AnchorStyles]::Left
    )
    $ExportButton.Tag = $UiState
    $Form.Controls.Add($ExportButton)

    $RestoreButton = New-Object System.Windows.Forms.Button
    $RestoreButton.Text = "Restaurer un coffre"
    $RestoreButton.Location = New-Object System.Drawing.Point(695, 660)
    $RestoreButton.Size = New-Object System.Drawing.Size(165, 36)
    $RestoreButton.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Bottom -bor
        [System.Windows.Forms.AnchorStyles]::Left
    )
    $RestoreButton.Tag = $UiState
    $Form.Controls.Add($RestoreButton)

    $CloseButton = New-Object System.Windows.Forms.Button
    $CloseButton.Text = "Fermer"
    $CloseButton.Location = New-Object System.Drawing.Point(825, 710)
    $CloseButton.Size = New-Object System.Drawing.Size(85, 30)
    $CloseButton.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Bottom -bor
        [System.Windows.Forms.AnchorStyles]::Right
    )
    $Form.Controls.Add($CloseButton)

    $Footer = New-Object System.Windows.Forms.Label
    $Footer.Text = (
        "Les champs sont modifiables. Un champ vidé par erreur conserve " +
        "la valeur déjà enregistrée."
    )
    $Footer.Location = New-Object System.Drawing.Point(25, 716)
    $Footer.Size = New-Object System.Drawing.Size(760, 22)
    $Footer.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Bottom -bor
        [System.Windows.Forms.AnchorStyles]::Left
    )
    $Form.Controls.Add($Footer)

    $GenerateButton.Add_Click({
        param($Sender, $EventArgs)

        $State = $Sender.Tag
        $GeneratedCount = 0

        foreach ($DefinitionObject in $State.Definitions) {
            $Definition = [hashtable]$DefinitionObject
            $Id = [string]$Definition.id

            if ($Definition.kind -ne "generated") {
                continue
            }

            $TextBox = $State.TextBoxes[$Id]

            if (-not [string]::IsNullOrWhiteSpace($TextBox.Text)) {
                continue
            }

            if ($State.WorkingValues.ContainsKey($Id)) {
                $TextBox.Text = [string]$State.WorkingValues[$Id]
                continue
            }

            $TextBox.Text = New-RandomSecret -ByteLength 48
            $GeneratedCount++
        }

        Update-SecretsFormStatuses `
            -Definitions $State.Definitions `
            -TextBoxes $State.TextBoxes `
            -StatusLabels $State.StatusLabels `
            -WorkingValues $State.WorkingValues

        if ($GeneratedCount -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "Tous les secrets techniques sont déjà présents.",
                "Aucun secret manquant",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
        else {
            [System.Windows.Forms.MessageBox]::Show(
                "$GeneratedCount secret(s) technique(s) généré(s).`n`n" +
                "Clique sur « Enregistrer le coffre » pour les conserver.",
                "Génération terminée",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
    })

    $SaveButton.Add_Click({
        param($Sender, $EventArgs)

        try {
            $State = $Sender.Tag

            $Values = Get-SecretsFormValues `
                -Definitions $State.Definitions `
                -TextBoxes $State.TextBoxes `
                -WorkingValues $State.WorkingValues

            $GeneratedCount = 0

            foreach ($DefinitionObject in $State.Definitions) {
                $Definition = [hashtable]$DefinitionObject
                $Id = [string]$Definition.id

                if (
                    $Definition.kind -eq "generated" -and
                    (
                        -not $Values.ContainsKey($Id) -or
                        [string]::IsNullOrWhiteSpace($Values[$Id])
                    )
                ) {
                    $GeneratedValue = New-RandomSecret -ByteLength 48
                    $Values[$Id] = $GeneratedValue
                    $State.TextBoxes[$Id].Text = $GeneratedValue
                    $GeneratedCount++
                }
            }

            $Result = Save-Secrets `
                -Values $Values `
                -SecretsRoot $State.SecretsRoot `
                -BackupsRoot $State.BackupsRoot

            $State.WorkingValues.Clear()

            foreach ($Key in $Values.Keys) {
                $State.WorkingValues[$Key] = [string]$Values[$Key]
            }

            Set-SecretsFormValues `
                -Definitions $State.Definitions `
                -TextBoxes $State.TextBoxes `
                -Values $State.WorkingValues

            Update-SecretsFormStatuses `
                -Definitions $State.Definitions `
                -TextBoxes $State.TextBoxes `
                -StatusLabels $State.StatusLabels `
                -WorkingValues $State.WorkingValues

            Prepare-DeployRepository `
                -DeployRepository $State.DeployRepository `
                -CurrentScript $PSCommandPath

            $GeneratedMessage = if ($GeneratedCount -gt 0) {
                "`nSecrets techniques générés automatiquement : $GeneratedCount"
            }
            else {
                ""
            }

            [System.Windows.Forms.MessageBox]::Show(
                "Le coffre a été enregistré.`n`n" +
                "Sauvegarde locale DPAPI :`n$($Result.DpapiPath)" +
                $GeneratedMessage +
                "`n`nAucune valeur sensible n'a été écrite dans Git.",
                "Coffre enregistré",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                "Erreur d'enregistrement",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })

    $ExportButton.Add_Click({
        param($Sender, $EventArgs)

        try {
            $State = $Sender.Tag

            $Values = Get-SecretsFormValues `
                -Definitions $State.Definitions `
                -TextBoxes $State.TextBoxes `
                -WorkingValues $State.WorkingValues

            if ($Values.Count -eq 0) {
                throw "Aucun secret n'est actuellement disponible à exporter."
            }

            $Passphrase = Show-PassphraseDialog `
                -Title "Exporter le coffre portable" `
                -Instruction (
                    "Choisissez un mot de passe maître portable. " +
                    "Il sera indispensable lors d'une restauration."
                ) `
                -Confirm

            if ([string]::IsNullOrWhiteSpace($Passphrase)) {
                return
            }

            $DefaultDirectory = Join-Path $State.BackupsRoot "secrets"

            New-Item `
                -ItemType Directory `
                -Path $DefaultDirectory `
                -Force |
                Out-Null

            $SaveDialog = New-Object System.Windows.Forms.SaveFileDialog
            $SaveDialog.Title = "Enregistrer le coffre portable"
            $SaveDialog.Filter = "Coffre BAW OS (*.bawvault)|*.bawvault"
            $SaveDialog.InitialDirectory = $DefaultDirectory
            $SaveDialog.FileName = (
                "BAW-Secrets-{0}.bawvault" -f
                (Get-Date -Format "yyyyMMdd-HHmmss")
            )

            if (
                $SaveDialog.ShowDialog() -ne
                [System.Windows.Forms.DialogResult]::OK
            ) {
                return
            }

            Protect-PortableVault `
                -Values $Values `
                -Passphrase $Passphrase `
                -OutputPath $SaveDialog.FileName

            $Passphrase = $null

            [System.Windows.Forms.MessageBox]::Show(
                "Coffre portable créé :`n`n$($SaveDialog.FileName)`n`n" +
                "Conserve séparément le fichier et son mot de passe maître.",
                "Export terminé",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                "Erreur d'export",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })

    $RestoreButton.Add_Click({
        param($Sender, $EventArgs)

        try {
            $State = $Sender.Tag
            $OpenDialog = New-Object System.Windows.Forms.OpenFileDialog
            $OpenDialog.Title = "Sélectionner un coffre BAW OS"
            $OpenDialog.Filter = "Coffre BAW OS (*.bawvault)|*.bawvault"

            if (
                $OpenDialog.ShowDialog() -ne
                [System.Windows.Forms.DialogResult]::OK
            ) {
                return
            }

            $Passphrase = Show-PassphraseDialog `
                -Title "Restaurer le coffre portable" `
                -Instruction "Saisissez le mot de passe maître du coffre."

            if ([string]::IsNullOrWhiteSpace($Passphrase)) {
                return
            }

            $Restored = Unprotect-PortableVault `
                -VaultPath $OpenDialog.FileName `
                -Passphrase $Passphrase

            $Passphrase = $null
            $State.WorkingValues.Clear()

            foreach ($Key in $Restored.Keys) {
                $State.WorkingValues[$Key] = [string]$Restored[$Key]
            }

            Set-SecretsFormValues `
                -Definitions $State.Definitions `
                -TextBoxes $State.TextBoxes `
                -Values $State.WorkingValues

            Update-SecretsFormStatuses `
                -Definitions $State.Definitions `
                -TextBoxes $State.TextBoxes `
                -StatusLabels $State.StatusLabels `
                -WorkingValues $State.WorkingValues

            [System.Windows.Forms.MessageBox]::Show(
                "Le coffre a été déchiffré et chargé dans les champs.`n`n" +
                "Les valeurs restent masquées. Clique sur " +
                "« Enregistrer le coffre » pour les écrire sur ce poste.",
                "Coffre chargé",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                "Restauration impossible",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })

    $CloseButton.Add_Click({
        $Form.Close()
    })

    Update-SecretsFormStatuses `
        -Definitions $SecretDefinitions `
        -TextBoxes $TextBoxes `
        -StatusLabels $StatusLabels `
        -WorkingValues $WorkingValues

    $Form.ShowDialog() | Out-Null
}

# ============================================================
# EXÉCUTION
# ============================================================

try {
    Write-Step "BAW Secrets Bootstrap"

    $Root = Resolve-InstallRoot `
        -RequestedRoot $InstallRoot `
        -DisableGui:$NoGuiRootSelection

    if ([string]::IsNullOrWhiteSpace($Root)) {
        throw "Aucune racine BAW OS n'a été sélectionnée."
    }

    $SecretsRoot = Join-Path $Root "secrets"
    $BackupsRoot = Join-Path $Root "backups"
    $DeployRepository = Join-Path $Root "repositories\baw-os-deploy"

    foreach ($Path in @(
        $Root,
        $SecretsRoot,
        $BackupsRoot,
        $DeployRepository
    )) {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
    }

    Write-Success "Racine : $Root"
    Write-Info "Secrets : $SecretsRoot"
    Write-Info "Sauvegardes : $BackupsRoot"

    Show-SecretsBootstrapForm `
        -Root $Root `
        -SecretsRoot $SecretsRoot `
        -BackupsRoot $BackupsRoot `
        -DeployRepository $DeployRepository

    Write-Success "BAW Secrets Bootstrap terminé"
}
catch {
    Write-Host ""
    Write-Host "✘ ÉCHEC" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
