# =============================================================================
# Main7.ps1 — Orquestador | Practica 7 | Windows Server
# Instalacion Hibrida (WEB/FTP) + SSL/TLS en servicios HTTP y FTP
# =============================================================================

# Verificar privilegios
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "[ERROR] Ejecuta PowerShell como Administrador."
    pause; exit
}

# Cargar modulos
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$dir\FunGENERALES.ps1"
. "$dir\FunFTP.ps1"
. "$dir\FunHTTP.ps1"
. "$dir\FunSSL.ps1"
. "$dir\FunClienteFTP.ps1"

Import-Module WebAdministration -ErrorAction SilentlyContinue

# =============================================================================
# MENUS
# =============================================================================

function Menu-FTP-Servidor {
    Clear-Host
    Separador
    Write-Host "   SERVIDOR FTP - CONFIGURACION" -ForegroundColor White
    Separador
    Write-Host ""
    Verificar-FTP
}

function Menu-FTP-Usuarios {
    while ($true) {
        Clear-Host
        Separador
        Write-Host "   ADMINISTRAR USUARIOS FTP" -ForegroundColor White
        Separador
        Write-Host "  1. Alta usuario"
        Write-Host "  2. Baja usuario"
        Write-Host "  3. Consultar usuarios"
        Write-Host "  4. Mover usuario a otro grupo"
        Write-Host "  0. Volver"
        Separador
        $op = Read-Host "Opcion"
        switch ($op) {
            "1" { Crear-UsuariosFTP; Pausa }
            "2" { Eliminar-UsuarioFTP; Pausa }
            "3" { Consultar-UsuariosFTP; Pausa }
            "4" { Mover-GrupoFTP; Pausa }
            "0" { return }
            default { Write-Host "[AVISO] Opcion invalida." -ForegroundColor Yellow }
        }
    }
}

function Menu-FTP-Grupos {
    while ($true) {
        Clear-Host
        Separador
        Write-Host "   ADMINISTRAR GRUPOS FTP" -ForegroundColor White
        Separador
        Write-Host "  1. Alta grupo"
        Write-Host "  2. Baja grupo"
        Write-Host "  3. Consultar grupos"
        Write-Host "  0. Volver"
        Separador
        $op = Read-Host "Opcion"
        switch ($op) {
            "1" { Crear-GrupoFTP; Pausa }
            "2" { Eliminar-GrupoFTP; Pausa }
            "3" { Consultar-GruposFTP; Pausa }
            "0" { return }
            default { Write-Host "[AVISO] Opcion invalida." -ForegroundColor Yellow }
        }
    }
}

function Menu-HTTP {
    Clear-Host
    Separador
    Write-Host "   INSTALAR SERVICIO HTTP" -ForegroundColor White
    Separador
    Write-Host "  ORIGEN DE INSTALACION:"
    Write-Host "  1. WEB - Chocolatey (internet)"
    Write-Host "  2. FTP - Repositorio privado"
    Write-Host "  0. Volver"
    Separador
    $op = Read-Host "Origen [0-2]"
    switch ($op) {
        "1" { Menu-HTTP-Web }
        "2" { Menu-HTTP-FTP }
        "0" { return }
        default { Write-Host "[AVISO] Opcion invalida." -ForegroundColor Yellow }
    }
}

function Menu-HTTP-Web {
    Clear-Host
    Separador
    Write-Host "   INSTALAR HTTP - DESDE CHOCOLATEY" -ForegroundColor White
    Separador
    Write-Host "  1. IIS"
    Write-Host "  2. Apache2"
    Write-Host "  3. Nginx"
    Write-Host "  4. Tomcat"
    Write-Host "  0. Volver"
    Separador
    $op = Read-Host "Servicio [0-4]"
    switch ($op) {
        "1" { Instalar-IIS;    Preguntar-SSL -servicio "iis";    Pausa }
        "2" { Instalar-Apache; Preguntar-SSL -servicio "apache"; Pausa }
        "3" { Instalar-Nginx;  Preguntar-SSL -servicio "nginx";  Pausa }
        "4" { Instalar-Tomcat; Preguntar-SSL -servicio "tomcat"; Pausa }
        "0" { return }
        default { Write-Host "[AVISO] Opcion invalida." -ForegroundColor Yellow }
    }
}

