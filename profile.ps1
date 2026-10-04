# PSReadLine must be loaded before PSFzf (PSFzf README).
if (-not (Get-Module -Name PSReadLine)) {
    Import-Module PSReadLine
}
Import-Module PSFzf

# PSFzf UI Customization (Boxed and Modern Look)
$env:FZF_DEFAULT_OPTS = "--height 40% --layout=reverse --border --margin=1 --padding=1 --info=inline --preview-window='right:60%' --color='hl:148,hl+:154,pointer:032,marker:010,bg+:237,gutter:008,border:057,header:037,label:065,query:158' --prompt='> ' --pointer='▶' --marker='✓'"

# Ctrl+t file preview with bat; Ctrl+/ cycles the preview window (fzf README example)
$env:FZF_CTRL_T_OPTS = "--preview 'bat -n --color=always {}' --bind 'ctrl-/:change-preview-window(down|hidden|)'"

# Key handlers live in Set-PredictionSource_Override below: CTT's
# Initialize-PSReadLine sets EditMode, which resets every key handler,
# and only then calls that override.

# --- 1. CORE UTILITIES ---
# Use CTT's built-in 'Invoke-Profile' to reload if available (regular pwsh), else reload manually
function Import-Profile {
    if (Get-Command Invoke-Profile -ErrorAction SilentlyContinue) {
        Invoke-Profile
    } else {
        . $PROFILE.CurrentUserAllHosts
        . $PROFILE.CurrentUserCurrentHost
    }
}
Set-Alias -Name Reload-Profile -Value Import-Profile

# --- 2. DEVELOPER OPTIMIZATIONS (JS/TS, Python, Git) ---
function Remove-NodeModulesDirectory {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $dir = Get-ChildItem -Path . -Filter "node_modules" -Recurse -Directory -ErrorAction SilentlyContinue |
           Select-Object -ExpandProperty FullName |
           fzf --prompt="Clean node_modules > " --header="Select to REMOVE"
    if ($dir -and $PSCmdlet.ShouldProcess($dir, 'Remove directory')) {
        Write-Information -MessageData "Removing $dir..." -InformationAction Continue
        Remove-Item -Path $dir -Recurse -Force
    }
}

# Python/VirtualEnv Auto-Activation (very useful for devs)
function venv {
    if (Test-Path ".\venv\Scripts\Activate.ps1") { . .\venv\Scripts\Activate.ps1 }
    elseif (Test-Path ".\.venv\Scripts\Activate.ps1") { . .\.venv\Scripts\Activate.ps1 }
    else { Write-Warning "No virtualenv (venv or .venv) found in current directory." }
}

# Shortcut for common dev tasks
function nr { npm run $args }
function py { python $args }

# --- 3. POWER USER GIT & UI ---
Import-Module posh-git -ErrorAction SilentlyContinue

# Smart Git Checkout (Fuzzy Search) - Type 'gco' to select branch
function gco {
    $branches = git branch -a | ForEach-Object { $_.Trim().TrimStart("*").Trim() }
    if ($null -eq $branches) { return }
    $branch = $branches | fzf --height 40% --header "Check out branch" --border --layout=reverse --info=inline
    if ($branch) {
        if ($branch -match "^remotes/") {
            $local = $branch -replace "^remotes/[^/]+/", ""
            git checkout -b $local $branch
        } else {
            git checkout $branch
        }
    }
}

# Fuzzy Process Killer (Type 'kp' to kill a process)
function kp {
    $proc = Get-Process | fzf --header "Kill Process" --border --layout=reverse --info=inline --preview 'Get-Process -Id {1} | Select-Object *'
    if ($proc) {
        $id = ($proc -split "\s+")[0]
        Stop-Process -Id $id -Confirm
    }
}

# Fuzzy File Opener (Type 'fo' to open a file in VS Code)
function fo {
    $file = fzf --header "Open File in VS Code" --border --layout=reverse --info=inline --preview 'cat {}'
    if ($file) {
        code $file
    }
}

# Fuzzy Docker Manager (if docker exists)
function dps {
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        $container = docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}" |
            fzf --header "Select Container" --header-lines 1 --border --layout=reverse
        if ($container) {
            $id = ($container -split "\s+")[0]
            $action = "Stop", "Start", "Restart", "Remove", "Logs", "Shell" | fzf --header "Action for $id"
            switch ($action) {
                "Stop"    { docker stop $id }
                "Start"   { docker start $id }
                "Restart" { docker restart $id }
                "Remove"  { docker rm -f $id }
                "Logs"    { docker logs -f $id }
                "Shell"   { docker exec -it $id sh }
            }
        }
    } else {
        Write-Warning "Docker not found in PATH"
    }
}

# Alias mapping
Set-Alias -Name kll -Value kp
Set-Alias -Name v -Value fo

# --- 4. CTT OVERRIDES & FIXES ---
# CTT's Update-PowerShell forwards its own -WhatIf/-Confirm here via @PSBoundParameters
function Update-PowerShell_Override {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ($PSCmdlet.ShouldProcess('Microsoft.PowerShell', 'winget upgrade')) {
        Write-Information -MessageData "Checking for PowerShell updates via winget..." -InformationAction Continue
        # Using --force to bypass the "different install technology" conflict
        winget upgrade --id Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements --force
    }
}

function Set-PredictionSource_Override {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Name is fixed by the CTT override contract; it only changes PSReadLine state of the current session.')]
    param()

    # PSFzf's documented way to bind its handlers: Ctrl+t files, Ctrl+r history,
    # Alt+c cd into a directory, Alt+a pick an argument from history
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' `
                    -PSReadlineChordReverseHistory 'Ctrl+r' `
                    -PSReadlineChordSetLocation 'Alt+c' `
                    -PSReadlineChordReverseHistoryArgs 'Alt+a'

    # Force Tab to use FZF instead of CTT's MenuComplete
    Set-PSReadLineKeyHandler -Key Tab -ScriptBlock { Invoke-FzfTabCompletion }

    if ($PSVersionTable.PSEdition -eq "Core") {
        # Improved prediction settings
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin
        Set-PSReadLineOption -MaximumHistoryCount 10000
    } else {
        # Desktop version - use History only
        Set-PSReadLineOption -MaximumHistoryCount 10000
    }
}

# --- Minimalisque workspace identity (switches GitHub/npm/Node env inside D:\Work\Minimalisque) ---
$minimalisqueEnv = Join-Path $HOME '.config\minimalisque\shell\minimalisque-env.ps1'
if (Test-Path -LiteralPath $minimalisqueEnv) { . $minimalisqueEnv }
Remove-Variable minimalisqueEnv
