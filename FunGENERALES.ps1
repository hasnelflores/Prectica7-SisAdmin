# =============================================================================
# FunGENERALES.ps1 — Funciones utilitarias compartidas | Practica 7 | Windows
# =============================================================================

$dominioSSL = "reprobados.com"
$certStore  = "Cert:\LocalMachine\My"

function Pausa {
    Write-Host "`nPresiona Enter para continuar..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Separador { Write-Host "=========================================" -ForegroundColor White }

function Get-PuertoValido {
    param([string]$porDefecto)
    while ($true) {
        $p = Read-Host "Puerto de escucha [1-65535] (ej. $porDefecto)"
        if (-not $p) { $p = $porDefecto }
        if ($p -notmatch '^\d+$' -or [int]$p -lt 1 -or [int]$p -gt 65535) {
            Write-Host "[ERROR] Puerto invalido." -ForegroundColor Red; continue
        }
        $enUso = Test-NetConnection -ComputerName localhost -Port $p -WarningAction SilentlyContinue
        if ($enUso.TcpTestSucceeded) {
            Write-Host "[ERROR] Puerto $p en uso. Elige otro." -ForegroundColor Red
        } else { return $p }
    }
}

function Configurar-Firewall {
    param([string]$puerto, [string]$nombre)
    New-NetFirewallRule -DisplayName "P7-$nombre-$puerto" -LocalPort $puerto -Protocol TCP `
        -Action Allow -Direction Inbound -ErrorAction SilentlyContinue | Out-Null
    Write-Host "[OK] Puerto $puerto abierto en Firewall." -ForegroundColor Green
}

function Crear-PaginaWeb {
    param([string]$ruta, [string]$servidor, [string]$version, [string]$puerto)
    $html = @"
<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><title>$servidor - Practica 7</title>
<style>
body{font-family:Arial,sans-serif;background:#1e1e2e;color:#cdd6f4;
     display:flex;justify-content:center;align-items:center;height:100vh;margin:0}
.box{background:#313244;border-radius:12px;padding:40px 60px;
     text-align:center;box-shadow:0 4px 20px rgba(0,0,0,.5)}
h1{color:#89b4fa;margin-bottom:20px}
p{font-size:1.2rem;margin:8px 0}
b{color:#a6e3a1}
.ssl{color:#f38ba8;font-size:0.9rem;margin-top:16px}
</style></head>
<body><div class="box">
<h1>Practica 7 - Infraestructura Segura</h1>
<p>Servidor: <b>$servidor</b></p>
<p>Version:  <b>$version</b></p>
<p>Puerto:   <b>$puerto</b></p>
<p class="ssl">$dominioSSL | SSL/TLS Activo</p>
</div></body></html>
"@
    $html | Out-File -FilePath $ruta -Encoding UTF8 -Force
    Write-Host "[OK] index.html creado en $ruta" -ForegroundColor Green
}

function Select-Version {
    param([string]$packageName)
    Write-Host "[INFO] Consultando versiones de $packageName con Chocolatey..." -ForegroundColor Cyan
    $chocoData = choco search $packageName --exact --all-versions -r 2>$null
    $versions = @()
    foreach ($line in $chocoData) {
        if ($line -match "(?i)^${packageName}\|") { $versions += ($line -split '\|')[1] }
    }
    if ($versions.Count -eq 0) {
        Write-Host "[AVISO] Usando version mas reciente." -ForegroundColor Yellow
        return "latest"
    }
    $versions = $versions | Sort-Object { try { [version]($_ -replace '[^\d\.]','') } catch { [version]"0.0" } } -Descending
    $display = $versions | Select-Object -First 5
    Write-Host "`n  Versiones disponibles:"; Separador
    $i = 1
    foreach ($v in $display) {
        if ($i -eq 1)                  { Write-Host "  $i) $v  <- latest" }
        elseif ($i -eq $display.Count) { Write-Host "  $i) $v  <- LTS/estable" }
        else                           { Write-Host "  $i) $v" }
        $i++
    }
    Separador
    $sel = Read-Host "  Elige una version [1-$($display.Count)]"
    if ($sel -match "^\d+$" -and [int]$sel -ge 1 -and [int]$sel -le $display.Count) {
        return $display[[int]$sel - 1]
    }
    return $display[0]
}