function Menu-HTTP-FTP {
    Write-Host ""
    Write-Host "[INFO] Instalacion desde repositorio FTP privado" -ForegroundColor Cyan
    Write-Host "[AVISO] Estructura esperada: /http/Windows/{IIS,Apache,Nginx,Tomcat}/" -ForegroundColor Yellow
    Write-Host ""

    $resultado = Navegador-FTP

    if (-not $resultado -or -not $script:FTP_INSTALADOR) {
        Write-Host "[ERROR] No se obtuvo un instalador valido." -ForegroundColor Red
        Pausa; return
    }

    Instalar-Desde-FTP -archivo $script:FTP_INSTALADOR -servicio $script:FTP_SERVICIO

    $srvLower = $script:FTP_SERVICIO.ToLower()
    switch -Wildcard ($srvLower) {
        "apache*" { Preguntar-SSL -servicio "apache" }
        "nginx*"  { Preguntar-SSL -servicio "nginx"  }
        "tomcat*" { Preguntar-SSL -servicio "tomcat" }
        "iis*"    { Preguntar-SSL -servicio "iis"    }
    }
    Pausa
}

function Menu-SSL-Individual {
    Clear-Host
    Separador
    Write-Host "   HABILITAR SSL - SERVICIO INDIVIDUAL" -ForegroundColor White
    Separador
    Write-Host "  1. IIS     (HTTPS 443 + HTTP->HTTPS)"
    Write-Host "  2. Apache  (HTTPS 443 + HTTP->HTTPS)"
    Write-Host "  3. Nginx   (HTTPS 443 + HTTP->HTTPS)"
    Write-Host "  4. Tomcat  (HTTPS 443)"
    Write-Host "  5. IIS-FTP (FTPS canal cifrado)"
    Write-Host "  0. Volver"
    Separador
    $s = Read-Host "Opcion [0-5]"
    switch ($s) {
        "1" { Habilitar-SSL-IIS;    Pausa }
        "2" { Habilitar-SSL-Apache; Pausa }
        "3" { Habilitar-SSL-Nginx;  Pausa }
        "4" { Habilitar-SSL-Tomcat; Pausa }
        "5" { Habilitar-SSL-FTP;    Pausa }
        "0" { return }
        default { Write-Host "[AVISO] Opcion invalida." -ForegroundColor Yellow }
    }
}

# =============================================================================
# MENU PRINCIPAL
# =============================================================================

function Menu-Principal {
    while ($true) {
        Clear-Host
        Separador
        Write-Host "   PRACTICA 07 - DESPLIEGUE SEGURO (WINDOWS)" -ForegroundColor White
        Separador
        Write-Host "  -- SERVIDOR FTP --"
        Write-Host "  1. Instalar y configurar IIS-FTP"
        Write-Host "  2. Administrar usuarios FTP"
        Write-Host "  3. Administrar grupos FTP"
        Write-Host "  -- SERVICIOS HTTP --"
        Write-Host "  4. Instalar IIS / Apache / Nginx / Tomcat"
        Write-Host "  -- SSL / TLS --"
        Write-Host "  5. Habilitar SSL en un servicio"
        Write-Host "  6. Habilitar SSL en TODOS los servicios"
        Write-Host "  7. Ver resumen de verificacion SSL"
        Write-Host "  0. Salir"
        Separador

        $opt = Read-Host "Selecciona una opcion [0-7]"
        switch ($opt) {
            "1" { Menu-FTP-Servidor }
            "2" { Menu-FTP-Usuarios }
            "3" { Menu-FTP-Grupos }
            "4" { Menu-HTTP }
            "5" { Menu-SSL-Individual }
            "6" { SSL-Todos; Pausa }
            "7" { Resumen-SSL; Pausa }
            "0" { Write-Host "Saliendo..." -ForegroundColor White; exit }
            default { Write-Host "[AVISO] Opcion invalida." -ForegroundColor Yellow; Start-Sleep 1 }
        }
    }
}

# =============================================================================
# ARRANCAR
# =============================================================================
Menu-Principal
