# =============================================================================
# FunClienteFTP.ps1 — Cliente FTP dinamico + SHA256 | Practica 7 | Windows
# =============================================================================

$script:FTP_INSTALADOR = ""
$script:FTP_SERVICIO   = ""

function Navegador-FTP {
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor White
    Write-Host "   CLIENTE FTP - REPOSITORIO PRIVADO     " -ForegroundColor White
    Write-Host "=========================================" -ForegroundColor White
    Write-Host ""

    $ftpIP   = Read-Host "IP del servidor FTP"
    $ftpUser = Read-Host "Usuario FTP"
    $ftpPass = Read-Host "Password FTP"

    $ftpBase = "ftp://${ftpUser}:${ftpPass}@${ftpIP}"
    $ruta    = "http/Windows"

    Write-Host "[INFO] Conectando a ftp://$ftpIP/$ruta/ ..." -ForegroundColor Cyan

    try {
        $wc = New-Object System.Net.WebClient
        $wc.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
        $lista = $wc.DownloadString("$ftpBase/$ruta/")
        $servicios = ($lista -split "`r`n|`n") `
            | Where-Object { $_ -match '\S' } `
            | ForEach-Object { $_.Trim() } `
            | Where-Object { $_ -ne "" }
    } catch {
        Write-Host "[ERROR] No se pudo conectar al FTP: $_" -ForegroundColor Red
        return $false
    }

    Write-Host "`n  Servicios disponibles:"
    Separador
    $i = 1
    foreach ($s in $servicios) { Write-Host "  $i) $s"; $i++ }
    Separador

    $sel = Read-Host "Elige un servicio [1-$($servicios.Count)]"
    if ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $servicios.Count) {
        Write-Host "[ERROR] Seleccion invalida." -ForegroundColor Red; return $false
    }
    $servicio = $servicios[[int]$sel - 1]
    Write-Host "[OK] Servicio seleccionado: $servicio" -ForegroundColor Green

    # Listar instaladores
    try {
        $lista2   = $wc.DownloadString("$ftpBase/$ruta/$servicio/")
        $archivos = ($lista2 -split "`r`n|`n") `
            | Where-Object { $_ -match '\.(zip|msi|exe)$' } `
            | ForEach-Object { $_.Trim() }
    } catch {
        Write-Host "[ERROR] No se pudo listar archivos: $_" -ForegroundColor Red
        return $false
    }

    if ($archivos.Count -eq 0) {
        Write-Host "[ERROR] No se encontraron instaladores en $servicio." -ForegroundColor Red
        return $false
    }

    Write-Host "`n  Instaladores disponibles:"
    Separador
    $i = 1
    foreach ($a in $archivos) { Write-Host "  $i) $a"; $i++ }
    Separador

    $selA = Read-Host "Elige un instalador [1-$($archivos.Count)]"
    if ($selA -notmatch '^\d+$' -or [int]$selA -lt 1 -or [int]$selA -gt $archivos.Count) {
        Write-Host "[ERROR] Seleccion invalida." -ForegroundColor Red; return $false
    }
    $archivo = $archivos[[int]$selA - 1]
    Write-Host "[OK] Instalador seleccionado: $archivo" -ForegroundColor Green

    $localPath = "$env:TEMP\$archivo"
    $hashPath  = "$localPath.sha256"

    Write-Host "[INFO] Descargando $archivo ..." -ForegroundColor Cyan
    try {
        $wc.DownloadFile("$ftpBase/$ruta/$servicio/$archivo", $localPath)
        Write-Host "[OK] Descargado: $localPath" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] No se pudo descargar: $_" -ForegroundColor Red
        return $false
    }

    # Verificar hash SHA256
    try {
        $wc.DownloadFile("$ftpBase/$ruta/$servicio/$archivo.sha256", $hashPath)
        $hashEsperado = (Get-Content $hashPath -Raw).Split(' ')[0].Trim().ToLower()
        $hashLocal    = (Get-FileHash -Algorithm SHA256 -Path $localPath).Hash.ToLower()

        Write-Host ""
        Write-Host "  Hash esperado  (servidor): $hashEsperado"
        Write-Host "  Hash calculado (local):    $hashLocal"
        Write-Host ""

        if ($hashLocal -eq $hashEsperado) {
            Write-Host "[OK] INTEGRIDAD VERIFICADA - Archivo no corrompido." -ForegroundColor Green
        } else {
            Write-Host "[ERROR] FALLO DE INTEGRIDAD - Los hashes NO coinciden." -ForegroundColor Red
            Write-Host "[ERROR] El archivo puede estar corrompido o modificado." -ForegroundColor Red
            Remove-Item $localPath -Force -ErrorAction SilentlyContinue
            return $false
        }
    } catch {
        Write-Host "[AVISO] No se encontro .sha256. Omitiendo verificacion de integridad." -ForegroundColor Yellow
    }

    $script:FTP_INSTALADOR = $localPath
    $script:FTP_SERVICIO   = $servicio
    Write-Host "[OK] Instalador listo: $localPath" -ForegroundColor Green
    return $true
}

function Generar-HashRepo {
    # Utilitario para generar .sha256 de los archivos en el repositorio FTP
    param([string]$directorio = "C:\FTP_Raiz\http")
    Write-Host "[INFO] Generando archivos .sha256 en $directorio ..." -ForegroundColor Cyan
    Get-ChildItem -Path $directorio -Recurse `
        -Include "*.zip","*.msi","*.exe" | ForEach-Object {
        $hash = (Get-FileHash -Algorithm SHA256 -Path $_.FullName).Hash.ToLower()
        "$hash  $($_.Name)" | Out-File "$($_.FullName).sha256" -Encoding ASCII -Force
        Write-Host "[OK] Generado: $($_.Name).sha256" -ForegroundColor Green
    }
}
