param(
    [Parameter(Mandatory)][string]$ArchivePath,
    [Parameter(Mandatory)][string]$EnginePath,
    [Parameter(Mandatory)][string]$SharedToolsPath,
    [string]$GamePath
)
$ErrorActionPreference = 'Stop'
$privacyChecker = Join-Path $SharedToolsPath 'Test-Privacy.ps1'
$archiveInspector = Join-Path $SharedToolsPath 'release_archive.py'
$containerInspector = Join-Path $SharedToolsPath 'Inspect-CookedContent.ps1'
$installedVerifier = Join-Path $SharedToolsPath 'installed_package.py'
foreach ($tool in @($privacyChecker, $archiveInspector, $containerInspector, $installedVerifier)) {
    if (!(Test-Path -LiteralPath $tool -PathType Leaf)) { throw 'Shared verification tools are missing' }
}
$ArchivePath = (Resolve-Path -LiteralPath $ArchivePath).Path
Add-Type -AssemblyName System.IO.Compression.FileSystem
$containerName = 'InstantVolumeReducerFactoryGame-Windows'
$expectedFiles = @(
    'InstantVolumeReducer.uplugin',
    'Resources/Icon128.png',
    'Binaries/Win64/FactoryGameSteam-InstantVolumeReducer-Win64-Shipping.dll',
    'Binaries/Win64/FactoryGameSteam-Win64-Shipping.modules',
    "Content/Paks/Windows/$containerName.pak",
    "Content/Paks/Windows/$containerName.ucas",
    "Content/Paks/Windows/$containerName.utoc"
)
$python = Join-Path $EnginePath 'Engine\Binaries\ThirdParty\Python3\Win64\python.exe'
$inspection = & $python $archiveInspector $ArchivePath
if ($LASTEXITCODE -ne 0) { throw 'Shared archive inspection failed' }
$files = @($inspection | ConvertFrom-Json | ForEach-Object { $_.Replace('\', '/') })
$differences = Compare-Object $expectedFiles $files
if ($differences) { throw "Unexpected or missing archive entries: $($differences | Out-String)" }
$reportPath = Join-Path $PSScriptRoot ("..\Saved\PackageAudit\" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $reportPath -Force | Out-Null
$reportPath = (Resolve-Path -LiteralPath $reportPath).Path
[System.IO.Compression.ZipFile]::ExtractToDirectory($ArchivePath, $reportPath)
$files | Set-Content -LiteralPath (Join-Path $reportPath 'archive-files.txt')
$pakPath = Join-Path $reportPath "Content\Paks\Windows\$containerName.pak"
$utocPath = Join-Path $reportPath "Content\Paks\Windows\$containerName.utoc"
$content = & $containerInspector -PakPath $pakPath -UtocPath $utocPath -EnginePath $EnginePath -ReportPath $reportPath
if (Compare-Object @('AssetRegistry.bin', 'Config/PluginSettings.ini') $content.PakFiles) {
    throw 'Unexpected or missing files inside the pak container'
}
$contentPrefix = '../../../FactoryGame/Mods/InstantVolumeReducer/Content/'
$expectedCooked = @(
    "${contentPrefix}IVR_Config.uasset",
    "${contentPrefix}RootInstance_InstantVolumeReducer.uasset",
    "${contentPrefix}Input/IA_ToggleReducer.uasset",
    "${contentPrefix}Input/IMC_InstantVolumeReducer.uasset",
    '<ContainerHeader>'
)
if (Compare-Object $expectedCooked $content.CookedFiles) {
    throw 'Unexpected or missing cooked content; review runtime dependencies before updating the expected list'
}
$packageFiles = @($files | ForEach-Object { Join-Path $reportPath $_ })
& $privacyChecker -Files ($packageFiles + $content.ExtractedFiles)
if ($GamePath) {
    $installedRoot = Join-Path $GamePath 'FactoryGame\Mods\InstantVolumeReducer'
    & $python $installedVerifier $ArchivePath $installedRoot --report (Join-Path $reportPath 'installed-hashes.json')
    if ($LASTEXITCODE -ne 0) { throw 'Installed-package verification failed' }
}
Write-Output "Package verified: runtime-only files and cooked content; privacy checks passed. Reports: $reportPath"
