# =============================================================================
# FunFTP.ps1 — Servidor IIS-FTP | Practica 7 | Windows
# =============================================================================

$rootPath = "C:\FTP_Raiz"
$siteName = "ServidorFTP"

function Verificar-FTP {
    $feature = Get-WindowsFeature Web-FTP-Server
    if ($feature.Installed) {
        Write-Host "[OK] IIS-FTP ya esta instalado." -ForegroundColor Green
        $r = Read-Host "Desea reconfigurar? (s/N)"
        if ($r -notmatch '^[sS]$') { Pausa; return }
    } else {
        Write-Host "[INFO] Instalando IIS-FTP..." -ForegroundColor Cyan
        Install-WindowsFeature Web-FTP-Server, Web-FTP-Service -IncludeManagementTools | Out-Null
        Write-Host "[OK] IIS-FTP instalado." -ForegroundColor Green
    }
    Configurar-FTP
}

function Configurar-FTP {
    Import-Module WebAdministration

    foreach ($grupo in @("reprobados","recursadores")) {
        if (-not (Get-LocalGroup -Name $grupo -ErrorAction SilentlyContinue)) {
            New-LocalGroup $grupo | Out-Null
            Write-Host "[OK] Grupo $grupo creado." -ForegroundColor Green
        }
    }

    foreach ($folder in @("general","reprobados","recursadores")) {
        $path = "$rootPath\$folder"
        if (-not (Test-Path $path)) { New-Item -Path $path -ItemType Directory -Force | Out-Null }
    }

    # Crear estructura repositorio HTTP para practica 7
    foreach ($srv in @("IIS","Apache","Nginx","Tomcat")) {
        $p = "$rootPath\http\Windows\$srv"
        if (-not (Test-Path $p)) { New-Item -Path $p -ItemType Directory -Force | Out-Null }
    }

    icacls "$rootPath\general"      /grant "IUSR:(OI)(CI)(RX)" | Out-Null
    icacls "$rootPath\general"      /grant "NT AUTHORITY\Authenticated Users:(OI)(CI)(M)" | Out-Null
    icacls "$rootPath\reprobados"   /grant "reprobados:(OI)(CI)(M)" | Out-Null
    icacls "$rootPath\recursadores" /grant "recursadores:(OI)(CI)(M)" | Out-Null
    icacls $rootPath /grant "IUSR:(RX)" | Out-Null
    icacls $rootPath /grant "NT AUTHORITY\Authenticated Users:(RX)" | Out-Null

    if (-not (Get-WebSite -Name $siteName -ErrorAction SilentlyContinue)) {
        New-WebFtpSite -Name $siteName -Port 21 -PhysicalPath $rootPath -Force | Out-Null
    } else {
        Set-ItemProperty "IIS:\Sites\$siteName" -Name physicalPath -Value $rootPath
    }

    Set-ItemProperty "IIS:\Sites\$siteName" -Name "ftpServer.security.ssl.controlChannelPolicy" -Value 0
    Set-ItemProperty "IIS:\Sites\$siteName" -Name "ftpServer.security.ssl.dataChannelPolicy" -Value 0
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$siteName" -Name "ftpServer.userIsolation.mode" -Value 0

    try {
        Add-WebConfigurationProperty -PSPath "IIS:\" -Location $siteName `
            -Filter "system.ftpServer/security/authorization" -Name "." `
            -Value @{accessType="Allow"; users="*"; roles=""; permissions="Read,Write"} `
            -ErrorAction SilentlyContinue
    } catch {}

    Configurar-Firewall -puerto "21" -nombre "FTP"
    Restart-Service FTPSVC -ErrorAction SilentlyContinue
    Write-Host "[OK] Sitio FTP configurado en puerto 21." -ForegroundColor Green
    Write-Host "[OK] Repositorio HTTP creado en $rootPath\http\Windows\" -ForegroundColor Green
}

function Crear-UsuariosFTP {
    $n = Read-Host "Numero de usuarios a crear"
    for ($i = 1; $i -le $n; $i++) {
        $usuario = Read-Host "Nombre del usuario"
        $password = Read-Host "Contrasena" -AsSecureString
        $grupo = ""
        while ($grupo -ne "reprobados" -and $grupo -ne "recursadores") {
            $grupo = Read-Host "Grupo (reprobados/recursadores)"
        }
        if (-not (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue)) {
            try {
                New-LocalUser -Name $usuario -Password $password -PasswordNeverExpires | Out-Null
                Add-LocalGroupMember -Group $grupo -Member $usuario | Out-Null
                $personalPath = "$rootPath\$usuario"
                New-Item -Path $personalPath -ItemType Directory -Force | Out-Null
                icacls $personalPath /grant "${usuario}:(OI)(CI)(M)" | Out-Null
                icacls $rootPath /grant "${usuario}:(RX)" | Out-Null
                Write-Host "[OK] Usuario $usuario creado en $grupo." -ForegroundColor Green
            } catch {
                Write-Host "[ERROR] $_" -ForegroundColor Red; $i--
            }
        } else {
            Write-Host "[!] El usuario $usuario ya existe." -ForegroundColor Yellow; $i--
        }
    }
}

function Eliminar-UsuarioFTP {
    $u = Read-Host "Usuario a eliminar"
    if (Get-LocalUser -Name $u -ErrorAction SilentlyContinue) {
        Remove-LocalUser -Name $u
        Remove-Item "$rootPath\$u" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Usuario $u eliminado." -ForegroundColor Green
    } else { Write-Host "[!] No existe." -ForegroundColor Red }
}

function Consultar-UsuariosFTP {
    Write-Host "`n  Usuarios FTP:" -ForegroundColor White
    foreach ($g in @("reprobados","recursadores")) {
        $miembros = (Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue).Name
        foreach ($m in $miembros) { Write-Host "  $($m.Split('\')[-1])  ->  $g" }
    }
}

function Mover-GrupoFTP {
    $u     = Read-Host "Usuario"
    $nuevo = Read-Host "Nuevo grupo (reprobados/recursadores)"
    $viejo = if ($nuevo -eq "reprobados") { "recursadores" } else { "reprobados" }
    Remove-LocalGroupMember -Group $viejo -Member $u -ErrorAction SilentlyContinue
    Add-LocalGroupMember   -Group $nuevo -Member $u -ErrorAction SilentlyContinue
    Write-Host "[OK] $u movido de $viejo a $nuevo." -ForegroundColor Green
}

function Crear-GrupoFTP {
    $g = Read-Host "Nombre del grupo"
    if (-not (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)) {
        New-LocalGroup $g | Out-Null
        New-Item -Path "$rootPath\$g" -ItemType Directory -Force | Out-Null
        Write-Host "[OK] Grupo $g creado." -ForegroundColor Green
    } else { Write-Host "[!] Ya existe." -ForegroundColor Yellow }
}

function Eliminar-GrupoFTP {
    $g = Read-Host "Nombre del grupo a eliminar"
    Remove-LocalGroup -Name $g -ErrorAction SilentlyContinue
    Write-Host "[OK] Grupo $g eliminado." -ForegroundColor Green
}

function Consultar-GruposFTP {
    foreach ($g in @("reprobados","recursadores")) {
        $m = (Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue).Name -join ", "
        Write-Host "  $g -> $m"
    }
}
