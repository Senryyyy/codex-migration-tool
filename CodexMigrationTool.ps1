$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$Script:ToolDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:EnginePath = Join-Path $Script:ToolDirectory 'codex-migrate.ps1'

if (-not (Test-Path -LiteralPath $Script:EnginePath)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Missing migration engine:`r`n$Script:EnginePath",
        'Codex Migration Tool',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

. $Script:EnginePath

function Add-LogLine {
    param([string] $Message)
    $Timestamp = Get-Date -Format 'HH:mm:ss'
    $Script:LogTextBox.AppendText("[$Timestamp] $Message`r`n")
    $Script:LogTextBox.SelectionStart = $Script:LogTextBox.TextLength
    $Script:LogTextBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Show-ErrorMessage {
    param([string] $Message)
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        'Codex Migration Tool',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function Show-InfoMessage {
    param([string] $Message)
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        'Codex Migration Tool',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Get-PackagePathFromUi {
    $Path = $Script:PackageTextBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Choose a migration package folder first.'
    }
    $Path = Normalize-MigrationPackagePath -Path $Path
    $Script:PackageTextBox.Text = $Path
    return $Path
}

function Assert-PackagePathReachable {
    param([Parameter(Mandatory = $true)][string] $Path)

    if ($Path.StartsWith('\\') -and (-not (Test-Path -LiteralPath $Path))) {
        throw "The network package folder is not reachable: $Path. Open it once in File Explorer, then paste the same path here."
    }
}

function Read-NetworkPathFromUser {
    param([string] $InitialPath = '\\NEWPC\CodexImport')

    $PromptForm = New-Object System.Windows.Forms.Form
    $PromptForm.Text = 'Network package path'
    $PromptForm.StartPosition = 'CenterParent'
    $PromptForm.Size = New-Object System.Drawing.Size(560, 190)
    $PromptForm.FormBorderStyle = 'FixedDialog'
    $PromptForm.MaximizeBox = $false
    $PromptForm.MinimizeBox = $false

    $PromptLabel = New-Object System.Windows.Forms.Label
    $PromptLabel.Text = 'Type or paste the shared folder path, for example \\NEWPC\CodexImport'
    $PromptLabel.AutoSize = $false
    $PromptLabel.Size = New-Object System.Drawing.Size(500, 42)
    $PromptLabel.Location = New-Object System.Drawing.Point(18, 18)
    $PromptForm.Controls.Add($PromptLabel)

    $PromptTextBox = New-Object System.Windows.Forms.TextBox
    $PromptTextBox.Location = New-Object System.Drawing.Point(20, 68)
    $PromptTextBox.Size = New-Object System.Drawing.Size(500, 28)
    $PromptTextBox.Text = $InitialPath
    $PromptForm.Controls.Add($PromptTextBox)

    $OkButton = New-Object System.Windows.Forms.Button
    $OkButton.Text = 'OK'
    $OkButton.Location = New-Object System.Drawing.Point(350, 110)
    $OkButton.Size = New-Object System.Drawing.Size(80, 30)
    $OkButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $PromptForm.Controls.Add($OkButton)

    $CancelButton = New-Object System.Windows.Forms.Button
    $CancelButton.Text = 'Cancel'
    $CancelButton.Location = New-Object System.Drawing.Point(440, 110)
    $CancelButton.Size = New-Object System.Drawing.Size(80, 30)
    $CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $PromptForm.Controls.Add($CancelButton)

    $PromptForm.AcceptButton = $OkButton
    $PromptForm.CancelButton = $CancelButton

    $Result = $PromptForm.ShowDialog($Script:Form)
    if ($Result -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }

    $Value = $PromptTextBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    return $Value
}

function Copy-ToolFilesToPackage {
    param([Parameter(Mandatory = $true)][string] $PackagePath)

    $Files = @(
        'CodexMigrationTool.cmd',
        'CodexMigrationTool.ps1',
        'codex-migrate.ps1'
    )

    Ensure-DirectoryExists -Path $PackagePath

    foreach ($File in $Files) {
        $Source = Join-Path $Script:ToolDirectory $File
        if (Test-Path -LiteralPath $Source) {
            Copy-Item -LiteralPath $Source -Destination (Join-Path $PackagePath $File) -Force
        }
    }
}

function Invoke-GuiOperation {
    param(
        [string] $Name,
        [scriptblock] $Operation
    )

    try {
        $Script:ExportButton.Enabled = $false
        $Script:VerifyButton.Enabled = $false
        $Script:ImportButton.Enabled = $false
        $Script:BrowseButton.Enabled = $false
        $Script:OpenButton.Enabled = $false
        $Script:NetworkButton.Enabled = $false
        $Script:AddProjectButton.Enabled = $false
        $Script:RemoveProjectButton.Enabled = $false

        Add-LogLine "$Name started."
        & $Operation
        Add-LogLine "$Name finished."
        Show-InfoMessage "$Name finished."
    }
    catch {
        $Message = $_.Exception.Message
        Add-LogLine "$Name failed: $Message"
        if ($_.ScriptStackTrace) {
            Add-LogLine $_.ScriptStackTrace
        }
        Show-ErrorMessage $Message
    }
    finally {
        $Script:ExportButton.Enabled = $true
        $Script:VerifyButton.Enabled = $true
        $Script:ImportButton.Enabled = $true
        $Script:BrowseButton.Enabled = $true
        $Script:OpenButton.Enabled = $true
        $Script:NetworkButton.Enabled = $true
        $Script:AddProjectButton.Enabled = $true
        $Script:RemoveProjectButton.Enabled = $true
    }
}

$Script:Form = New-Object System.Windows.Forms.Form
$Script:Form.Text = 'Codex Migration Tool'
$Script:Form.StartPosition = 'CenterScreen'
$Script:Form.Size = New-Object System.Drawing.Size(760, 700)
$Script:Form.MinimumSize = New-Object System.Drawing.Size(720, 660)
$Script:Form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$TitleLabel = New-Object System.Windows.Forms.Label
$TitleLabel.Text = 'Codex Migration Tool'
$TitleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$TitleLabel.AutoSize = $true
$TitleLabel.Location = New-Object System.Drawing.Point(18, 16)
$Script:Form.Controls.Add($TitleLabel)

$HelpLabel = New-Object System.Windows.Forms.Label
$HelpLabel.Text = 'Step 1 on old PC: choose the shared package folder and export. Step 2 on new PC: verify, then import.'
$HelpLabel.AutoSize = $false
$HelpLabel.Size = New-Object System.Drawing.Size(700, 42)
$HelpLabel.Location = New-Object System.Drawing.Point(20, 54)
$Script:Form.Controls.Add($HelpLabel)

$PackageLabel = New-Object System.Windows.Forms.Label
$PackageLabel.Text = 'Migration package folder'
$PackageLabel.AutoSize = $true
$PackageLabel.Location = New-Object System.Drawing.Point(20, 108)
$Script:Form.Controls.Add($PackageLabel)

$Script:PackageTextBox = New-Object System.Windows.Forms.TextBox
$Script:PackageTextBox.Location = New-Object System.Drawing.Point(20, 132)
$Script:PackageTextBox.Size = New-Object System.Drawing.Size(450, 28)
$DefaultPackage = 'C:\CodexImport'
if (-not (Test-Path -LiteralPath $DefaultPackage)) {
    $DefaultPackage = Join-Path ([Environment]::GetFolderPath('Desktop')) 'CodexImport'
}
$Script:PackageTextBox.Text = $DefaultPackage
$Script:Form.Controls.Add($Script:PackageTextBox)

$Script:BrowseButton = New-Object System.Windows.Forms.Button
$Script:BrowseButton.Text = 'Browse'
$Script:BrowseButton.Location = New-Object System.Drawing.Point(480, 130)
$Script:BrowseButton.Size = New-Object System.Drawing.Size(70, 32)
$Script:BrowseButton.Add_Click({
        $Dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $Dialog.Description = 'Choose migration package folder'
        $Dialog.SelectedPath = $Script:PackageTextBox.Text
        if ($Dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $Script:PackageTextBox.Text = $Dialog.SelectedPath
        }
    })
$Script:Form.Controls.Add($Script:BrowseButton)

$Script:NetworkButton = New-Object System.Windows.Forms.Button
$Script:NetworkButton.Text = 'Network'
$Script:NetworkButton.Location = New-Object System.Drawing.Point(556, 130)
$Script:NetworkButton.Size = New-Object System.Drawing.Size(104, 32)
$Script:NetworkButton.Add_Click({
        $Initial = $Script:PackageTextBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($Initial) -or (-not $Initial.StartsWith('\\'))) {
            $Initial = '\\NEWPC\CodexImport'
        }
        $Value = Read-NetworkPathFromUser -InitialPath $Initial
        if ($null -ne $Value) {
            $Script:PackageTextBox.Text = $Value
        }
    })
$Script:Form.Controls.Add($Script:NetworkButton)

$Script:OpenButton = New-Object System.Windows.Forms.Button
$Script:OpenButton.Text = 'Open'
$Script:OpenButton.Location = New-Object System.Drawing.Point(666, 130)
$Script:OpenButton.Size = New-Object System.Drawing.Size(58, 32)
$Script:OpenButton.Add_Click({
        try {
            $Path = Get-PackagePathFromUi
            if (-not (Test-Path -LiteralPath $Path)) {
                Ensure-DirectoryExists -Path $Path
            }
            Start-Process explorer.exe -ArgumentList "`"$Path`""
        }
        catch {
            Show-ErrorMessage $_.Exception.Message
        }
    })
$Script:Form.Controls.Add($Script:OpenButton)

$Script:IncludeHeavyCachesCheckBox = New-Object System.Windows.Forms.CheckBox
$Script:IncludeHeavyCachesCheckBox.Text = 'Include heavy caches'
$Script:IncludeHeavyCachesCheckBox.AutoSize = $true
$Script:IncludeHeavyCachesCheckBox.Location = New-Object System.Drawing.Point(20, 176)
$Script:Form.Controls.Add($Script:IncludeHeavyCachesCheckBox)

$Script:ForceCheckBox = New-Object System.Windows.Forms.CheckBox
$Script:ForceCheckBox.Text = 'Continue even if Codex is detected running'
$Script:ForceCheckBox.AutoSize = $true
$Script:ForceCheckBox.Location = New-Object System.Drawing.Point(210, 176)
$Script:Form.Controls.Add($Script:ForceCheckBox)

$ProjectLabel = New-Object System.Windows.Forms.Label
$ProjectLabel.Text = 'Extra project folders to restore to the same paths'
$ProjectLabel.AutoSize = $true
$ProjectLabel.Location = New-Object System.Drawing.Point(20, 214)
$Script:Form.Controls.Add($ProjectLabel)

$Script:ProjectListBox = New-Object System.Windows.Forms.ListBox
$Script:ProjectListBox.Location = New-Object System.Drawing.Point(20, 238)
$Script:ProjectListBox.Size = New-Object System.Drawing.Size(560, 78)
$Script:ProjectListBox.HorizontalScrollbar = $true
$Script:Form.Controls.Add($Script:ProjectListBox)

$Script:AddProjectButton = New-Object System.Windows.Forms.Button
$Script:AddProjectButton.Text = 'Add Project Folder'
$Script:AddProjectButton.Location = New-Object System.Drawing.Point(590, 238)
$Script:AddProjectButton.Size = New-Object System.Drawing.Size(134, 32)
$Script:AddProjectButton.Add_Click({
        $Dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $Dialog.Description = 'Choose an extra project folder to migrate'
        if ($Dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $SelectedPath = (Resolve-Path -LiteralPath $Dialog.SelectedPath).Path
            $Exists = $false
            foreach ($Item in $Script:ProjectListBox.Items) {
                if ([string]::Equals([string]$Item, $SelectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $Exists = $true
                    break
                }
            }
            if (-not $Exists) {
                [void] $Script:ProjectListBox.Items.Add($SelectedPath)
            }
        }
    })
$Script:Form.Controls.Add($Script:AddProjectButton)

$Script:RemoveProjectButton = New-Object System.Windows.Forms.Button
$Script:RemoveProjectButton.Text = 'Remove Selected'
$Script:RemoveProjectButton.Location = New-Object System.Drawing.Point(590, 278)
$Script:RemoveProjectButton.Size = New-Object System.Drawing.Size(134, 32)
$Script:RemoveProjectButton.Add_Click({
        while ($Script:ProjectListBox.SelectedItems.Count -gt 0) {
            $Script:ProjectListBox.Items.Remove($Script:ProjectListBox.SelectedItems[0])
        }
    })
$Script:Form.Controls.Add($Script:RemoveProjectButton)

$Script:ExportButton = New-Object System.Windows.Forms.Button
$Script:ExportButton.Text = 'Old PC: Export package'
$Script:ExportButton.Location = New-Object System.Drawing.Point(20, 336)
$Script:ExportButton.Size = New-Object System.Drawing.Size(220, 44)
$Script:ExportButton.Add_Click({
        Invoke-GuiOperation -Name 'Export' -Operation {
            $Path = Get-PackagePathFromUi
            Assert-PackagePathReachable -Path $Path
            Assert-CodexNotRunning -Force:$Script:ForceCheckBox.Checked
            $ExtraProjectPaths = @($Script:ProjectListBox.Items | ForEach-Object { [string]$_ })
            Invoke-CodexMigrationExport `
                -PackagePath $Path `
                -UserProfileRoot $env:USERPROFILE `
                -IncludeHeavyCaches:$Script:IncludeHeavyCachesCheckBox.Checked
            if ($ExtraProjectPaths.Count -gt 0) {
                Export-ExtraProjectFolders -ProjectPaths $ExtraProjectPaths -PackagePath $Path
            }
            Copy-ToolFilesToPackage -PackagePath $Path
            Add-LogLine 'Tool files copied into the package folder.'
        }
    })
$Script:Form.Controls.Add($Script:ExportButton)

$Script:VerifyButton = New-Object System.Windows.Forms.Button
$Script:VerifyButton.Text = 'New PC: Verify package'
$Script:VerifyButton.Location = New-Object System.Drawing.Point(260, 336)
$Script:VerifyButton.Size = New-Object System.Drawing.Size(220, 44)
$Script:VerifyButton.Add_Click({
        Invoke-GuiOperation -Name 'Verify' -Operation {
            $Path = Get-PackagePathFromUi
            Invoke-CodexMigrationVerify -PackagePath $Path
        }
    })
$Script:Form.Controls.Add($Script:VerifyButton)

$Script:ImportButton = New-Object System.Windows.Forms.Button
$Script:ImportButton.Text = 'New PC: Import package'
$Script:ImportButton.Location = New-Object System.Drawing.Point(500, 336)
$Script:ImportButton.Size = New-Object System.Drawing.Size(220, 44)
$Script:ImportButton.Add_Click({
        Invoke-GuiOperation -Name 'Import' -Operation {
            $Path = Get-PackagePathFromUi
            Assert-CodexNotRunning -Force:$Script:ForceCheckBox.Checked
            Add-LogLine 'Import will also restore ExtraProjects via Import-ExtraProjectFolders when extra-projects.json exists.'
            Invoke-CodexMigrationImport -PackagePath $Path -UserProfileRoot $env:USERPROFILE
        }
    })
$Script:Form.Controls.Add($Script:ImportButton)

$LogLabel = New-Object System.Windows.Forms.Label
$LogLabel.Text = 'Status'
$LogLabel.AutoSize = $true
$LogLabel.Location = New-Object System.Drawing.Point(20, 404)
$Script:Form.Controls.Add($LogLabel)

$Script:LogTextBox = New-Object System.Windows.Forms.TextBox
$Script:LogTextBox.Multiline = $true
$Script:LogTextBox.ScrollBars = 'Vertical'
$Script:LogTextBox.ReadOnly = $true
$Script:LogTextBox.Location = New-Object System.Drawing.Point(20, 428)
$Script:LogTextBox.Size = New-Object System.Drawing.Size(704, 200)
$Script:LogTextBox.Anchor = 'Top,Bottom,Left,Right'
$Script:Form.Controls.Add($Script:LogTextBox)

Add-LogLine 'Ready. Close Codex before exporting or importing.'
Add-LogLine 'Old PC package can be a network share such as \\NEWPC\CodexImport.'
Add-LogLine 'During large copies, watch the black terminal window for robocopy progress.'

[void] $Script:Form.ShowDialog()
