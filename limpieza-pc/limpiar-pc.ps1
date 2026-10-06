# limpiar-pc.ps1 - Libera espacio en C: borrando SOLO caches, temporales y restos de Windows.
#
# NO toca:
#   - Documentos, Escritorio, Imagenes, Videos, Musica, Descargas ni OneDrive
#   - Ninguna carpeta cuyo nombre tenga que ver con motos, bikes o autos
#   - Ningun programa instalado (Chrome, Spotify, Word, CapCut, etc. siguen igual,
#     con tus sesiones y contrasenas; solo se vacia su cache, que se regenera solo)
#
# Antes de borrar te muestra cuanto ocupa cada cosa y te pide confirmacion.

param([switch]$SinPreguntar)

# --- Pedir permisos de administrador (necesarios para limpiar Windows) ---
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$ErrorActionPreference = 'SilentlyContinue'
$L = $env:LOCALAPPDATA
$R = $env:APPDATA

# --- Protecciones ---
$rutasProtegidas = @(
    [Environment]::GetFolderPath('MyDocuments'),
    [Environment]::GetFolderPath('Desktop'),
    [Environment]::GetFolderPath('MyPictures'),
    [Environment]::GetFolderPath('MyVideos'),
    [Environment]::GetFolderPath('MyMusic'),
    "$env:USERPROFILE\Downloads",
    "$env:USERPROFILE\OneDrive",
    $env:OneDrive
) | Where-Object { $_ }
$palabrasProtegidas = 'moto|bike|biker|cruiser|v-twin|vtwin|longrun|ride ?logic|\bcars?\b|\bautos?\b|carro|coche|channel intelligence'

