# Configure and build the selected targets. CMake runs on every invocation so
# source relocation, generator changes and edited build modules are not hidden
# by an existing CMakeCache.txt.
param(
    [string]$Config = 'Release',
    [string[]]$Target = @('openssl-all'),
    [string]$Generator = 'Visual Studio 18 2026',
    [string]$Arch = 'x64',
    [switch]$Reconfigure
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$build = Join-Path $root 'build'
$cmake = (Get-Command cmake -ErrorAction SilentlyContinue).Source
$programFiles = [Environment]::GetFolderPath('ProgramFiles')
if (-not $cmake -and $programFiles) {
    $candidate = Join-Path $programFiles 'CMake\bin\cmake.exe'
    if (Test-Path -LiteralPath $candidate) { $cmake = $candidate }
}
if (-not $cmake) {
    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $vs = & $vswhere -latest -products * -property installationPath
        if ($vs) {
            $candidate = Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
            if (Test-Path -LiteralPath $candidate) { $cmake = $candidate }
        }
    }
}
if (-not $cmake) { throw 'cmake was not found on PATH or in standard install directories' }

if ($Reconfigure -and (Test-Path -LiteralPath $build)) {
    Remove-Item -LiteralPath $build -Recurse -Force
}

& $cmake -S $root -B $build -G $Generator -A $Arch
if ($LASTEXITCODE -ne 0) {
    throw 'cmake configure failed; after moving the source tree, rerun with -Reconfigure'
}

foreach ($t in $Target) {
    & $cmake --build $build --config $Config --target $t
    if ($LASTEXITCODE -ne 0) { throw "build failed for target $t" }
}

Write-Host ''
Write-Host "stage: $build\stage\$Config"
$argsFile = Join-Path $build "openssl\$Config\configure-args.txt"
if (Test-Path -LiteralPath $argsFile) {
    Write-Host 'configure args:'
    Get-Content -LiteralPath $argsFile
}
