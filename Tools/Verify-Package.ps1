param(
    [Parameter(Mandatory)][string]$ArchivePath,
    [Parameter(Mandatory)][string]$EnginePath,
    [Parameter(Mandatory)][string]$SharedToolsPath,
    [string]$GamePath,
    [ValidateSet('Steam', 'Windows', 'WindowsServer', 'Release')][string]$PackageType = 'Steam'
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
if ($GamePath -and $PackageType -ne 'Steam') { throw 'Installed verification is supported only for the Steam development package' }
$targets = if ($PackageType -eq 'Release') { @('Windows', 'WindowsServer') }
    elseif ($PackageType -eq 'WindowsServer') { @('WindowsServer') } else { @('Windows') }
$expectedFiles = @()
foreach ($target in $targets) {
    $prefix = if ($PackageType -eq 'Release') { "$target/" } else { '' }
    $containerName = "InstantVolumeReducerFactoryGame-$target"
    $targetFiles = @('InstantVolumeReducer.uplugin', 'Resources/Icon128.png', 'Resources/LICENSE')
    $binaries = if ($target -eq 'WindowsServer') { @('FactoryServer') }
        elseif ($PackageType -eq 'Steam') { @('FactoryGameSteam') } else { @('FactoryGameSteam', 'FactoryGameEGS') }
    foreach ($binary in $binaries) {
        $targetFiles += "Binaries/Win64/$binary-InstantVolumeReducer-Win64-Shipping.dll"
        $targetFiles += "Binaries/Win64/$binary-Win64-Shipping.modules"
    }
    foreach ($extension in @('pak', 'ucas', 'utoc')) { $targetFiles += "Content/Paks/$target/$containerName.$extension" }
    $expectedFiles += @($targetFiles | ForEach-Object { $prefix + $_ })
}
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
$contentPrefix = '../../../FactoryGame/Mods/InstantVolumeReducer/Content/'
$expectedCooked = @(
    "${contentPrefix}IVR_Config.uasset",
    "${contentPrefix}RootInstance_InstantVolumeReducer.uasset",
    "${contentPrefix}Input/IA_ToggleReducer.uasset",
    "${contentPrefix}Input/IMC_InstantVolumeReducer.uasset",
    '<ContainerHeader>'
)
$sourceDescriptor = Get-Content (Join-Path $PSScriptRoot '../InstantVolumeReducer.uplugin') -Raw | ConvertFrom-Json
$extractedFiles = @()
foreach ($target in $targets) {
    $targetRoot = if ($PackageType -eq 'Release') { Join-Path $reportPath $target } else { $reportPath }
    if ((Get-FileHash -LiteralPath (Join-Path $targetRoot 'Resources/LICENSE')).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot '../LICENSE')).Hash) { throw 'Packaged license differs from the repository license' }
    $descriptor = Get-Content (Join-Path $targetRoot 'InstantVolumeReducer.uplugin') -Raw | ConvertFrom-Json
    foreach ($field in @('Version', 'VersionName', 'SemVersion', 'GameVersion')) {
        if ($descriptor.$field -ne $sourceDescriptor.$field) { throw "Packaged descriptor mismatch: $field" }
    }
    if (($descriptor.Plugins | ConvertTo-Json -Depth 5 -Compress) -ne ($sourceDescriptor.Plugins | ConvertTo-Json -Depth 5 -Compress)) {
        throw 'Packaged plugin dependencies differ from source'
    }
    $containerName = "InstantVolumeReducerFactoryGame-$target"
    $pakPath = Join-Path $targetRoot "Content/Paks/$target/$containerName.pak"
    $utocPath = Join-Path $targetRoot "Content/Paks/$target/$containerName.utoc"
    $content = & $containerInspector -PakPath $pakPath -UtocPath $utocPath -EnginePath $EnginePath -ReportPath (Join-Path $reportPath "$target-inspection")
    if (Compare-Object @('AssetRegistry.bin', 'Config/PluginSettings.ini') $content.PakFiles) { throw 'Unexpected or missing files inside the pak container' }
    if (Compare-Object $expectedCooked $content.CookedFiles) { throw 'Unexpected or missing cooked content; review runtime dependencies before updating the expected list' }
    $extractedFiles += $content.ExtractedFiles
}
$packageFiles = @($files | ForEach-Object { Join-Path $reportPath $_ })
& $privacyChecker -Files ($packageFiles + $extractedFiles)
if ($GamePath) {
    $installedRoot = Join-Path $GamePath 'FactoryGame\Mods\InstantVolumeReducer'
    & $python $installedVerifier $ArchivePath $installedRoot --report (Join-Path $reportPath 'installed-hashes.json')
    if ($LASTEXITCODE -ne 0) { throw 'Installed-package verification failed' }
}
Write-Output "Package verified: runtime-only files and cooked content; privacy checks passed. Reports: $reportPath"
