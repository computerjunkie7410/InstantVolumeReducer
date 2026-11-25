param(
    [string]$EnginePath = $env:SATISFACTORY_ENGINE_PATH,
    [string]$GamePath = $env:SATISFACTORY_GAME_PATH,
    [string]$SharedToolsPath = $env:SATISFACTORY_SHARED_TOOLS
)
$ErrorActionPreference = 'Stop'
if (!$SharedToolsPath) {
    $projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $SharedToolsPath = Join-Path $projectRoot '.mod-development\Tools'
}
$builder = Join-Path $SharedToolsPath 'Build-Mod.ps1'
if (!(Test-Path -LiteralPath $builder -PathType Leaf)) { throw 'Shared build tools are missing; provide -SharedToolsPath' }
& $builder -ModPath (Join-Path $PSScriptRoot '..') -PackageVerifier (Join-Path $PSScriptRoot 'Verify-Package.ps1') -EnginePath $EnginePath -GamePath $GamePath -PakRulesPath (Join-Path $PSScriptRoot 'PackageRules.ini')
