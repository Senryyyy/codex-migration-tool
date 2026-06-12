#requires -version 5.0
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Export', 'Import', 'Verify')]
    [string] $Mode,

    [string] $PackagePath,

    [string] $UserProfileRoot = $env:USERPROFILE,

    [switch] $IncludeHeavyCaches,

    [switch] $Force
)

function Write-CodexMigrationInfo {
    param([string] $Message)
    Write-Host "[codex-migrate] $Message"
}

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string] $Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Normalize-MigrationPackagePath {
    param([Parameter(Mandatory = $true)][string] $Path)

    $Normalized = $Path.Trim()
    $Normalized = $Normalized.Trim([char[]]@('"', "'"))
    $Normalized = $Normalized.Replace('/', '\')

    if ([string]::IsNullOrWhiteSpace($Normalized)) {
        return $Normalized
    }

    if ($Normalized.StartsWith('\') -and (-not $Normalized.StartsWith('\\'))) {
        return "\$Normalized"
    }

    $LooksLikeDrivePath = $Normalized -match '^[A-Za-z]:\\'
    $LooksLikeUncPath = $Normalized.StartsWith('\\')
    $LooksLikeRelativePath = $Normalized.StartsWith('.') -or $Normalized.StartsWith('~')
    $LooksLikeComputerShare = $Normalized -match '^[^\\/:]+\\[^\\/:]+($|\\)'

    if ((-not $LooksLikeDrivePath) -and (-not $LooksLikeUncPath) -and (-not $LooksLikeRelativePath) -and $LooksLikeComputerShare) {
        return "\\$Normalized"
    }

    return $Normalized
}

function Test-UncShareRoot {
    param([Parameter(Mandatory = $true)][string] $Path)

    $Normalized = Normalize-MigrationPackagePath -Path $Path
    $Trimmed = $Normalized.TrimEnd('\')
    return [bool]($Trimmed -match '^\\\\[^\\]+\\[^\\]+$')
}

function Ensure-DirectoryExists {
    param([Parameter(Mandatory = $true)][string] $Path)

    if (Test-Path -LiteralPath $Path) {
        return
    }

    if (Test-UncShareRoot -Path $Path) {
        throw "The network share root is not reachable: $Path"
    }

    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Get-DefaultRobocopyExcludedDirectories {
    return @(
        'node_modules',
        '.venv',
        'venv',
        'env',
        '__pycache__',
        '.pytest_cache',
        '.mypy_cache',
        '.ruff_cache',
        '.tox',
        '.nox',
        '.cache',
        '.parcel-cache',
        '.turbo',
        '.next',
        '.nuxt',
        'dist',
        'build',
        'coverage',
        'target',
        'out',
        '.gradle',
        '.idea\system',
        '.git\worktrees'
    )
}

function Get-DefaultRobocopyExcludedFiles {
    return @(
        '*.pyc',
        '*.pyo',
        '.DS_Store',
        'Thumbs.db',
        'Desktop.ini'
    )
}

function ConvertTo-SafePathSegment {
    param([Parameter(Mandatory = $true)][string] $Value)

    $Invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $Chars = $Value.ToCharArray() | ForEach-Object {
        if ($Invalid -contains $_) {
            '_'
        }
        else {
            $_
        }
    }

    $Segment = (-join $Chars).Trim()
    if ([string]::IsNullOrWhiteSpace($Segment)) {
        return 'project'
    }

    return $Segment
}

function New-ExtraProjectMigrationPlan {
    param([string[]] $ProjectPaths)

    $Plan = @()
    $Index = 1
    $Seen = @{}

    foreach ($ProjectPath in @($ProjectPaths)) {
        if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
            continue
        }

        $Normalized = Get-NormalizedFullPath -Path (Normalize-MigrationPackagePath -Path $ProjectPath)
        if ($Seen.ContainsKey($Normalized.ToLowerInvariant())) {
            continue
        }

        if (-not (Test-Path -LiteralPath $Normalized -PathType Container)) {
            throw "Extra project folder does not exist: $Normalized"
        }

        $Seen[$Normalized.ToLowerInvariant()] = $true
        $Leaf = Split-Path -Leaf $Normalized.TrimEnd('\', '/')
        $SafeLeaf = ConvertTo-SafePathSegment -Value $Leaf
        $RelativePath = "ExtraProjects\{0:D3}-{1}" -f $Index, $SafeLeaf

        $Plan += [pscustomobject]@{
            SourcePath          = (Resolve-Path -LiteralPath $Normalized).Path
            DestinationPath     = (Resolve-Path -LiteralPath $Normalized).Path
            PackageRelativePath = $RelativePath
        }

        $Index++
    }

    return $Plan
}

function Export-ExtraProjectFolders {
    param(
        [string[]] $ProjectPaths,
        [Parameter(Mandatory = $true)][string] $PackagePath,
        [switch] $Preview
    )

    $PackagePath = Normalize-MigrationPackagePath -Path $PackagePath
    $PackageFull = Get-NormalizedFullPath -Path $PackagePath
    $Plan = @(New-ExtraProjectMigrationPlan -ProjectPaths $ProjectPaths)

    if ($Plan.Count -eq 0) {
        return
    }

    Write-CodexMigrationInfo "extra project folders: $($Plan.Count)"
    if (-not $Preview) {
        Ensure-DirectoryExists -Path $PackageFull
    }

    foreach ($Project in $Plan) {
        Write-CodexMigrationInfo "copy ExtraProject: $($Project.SourcePath)"
        $Destination = Join-Path $PackageFull $Project.PackageRelativePath
        Invoke-SafeCopy `
            -Source $Project.SourcePath `
            -Destination $Destination `
            -Kind 'Directory' `
            -Preview:$Preview `
            -UseDefaultExclusions:$false
    }

    if ($Preview) {
        return
    }

    $Map = [pscustomobject]@{
        Version      = 1
        CreatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        Projects     = @($Plan)
    }

    $MapPath = Join-Path $PackageFull 'extra-projects.json'
    $Map | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $MapPath -Encoding UTF8

    Write-CodexMigrationInfo "extra project map written: $MapPath"
    Write-CodexMigrationInfo 'extra projects are tracked in extra-projects.json and are not hashed into migration-manifest.json.'
}

function Import-ExtraProjectFolders {
    param(
        [Parameter(Mandatory = $true)][string] $PackagePath,
        [switch] $Preview
    )

    $PackagePath = Normalize-MigrationPackagePath -Path $PackagePath
    $PackageFull = Get-NormalizedFullPath -Path $PackagePath
    $MapPath = Join-Path $PackageFull 'extra-projects.json'

    if (-not (Test-Path -LiteralPath $MapPath)) {
        Write-CodexMigrationInfo 'no extra project map found; skipping extra projects.'
        return
    }

    $Map = Get-Content -LiteralPath $MapPath -Raw | ConvertFrom-Json
    foreach ($Project in @($Map.Projects)) {
        $Source = Join-Path $PackageFull $Project.PackageRelativePath
        $Destination = [string]$Project.DestinationPath

        if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
            throw "Extra project package folder is missing: $Source"
        }

        Write-CodexMigrationInfo "restore ExtraProject: $Destination"
        Invoke-SafeCopy `
            -Source $Source `
            -Destination $Destination `
            -Kind 'Directory' `
            -Preview:$Preview `
            -UseDefaultExclusions:$false
    }
}

function Test-ExtraProjectPackageFolders {
    param([Parameter(Mandatory = $true)][string] $PackagePath)

    $PackagePath = Normalize-MigrationPackagePath -Path $PackagePath
    $PackageFull = Get-NormalizedFullPath -Path $PackagePath
    $MapPath = Join-Path $PackageFull 'extra-projects.json'

    if (-not (Test-Path -LiteralPath $MapPath)) {
        return
    }

    $Map = Get-Content -LiteralPath $MapPath -Raw | ConvertFrom-Json
    foreach ($Project in @($Map.Projects)) {
        $Source = Join-Path $PackageFull $Project.PackageRelativePath
        if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
            throw "Extra project package folder is missing: $Source"
        }
    }

    Write-CodexMigrationInfo "extra project folder references verified: $(@($Map.Projects).Count)"
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string] $BasePath,
        [Parameter(Mandatory = $true)][string] $Path
    )

    $BaseFull = (Get-NormalizedFullPath -Path $BasePath).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $PathFull = Get-NormalizedFullPath -Path $Path

    if ($PathFull.StartsWith($BaseFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $PathFull.Substring($BaseFull.Length)
    }

    $BaseUri = New-Object System.Uri($BaseFull)
    $PathUri = New-Object System.Uri($PathFull)
    return [System.Uri]::UnescapeDataString($BaseUri.MakeRelativeUri($PathUri).ToString()).Replace('/', '\')
}

function ConvertTo-LongLiteralPath {
    param([Parameter(Mandatory = $true)][string] $Path)

    $FullPath = Get-NormalizedFullPath -Path $Path

    if ($FullPath.StartsWith('\\?\')) {
        return $FullPath
    }

    if ($FullPath.StartsWith('\\')) {
        return "\\?\UNC\$($FullPath.TrimStart('\'))"
    }

    if ($FullPath -match '^[A-Za-z]:\\') {
        return "\\?\$FullPath"
    }

    return $FullPath
}

function Test-ExcludedCodexPath {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $CodexRoot,
        [switch] $IncludeHeavyCaches
    )

    $FullPath = Get-NormalizedFullPath -Path $Path
    $RootPath = (Get-NormalizedFullPath -Path $CodexRoot).TrimEnd('\', '/')

    if (-not $FullPath.StartsWith($RootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    $Relative = $FullPath.Substring($RootPath.Length).TrimStart('\', '/')
    $Parts = @($Relative -split '[\\/]' | Where-Object { $_ -ne '' })
    if ($Parts.Count -eq 0) {
        return $false
    }

    $LeafName = [System.IO.Path]::GetFileName($FullPath)
    $AlwaysExcludedFiles = @(
        'auth.json',
        'installation_id',
        'cap_sid',
        'chrome-native-hosts.json',
        'chrome-native-hosts-v2.json'
    )

    if ($AlwaysExcludedFiles -contains $LeafName) {
        return $true
    }

    if ($LeafName -like 'logs_*.sqlite*') {
        return $true
    }

    $HeavyRoots = @(
        '.sandbox',
        '.sandbox-bin',
        '.sandbox-secrets',
        '.tmp',
        'tmp',
        'browser',
        'node_repl',
        'process_manager',
        'computer-use',
        'computer-use-turn-ended',
        'vendor_imports'
    )

    if ((-not $IncludeHeavyCaches) -and ($HeavyRoots -contains $Parts[0])) {
        return $true
    }

    return $false
}

function New-MigrationItem {
    param(
        [Parameter(Mandatory = $true)][string] $Source,
        [Parameter(Mandatory = $true)][string] $RelativePath,
        [Parameter(Mandatory = $true)][string] $Kind
    )

    [pscustomobject]@{
        Source       = $Source
        RelativePath = $RelativePath
        Kind         = $Kind
    }
}

function Get-CodexMigrationItemPlan {
    param(
        [string] $UserProfileRoot = $env:USERPROFILE,
        [switch] $IncludeHeavyCaches
    )

    $Items = @()
    $CodexRoot = Join-Path $UserProfileRoot '.codex'
    $DocumentsCodex = Join-Path $UserProfileRoot 'Documents\Codex'

    if (Test-Path -LiteralPath $DocumentsCodex) {
        $Items += New-MigrationItem -Source $DocumentsCodex -RelativePath 'Documents\Codex' -Kind 'Directory'
    }

    $CodexDirectories = @(
        'sessions',
        'archived_sessions',
        'memories',
        'skills',
        'skills-disabled',
        'plugins',
        'rules',
        'superpowers'
    )

    if ($IncludeHeavyCaches) {
        $CodexDirectories += @('browser', 'node_repl', 'computer-use', 'vendor_imports')
    }

    foreach ($DirectoryName in $CodexDirectories) {
        $Source = Join-Path $CodexRoot $DirectoryName
        if ((Test-Path -LiteralPath $Source) -and (-not (Test-ExcludedCodexPath -Path $Source -CodexRoot $CodexRoot -IncludeHeavyCaches:$IncludeHeavyCaches))) {
            $Items += New-MigrationItem -Source $Source -RelativePath ".codex\$DirectoryName" -Kind 'Directory'
        }
    }

    $CodexFiles = @(
        'config.toml',
        'AGENTS.md',
        'session_index.jsonl',
        '.codex-global-state.json',
        '.codex-global-state.json.bak'
    )

    foreach ($FileName in $CodexFiles) {
        $Source = Join-Path $CodexRoot $FileName
        if ((Test-Path -LiteralPath $Source) -and (-not (Test-ExcludedCodexPath -Path $Source -CodexRoot $CodexRoot -IncludeHeavyCaches:$IncludeHeavyCaches))) {
            $Items += New-MigrationItem -Source $Source -RelativePath ".codex\$FileName" -Kind 'File'
        }
    }

    if (Test-Path -LiteralPath $CodexRoot) {
        $SqliteFiles = Get-ChildItem -LiteralPath $CodexRoot -File -Filter '*.sqlite*' -ErrorAction SilentlyContinue |
            Where-Object { -not (Test-ExcludedCodexPath -Path $_.FullName -CodexRoot $CodexRoot -IncludeHeavyCaches:$IncludeHeavyCaches) }

        foreach ($SqliteFile in $SqliteFiles) {
            $Items += New-MigrationItem -Source $SqliteFile.FullName -RelativePath ".codex\$($SqliteFile.Name)" -Kind 'File'
        }
    }

    return $Items
}

function New-CodexManifestFileEntry {
    param(
        [Parameter(Mandatory = $true)][string] $RootPath,
        [Parameter(Mandatory = $true)][string] $FilePath
    )

    try {
        if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
            return $null
        }

        $Item = Get-Item -LiteralPath $FilePath -ErrorAction Stop
        try {
            $Hash = Get-FileHash -LiteralPath $Item.FullName -Algorithm SHA256 -ErrorAction Stop
        }
        catch {
            $LongPath = ConvertTo-LongLiteralPath -Path $Item.FullName
            $Hash = Get-FileHash -LiteralPath $LongPath -Algorithm SHA256 -ErrorAction Stop
        }

        [pscustomobject]@{
            RelativePath   = Get-RelativePath -BasePath $RootPath -Path $Item.FullName
            Size           = $Item.Length
            LastWriteTime  = $Item.LastWriteTimeUtc.ToString('o')
            HashAlgorithm  = 'SHA256'
            SHA256         = $Hash.Hash.ToLowerInvariant()
        }
    }
    catch {
        Write-Warning "Skipping manifest entry for '$FilePath': $($_.Exception.Message)"
        return $null
    }
}

function New-CodexMigrationManifest {
    param(
        [Parameter(Mandatory = $true)][string] $RootPath,
        [string] $Mode = 'Export',
        [string] $ComputerName = $env:COMPUTERNAME
    )

    $RootFull = Get-NormalizedFullPath -Path $RootPath
    $Entries = @()
    $SkippedEntries = @()

    if (Test-Path -LiteralPath $RootFull) {
        foreach ($File in @(Get-ChildItem -LiteralPath $RootFull -Recurse -File -Force -ErrorAction SilentlyContinue |
                Sort-Object FullName)) {
            $RelativeForFilter = Get-RelativePath -BasePath $RootFull -Path $File.FullName
            if ($RelativeForFilter -eq 'migration-manifest.json') {
                continue
            }
            if ($RelativeForFilter -eq 'extra-projects.json') {
                continue
            }
            if ($RelativeForFilter.StartsWith('ExtraProjects\', [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $Entry = New-CodexManifestFileEntry -RootPath $RootFull -FilePath $File.FullName
            if ($null -ne $Entry) {
                $Entries += $Entry
            }
            else {
                try {
                    $SkippedEntries += Get-RelativePath -BasePath $RootFull -Path $File.FullName
                }
                catch {
                    $SkippedEntries += $File.FullName
                }
            }
        }
    }

    [pscustomobject]@{
        Tool          = 'codex-migrate.ps1'
        Version       = '1.0.0'
        Mode          = $Mode
        ComputerName  = $ComputerName
        CreatedAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
        EntryCount    = @($Entries).Count
        SkippedCount  = @($SkippedEntries).Count
        SkippedEntries = @($SkippedEntries)
        Entries       = @($Entries)
    }
}

function Invoke-SafeCopy {
    param(
        [Parameter(Mandatory = $true)][string] $Source,
        [Parameter(Mandatory = $true)][string] $Destination,
        [ValidateSet('File', 'Directory')]
        [string] $Kind,
        [switch] $Preview,
        [switch] $UseDefaultExclusions
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        Write-CodexMigrationInfo "skip missing source: $Source"
        return
    }

    if ($Preview) {
        Write-CodexMigrationInfo "would copy $Kind '$Source' -> '$Destination'"
        return
    }

    if ($Kind -eq 'File') {
        $Parent = Split-Path -Parent $Destination
        Ensure-DirectoryExists -Path $Parent
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        return
    }

    $Robocopy = Get-Command robocopy.exe -ErrorAction SilentlyContinue
    if ($Robocopy) {
        $Arguments = @(
            $Source,
            $Destination,
            '/E',
            '/Z',
            '/MT:8',
            '/COPY:DAT',
            '/DCOPY:DAT',
            '/R:1',
            '/W:2',
            '/XJ',
            '/ETA'
        )

        if ($UseDefaultExclusions) {
            $ExcludedDirectories = @(Get-DefaultRobocopyExcludedDirectories)
            if ($ExcludedDirectories.Count -gt 0) {
                $Arguments += '/XD'
                $Arguments += $ExcludedDirectories
            }

            $ExcludedFiles = @(Get-DefaultRobocopyExcludedFiles)
            if ($ExcludedFiles.Count -gt 0) {
                $Arguments += '/XF'
                $Arguments += $ExcludedFiles
            }
        }

        & robocopy.exe @Arguments
        $ExitCode = $LASTEXITCODE
        if ($ExitCode -gt 7) {
            throw "robocopy failed with exit code $ExitCode while copying '$Source' to '$Destination'"
        }
        return
    }

    Ensure-DirectoryExists -Path $Destination
    Copy-Item -LiteralPath (Join-Path $Source '*') -Destination $Destination -Recurse -Force
}

function Assert-CodexNotRunning {
    param([switch] $Force)

    if ($Force) {
        return
    }

    $Processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessName -match 'codex'
        })

    if ($Processes.Count -gt 0) {
        $Names = ($Processes | Select-Object -ExpandProperty ProcessName -Unique) -join ', '
        throw "Codex-like processes appear to be running ($Names). Close Codex first, or rerun with -Force if you intentionally accept this risk."
    }
}

function Invoke-CodexMigrationExport {
    param(
        [Parameter(Mandatory = $true)][string] $PackagePath,
        [string] $UserProfileRoot = $env:USERPROFILE,
        [switch] $IncludeHeavyCaches,
        [switch] $Preview
    )

    $PackagePath = Normalize-MigrationPackagePath -Path $PackagePath
    $PackageFull = Get-NormalizedFullPath -Path $PackagePath
    $Plan = Get-CodexMigrationItemPlan -UserProfileRoot $UserProfileRoot -IncludeHeavyCaches:$IncludeHeavyCaches

    Write-CodexMigrationInfo "export package: $PackageFull"
    Write-CodexMigrationInfo "planned items: $(@($Plan).Count)"

    if (-not $Preview) {
        Ensure-DirectoryExists -Path $PackageFull
    }

    foreach ($Item in $Plan) {
        $Destination = Join-Path $PackageFull $Item.RelativePath
        Write-CodexMigrationInfo "copy $($Item.Kind): $($Item.RelativePath)"
        Invoke-SafeCopy `
            -Source $Item.Source `
            -Destination $Destination `
            -Kind $Item.Kind `
            -Preview:$Preview `
            -UseDefaultExclusions:(-not $IncludeHeavyCaches)
    }

    if ($Preview) {
        Write-CodexMigrationInfo 'preview complete; no files were written.'
        return
    }

    Write-CodexMigrationInfo 'building manifest; this can take a while for large packages.'
    $Manifest = New-CodexMigrationManifest -RootPath $PackageFull -Mode 'Export'
    $ManifestPath = Join-Path $PackageFull 'migration-manifest.json'
    $Manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
    Write-CodexMigrationInfo "manifest written: $ManifestPath"
    Write-CodexMigrationInfo "files recorded: $($Manifest.EntryCount)"
}

function Invoke-CodexMigrationImport {
    param(
        [Parameter(Mandatory = $true)][string] $PackagePath,
        [string] $UserProfileRoot = $env:USERPROFILE,
        [switch] $Preview
    )

    $PackagePath = Normalize-MigrationPackagePath -Path $PackagePath
    $PackageFull = Get-NormalizedFullPath -Path $PackagePath
    if (-not (Test-Path -LiteralPath $PackageFull)) {
        throw "Package path does not exist: $PackageFull"
    }

    $Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $BackupRoot = Join-Path $UserProfileRoot ".codex-migration-backups\$Timestamp"
    $PackageRoots = @('.codex', 'Documents\Codex') | Where-Object {
        Test-Path -LiteralPath (Join-Path $PackageFull $_)
    }

    Write-CodexMigrationInfo "import package: $PackageFull"
    Write-CodexMigrationInfo "backup root: $BackupRoot"

    foreach ($RelativeRoot in $PackageRoots) {
        $Source = Join-Path $PackageFull $RelativeRoot
        $Destination = Join-Path $UserProfileRoot $RelativeRoot
        $BackupDestination = Join-Path $BackupRoot $RelativeRoot

        if (Test-Path -LiteralPath $Destination) {
            Invoke-SafeCopy -Source $Destination -Destination $BackupDestination -Kind 'Directory' -Preview:$Preview
        }

        Invoke-SafeCopy -Source $Source -Destination $Destination -Kind 'Directory' -Preview:$Preview
    }

    Import-ExtraProjectFolders -PackagePath $PackageFull -Preview:$Preview

    if ($Preview) {
        Write-CodexMigrationInfo 'preview complete; no files were written.'
        return
    }

    Write-CodexMigrationInfo 'import complete.'
}

function Invoke-CodexMigrationVerify {
    param([Parameter(Mandatory = $true)][string] $PackagePath)

    $PackagePath = Normalize-MigrationPackagePath -Path $PackagePath
    $PackageFull = Get-NormalizedFullPath -Path $PackagePath
    $ManifestPath = Join-Path $PackageFull 'migration-manifest.json'

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "Manifest not found: $ManifestPath"
    }

    $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $Failures = New-Object System.Collections.Generic.List[string]

    foreach ($Entry in @($Manifest.Entries)) {
        $Path = Join-Path $PackageFull $Entry.RelativePath
        if (-not (Test-Path -LiteralPath $Path)) {
            $Failures.Add("missing: $($Entry.RelativePath)")
            continue
        }

        $Item = Get-Item -LiteralPath $Path
        if ($Item.Length -ne [int64]$Entry.Size) {
            $Failures.Add("size mismatch: $($Entry.RelativePath)")
            continue
        }

        $EntryForVerify = New-CodexManifestFileEntry -RootPath $PackageFull -FilePath $Path
        if ($null -eq $EntryForVerify) {
            $Failures.Add("unreadable: $($Entry.RelativePath)")
            continue
        }

        $Hash = $EntryForVerify.SHA256
        if ($Hash -ne $Entry.SHA256) {
            $Failures.Add("hash mismatch: $($Entry.RelativePath)")
        }
    }

    if ($Failures.Count -gt 0) {
        foreach ($Failure in $Failures) {
            Write-Warning $Failure
        }
        throw "Verification failed with $($Failures.Count) problem(s)."
    }

    Test-ExtraProjectPackageFolders -PackagePath $PackageFull
    Write-CodexMigrationInfo "verification passed for $($Manifest.EntryCount) manifest file(s)."
}

function Invoke-CodexMigrationCli {
    param(
        [ValidateSet('Export', 'Import', 'Verify')]
        [string] $Mode,
        [string] $PackagePath,
        [string] $UserProfileRoot = $env:USERPROFILE,
        [switch] $IncludeHeavyCaches,
        [switch] $Force,
        [switch] $Preview
    )

    if ([string]::IsNullOrWhiteSpace($Mode)) {
        throw 'Missing -Mode. Use Export, Import, or Verify.'
    }

    if ([string]::IsNullOrWhiteSpace($PackagePath)) {
        throw 'Missing -PackagePath.'
    }

    $PackagePath = Normalize-MigrationPackagePath -Path $PackagePath

    if ($Mode -in @('Export', 'Import')) {
        Assert-CodexNotRunning -Force:$Force
    }

    switch ($Mode) {
        'Export' {
            Invoke-CodexMigrationExport -PackagePath $PackagePath -UserProfileRoot $UserProfileRoot -IncludeHeavyCaches:$IncludeHeavyCaches -Preview:$Preview
        }
        'Import' {
            Invoke-CodexMigrationImport -PackagePath $PackagePath -UserProfileRoot $UserProfileRoot -Preview:$Preview
        }
        'Verify' {
            Invoke-CodexMigrationVerify -PackagePath $PackagePath
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-CodexMigrationCli `
        -Mode $Mode `
        -PackagePath $PackagePath `
        -UserProfileRoot $UserProfileRoot `
        -IncludeHeavyCaches:$IncludeHeavyCaches `
        -Force:$Force `
        -Preview:$WhatIfPreference
}
