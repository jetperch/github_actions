# SPDX-FileCopyrightText: Copyright 2026 Jetperch LLC
# SPDX-License-Identifier: Apache-2.0

# Sign Windows PE files with AzureSignTool.  See action.yml for the inputs,
# which arrive as WS_* environment variables.

$ErrorActionPreference = 'Stop'

function Set-SignedOutput([string] $value) {
    "signed=$value" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
}

if (-not $IsWindows) {
    throw 'windows_sign: requires a Windows runner'
}
if ([string]::IsNullOrEmpty($env:WS_KEY_VAULT_URI)) {
    Write-Host '::notice title=windows_sign::Skipped: azure_key_vault_uri is empty.'
    Set-SignedOutput 'false'
    exit 0
}
$required = @{
    WS_CLIENT_ID     = 'azure_client_id'
    WS_TENANT_ID     = 'azure_tenant_id'
    WS_CLIENT_SECRET = 'azure_client_secret'
    WS_CERT_NAME     = 'azure_cert_name'
}
foreach ($name in $required.Keys) {
    if ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))) {
        throw "windows_sign: input $($required[$name]) is required with azure_key_vault_uri"
    }
}
if ($env:WS_IF_NO_FILES_FOUND -notin @('error', 'warn', 'ignore')) {
    throw "windows_sign: invalid if_no_files_found '$env:WS_IF_NO_FILES_FOUND'"
}

$files = @()
foreach ($line in ($env:WS_FILES -split "`r?`n")) {
    $pattern = $line.Trim()
    if (-not $pattern) {
        continue
    }
    $idx = $pattern.IndexOf('**')
    if ($idx -ge 0) {
        # <dir>/**/<name>: recursive below <dir>.  <name> takes wildcards.
        $base = $pattern.Substring(0, $idx).TrimEnd('/', '\')
        $leaf = $pattern.Substring($idx + 2).TrimStart('/', '\')
        if ($leaf -match '[/\\]' -or $leaf.Contains('**')) {
            throw "windows_sign: '**' must be followed by a file name: '$pattern'"
        }
        if (-not $base) { $base = '.' }
        if (-not $leaf) { $leaf = '*' }
        $found = @(Get-ChildItem -Path $base -Recurse -File -Filter $leaf -ErrorAction SilentlyContinue)
    } else {
        $found = @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue)
    }
    if ($found.Count -eq 0) {
        $msg = "windows_sign: no files match '$pattern'"
        if ($env:WS_IF_NO_FILES_FOUND -eq 'error') {
            throw $msg
        } elseif ($env:WS_IF_NO_FILES_FOUND -eq 'warn') {
            Write-Host "::warning title=windows_sign::$msg"
        }
    }
    $files += $found.FullName
}
$files = @($files | Sort-Object -Unique)
if ($files.Count -eq 0) {
    Write-Host 'windows_sign: no files to sign'
    Set-SignedOutput 'false'
    exit 0
}

if (-not (Get-Command AzureSignTool -ErrorAction SilentlyContinue)) {
    $toolArgs = @('tool', 'install', '--global', 'AzureSignTool')
    if ($env:WS_TOOL_VERSION) {
        $toolArgs += @('--version', $env:WS_TOOL_VERSION)
    }
    & dotnet @toolArgs
    if ($LASTEXITCODE) {
        throw "windows_sign: AzureSignTool install failed ($LASTEXITCODE)"
    }
    $env:PATH = "$env:PATH;$env:USERPROFILE\.dotnet\tools"
}

# One call signs every file: a file list avoids command-line length limits
# and a Key Vault and timestamp round trip per file.  -mdop limits the
# concurrent Key Vault calls to avoid throttling.  -s skips signed files.
$list = New-TemporaryFile
try {
    Set-Content -Path $list -Value $files -Encoding utf8
    Write-Host "windows_sign: signing $($files.Count) file(s)"
    $files | ForEach-Object { Write-Host "  $_" }
    & AzureSignTool sign `
        -kvu $env:WS_KEY_VAULT_URI `
        -kvi $env:WS_CLIENT_ID `
        -kvt $env:WS_TENANT_ID `
        -kvs $env:WS_CLIENT_SECRET `
        -kvc $env:WS_CERT_NAME `
        -tr $env:WS_TIMESTAMP_URL `
        -td sha256 -fd sha256 -s -mdop 4 `
        -ifl $list.FullName
    if ($LASTEXITCODE) {
        throw "windows_sign: AzureSignTool failed ($LASTEXITCODE)"
    }
} finally {
    Remove-Item -Path $list -ErrorAction SilentlyContinue
}

$bad = @($files | Where-Object { (Get-AuthenticodeSignature $_).Status -ne 'Valid' })
if ($bad.Count) {
    $bad | ForEach-Object { Write-Host "::error title=windows_sign::not signed: $_" }
    throw "windows_sign: $($bad.Count) file(s) failed signature verification"
}
Write-Host "windows_sign: $($files.Count) file(s) signed and verified"
Set-SignedOutput 'true'