function Es-Protegida([string]$ruta) {
    foreach ($p in $rutasProtegidas) {
        if ($ruta.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $ruta -match $palabrasProtegidas
}

function Medir([string]$ruta) {
    if (-not (Test-Path -LiteralPath $ruta)) { return 0 }
    $s = (Get-ChildItem -LiteralPath $ruta -Recurse -Force -File -ErrorAction SilentlyContinue |
          Measure-Object -Property Length -Sum).Sum
    if ($s) { return [double]$s } else { return 0 }
}

function GB([double]$bytes) { '{0:N2} GB' -f ($bytes / 1GB) }

function Borrar-Item($item) {
    # Nunca seguir accesos directos/enlaces de carpeta: podrian apuntar a tus archivos.
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return }
    if (Es-Protegida $item.FullName) { return }
    if ($item.PSIsContainer) {
        Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue | ForEach-Object { Borrar-Item $_ }
        try { [IO.Directory]::Delete($item.FullName, $false) } catch { }   # solo si quedo vacia
    } else {
        Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue  # si esta en uso, se salta
    }
}

function Vaciar([string]$ruta) {
    if (-not (Test-Path -LiteralPath $ruta)) { return }
    if (Es-Protegida $ruta) { Write-Host "   (omitido, protegido) $ruta" -ForegroundColor DarkGray; return }
    Get-ChildItem -LiteralPath $ruta -Force -ErrorAction SilentlyContinue | ForEach-Object { Borrar-Item $_ }
}

# Carpetas de cache de navegadores basados en Chromium (por cada perfil)
function Caches-Chromium([string]$userData) {
    $out = @("$userData\ShaderCache", "$userData\GrShaderCache", "$userData\GraphiteDawnCache")
    Get-ChildItem -LiteralPath $userData -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' -or $_.Name -eq 'Guest Profile' } |
        ForEach-Object { $out += "$($_.FullName)\Cache", "$($_.FullName)\Code Cache", "$($_.FullName)\GPUCache" }
    return $out
}

$firefox = Get-ChildItem "$L\Mozilla\Firefox\Profiles" -Directory -Force -ErrorAction SilentlyContinue |
           ForEach-Object { "$($_.FullName)\cache2" }

# --- Que se limpia ---
$grupos = [ordered]@{
    'Temporales de tu usuario'           = @($env:TEMP)
    'Temporales de Windows'              = @("$env:windir\Temp")
    'Descargas de Windows Update'        = @("$env:windir\SoftwareDistribution\Download")
    'Reportes y volcados de errores'     = @("$L\CrashDumps", "$env:windir\Minidump",
                                             "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
                                             "$env:ProgramData\Microsoft\Windows\WER\ReportQueue")
    'Cache de Chrome'                    = Caches-Chromium "$L\Google\Chrome\User Data"
    'Cache de Edge'                      = Caches-Chromium "$L\Microsoft\Edge\User Data"
    'Cache de Brave'                     = Caches-Chromium "$L\BraveSoftware\Brave-Browser\User Data"
    'Cache de Firefox'                   = @($firefox)
    'Cache de Discord'                   = @("$R\discord\Cache", "$R\discord\Code Cache", "$R\discord\GPUCache")
    'Cache de CapCut (no toca proyectos)' = @("$L\CapCut\User Data\Cache")
    'Cache de medios de Adobe'           = @("$R\Adobe\Common\Media Cache Files", "$R\Adobe\Common\Media Cache")
    'Cache de graficos (DirectX/NVIDIA/AMD)' = @("$L\D3DSCache", "$L\NVIDIA\DXCache", "$L\NVIDIA\GLCache",
                                                 "$L\AMD\DxCache", "$L\AMD\DxcCache")
    'Cache de npm / pip / yarn'          = @("$L\npm-cache", "$R\npm-cache", "$L\pip\cache", "$L\Yarn\Cache")
}

$antes = (Get-PSDrive C).Free
Write-Host ""
Write-Host "=== Limpieza de disco C: ===" -ForegroundColor Cyan
Write-Host "Espacio libre ahora: $(GB $antes)"
Write-Host "Midiendo lo que se puede borrar (puede tardar un par de minutos)..."
Write-Host ""

$total = 0
$tamanos = @{}
foreach ($g in $grupos.Keys) {
    $s = 0
    foreach ($r in $grupos[$g]) { if ($r) { $s += Medir $r } }
    $tamanos[$g] = $s
    $total += $s
    if ($s -gt 0) { Write-Host ('  {0,-42} {1,10}' -f $g, (GB $s)) }
}

$shell = New-Object -ComObject Shell.Application
$papelera = 0
$shell.Namespace(10).Items() | ForEach-Object { $papelera += [double]$_.ExtendedProperty('Size') }

Write-Host ""
Write-Host ('  {0,-42} {1,10}' -f 'TOTAL caches y temporales', (GB $total)) -ForegroundColor Yellow
Write-Host ('  {0,-42} {1,10}' -f 'Papelera de reciclaje (aparte)', (GB $papelera))
Write-Host "  + limpieza interna de Windows (actualizaciones viejas, Windows.old, etc.)"
Write-Host ""
Write-Host "Cierra Chrome, Edge, Discord, CapCut y Premiere antes de seguir" -ForegroundColor Yellow
Write-Host "(lo que este abierto se salta, no pasa nada)."
Write-Host ""

function Preguntar([string]$texto) {
    if ($SinPreguntar) { return $true }
    return (Read-Host "$texto (S/N)") -match '^[sS]'
}

if (-not (Preguntar 'Borrar caches y temporales?')) { Write-Host 'Cancelado. No se borro nada.'; Read-Host 'Enter para salir'; exit }
$vaciarPapelera = $papelera -gt 0 -and (Preguntar 'Vaciar tambien la Papelera de reciclaje?')

# --- Borrar ---
Write-Host ""
Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
foreach ($g in $grupos.Keys) {
    if ($tamanos[$g] -le 0) { continue }
    Write-Host "Limpiando: $g"
    foreach ($r in $grupos[$g]) { if ($r) { Vaciar $r } }
}
Start-Service wuauserv, bits -ErrorAction SilentlyContinue

Write-Host "Limpiando cache de Optimizacion de distribucion..."
Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue

if ($vaciarPapelera) {
    Write-Host "Vaciando la Papelera..."
    Clear-RecycleBin -DriveLetter C -Force -ErrorAction SilentlyContinue
}

# Liberador de espacio de Windows, solo categorias de sistema (NUNCA la carpeta Descargas)
Write-Host "Ejecutando el Liberador de espacio de Windows (puede tardar varios minutos)..."
$categorias = @('Active Setup Temp Folders', 'D3D Shader Cache', 'Delivery Optimization Files',
    'Downloaded Program Files', 'Internet Cache Files', 'Old ChkDsk Files', 'Previous Installations',
    'Setup Log Files', 'System error memory dump files', 'System error minidump files',
    'Temporary Files', 'Temporary Setup Files', 'Thumbnail Cache', 'Update Cleanup',
    'Upgrade Discarded Files', 'Windows Error Reporting Files', 'Windows ESD installation files',
    'Windows Upgrade Log Files')
$vc = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
foreach ($c in $categorias) {
    if (Test-Path "$vc\$c") { Set-ItemProperty -Path "$vc\$c" -Name StateFlags0777 -Value 2 -Type DWord }
}
Start-Process cleanmgr.exe -ArgumentList '/sagerun:777' -Wait

Write-Host "Limpiando componentes viejos de Windows Update (DISM)..."
Start-Process dism.exe -ArgumentList '/Online /Cleanup-Image /StartComponentCleanup' -Wait -NoNewWindow

$despues = (Get-PSDrive C).Free
Write-Host ""
Write-Host "=== Listo ===" -ForegroundColor Green
Write-Host "Espacio libre antes:   $(GB $antes)"
Write-Host "Espacio libre ahora:   $(GB $despues)"
Write-Host "Liberado:              $(GB ($despues - $antes))" -ForegroundColor Green
Write-Host ""

# --- Reporte (solo informativo, no borra nada) ---
if (Preguntar 'Quieres ver que carpetas de tu usuario ocupan mas espacio? (solo se muestra, no se borra)') {
    Write-Host "Midiendo... (en un disco tan lleno puede tardar varios minutos)"
    $raices = @(Get-ChildItem $env:USERPROFILE -Directory -Force) + @(Get-ChildItem $L -Directory -Force)
    $raices | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $_.FullName -ne $L } |
        ForEach-Object { [pscustomobject]@{ GB = [math]::Round((Medir $_.FullName) / 1GB, 1); Carpeta = $_.FullName } } |
        Sort-Object GB -Descending | Select-Object -First 15 | Format-Table -AutoSize | Out-Host

    Write-Host "Archivos de mas de 1 GB en Descargas:"
    Get-ChildItem "$env:USERPROFILE\Downloads" -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt 1GB } | Sort-Object Length -Descending | Select-Object -First 15 |
        ForEach-Object { '  {0,8}  {1}' -f (GB $_.Length), $_.FullName } | Out-Host
}

Read-Host 'Enter para salir'
