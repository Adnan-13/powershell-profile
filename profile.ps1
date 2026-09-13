Import-Module PSFzf
if (-not (Get-Module -Name PSReadLine)) {
    Import-Module PSReadLine
}

# PSFzf Key Handlers (Mandatory override for Ctrl+r)
Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -ScriptBlock { Invoke-FzfPsReadlineHandlerHistory }
Set-PSReadLineKeyHandler -Chord 'Ctrl+t' -ScriptBlock { Invoke-FzfPsReadlineHandlerProvider }

# PSFzf UI Customization (Boxed and Modern Look)
$env:FZF_DEFAULT_OPTS = "--height 40% --layout=reverse --border --margin=1 --padding=1 --info=inline --preview-window='right:60%' --color='hl:148,hl+:154,pointer:032,marker:010,bg+:237,gutter:008,border:057,header:037,label:065,query:158' --prompt='> ' --pointer='▶' --marker='✓'"

# Force Tab to use FZF for every completion
Set-PSReadLineKeyHandler -Key Tab -ScriptBlock { Invoke-FzfTabCompletion }

# --- 1. CORE UTILITIES ---
# Use CTT's built-in 'Invoke-Profile' to reload if available (regular pwsh), else reload manually
function Reload-Profile {
    if (Get-Command Invoke-Profile -ErrorAction SilentlyContinue) {
        Invoke-Profile
    } else {
        . $PROFILE.CurrentUserAllHosts
        . $PROFILE.CurrentUserCurrentHost
    }
}

# --- 2. DEVELOPER OPTIMIZATIONS (JS/TS, Python, Git) ---
function Invoke-FzfNodeModules {
    $dir = Get-ChildItem -Path . -Filter "node_modules" -Recurse -Directory -ErrorAction SilentlyContinue | 
           Select-Object -ExpandProperty FullName | 
           fzf --prompt="Clean node_modules > " --header="Select to REMOVE"
    if ($dir) {
        Write-Host "Removing $dir..." -ForegroundColor Yellow
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
function ni { npm install $args }
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
        Write-Host "Docker not found in PATH" -ForegroundColor Yellow
    }
}

# Alias mapping
Set-Alias -Name kll -Value kp
Set-Alias -Name v -Value fo

# --- 4. CTT OVERRIDES & FIXES ---
function Update-PowerShell_Override {
    Write-Host "Manually checking for PowerShell updates via winget..." -ForegroundColor Cyan
    # Using --force to bypass the "different install technology" conflict
    winget upgrade --id Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements --force
}

function Set-PredictionSource_Override {
    # Custom key handlers for PSFzf
    Set-PSReadLineKeyHandler -Chord 'Ctrl+r' `
                             -BriefDescription 'Fzf Reverse History Select' `
                             -Description 'Run fzf to search through PSReadline history' `
                             -ScriptBlock { Invoke-FzfPsReadlineHandlerHistory }

    Set-PSReadLineKeyHandler -Chord 'Ctrl+t' `
                             -BriefDescription 'Fzf Provider Select' `
                             -Description 'Run fzf for current provider based on current token' `
                             -ScriptBlock { Invoke-FzfPsReadlineHandlerProvider }

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
