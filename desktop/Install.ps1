$ErrorActionPreference = 'Stop'
$rhDestination = Join-Path $env:LOCALAPPDATA 'Programs\RHPrime'
if (Get-Process -Name RHPrime -ErrorAction SilentlyContinue) {
    throw 'Feche o RH PRIME antes de instalar ou atualizar.'
}
if (!(Test-Path (Join-Path $PSScriptRoot 'RHPrime.exe'))) {
    throw 'Extraia todo o ZIP antes de executar o instalador.'
}
New-Item -ItemType Directory -Force -Path $rhDestination | Out-Null
if ([IO.Path]::GetFullPath($PSScriptRoot) -ne [IO.Path]::GetFullPath($rhDestination)) {
    Copy-Item -Path (Join-Path $PSScriptRoot '*') -Destination $rhDestination -Recurse -Force
}
$rhShell = New-Object -ComObject WScript.Shell
$rhShortcut = $rhShell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'RH PRIME.lnk'))
$rhShortcut.TargetPath = Join-Path $rhDestination 'RHPrime.exe'
$rhShortcut.WorkingDirectory = $rhDestination
$rhShortcut.Save()
Write-Host 'Previa instalada. Abra RH PRIME pelo atalho na area de trabalho.'
Write-Host 'Documentos e credenciais existentes foram preservados.'
