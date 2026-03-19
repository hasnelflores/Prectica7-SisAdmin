# =============================================================================
# FunHTTP.ps1 — Instalacion HTTP (IIS/Apache/Nginx/Tomcat) | Practica 7 | Windows
# =============================================================================

function Instalar-IIS {
    Write-Host "`n==========================================" -ForegroundColor White
    Write-Host "        INSTALACION DE IIS                " -ForegroundColor White
    Write-Host "==========================================" -ForegroundColor White

    $puerto = Get-PuertoValido -porDefecto "8080"

    Write-Host "[INFO] Instalando IIS..." -ForegroundColor Cyan
    Install-WindowsFeature Web-Server, Web-Common-Http, Web-Static-Content, `
        Web-Default-Doc, Web-Http-Errors, Web-Http-Redirect, `
        Web-Mgmt-Console -IncludeManagementTools | Out-Null

    Import-Module WebAdministration

    # Asegurar que existe el sitio y el app pool
    if (-not (Get-WebAppPool -Name "DefaultAppPool" -ErrorAction SilentlyContinue)) {
        New-WebAppPool -Name "DefaultAppPool" | Out-Null
    }
    Start-WebAppPool -Name "DefaultAppPool" -ErrorAction SilentlyContinue

    if (-not (Get-WebSite -Name "Default Web Site" -ErrorAction SilentlyContinue)) {
        New-Website -Name "Default Web Site" -Port 80 `
            -PhysicalPath "C:\inetpub\wwwroot" `
            -ApplicationPool "DefaultAppPool" -Force | Out-Null
    }

    # Cambiar puerto
    Set-WebBinding -Name "Default Web Site" -BindingInformation "*:80:" `
        -PropertyName Port -Value $puerto -ErrorAction SilentlyContinue

    # Autenticacion anonima
    Set-WebConfigurationProperty `
        -Filter "system.webServer/security/authentication/anonymousAuthentication" `
        -PSPath "IIS:\Sites\Default Web Site" -Name enabled -Value $true
    Set-WebConfigurationProperty `
        -Filter "system.webServer/security/authentication/windowsAuthentication" `
        -PSPath "IIS:\Sites\Default Web Site" -Name enabled -Value $false

    # web.config simple
    @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <defaultDocument>
      <files><clear /><add value="index.html" /></files>
    </defaultDocument>
  </system.webServer>
</configuration>
"@ | Out-File "C:\inetpub\wwwroot\web.config" -Encoding UTF8 -Force

    Crear-PaginaWeb -ruta "C:\inetpub\wwwroot\index.html" `
        -servidor "Microsoft IIS" -version "Nativo" -puerto $puerto

    icacls "C:\inetpub\wwwroot" /grant "IUSR:(OI)(CI)(RX)" `
        /grant "IIS_IUSRS:(OI)(CI)(RX)" /grant "Todos:(OI)(CI)(RX)" | Out-Null

    Configurar-Firewall -puerto $puerto -nombre "IIS"
    Restart-Service W3SVC -Force
    Start-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
    Write-Host "[OK] IIS en puerto $puerto" -ForegroundColor Green
}

function Instalar-Apache {
    Write-Host "`n==========================================" -ForegroundColor White
    Write-Host "        INSTALACION DE APACHE2            " -ForegroundColor White
    Write-Host "==========================================" -ForegroundColor White

    $ver    = Select-Version -packageName "apache-httpd"
    $puerto = Get-PuertoValido -porDefecto "8081"

    Write-Host "[INFO] Instalando Apache con Chocolatey..." -ForegroundColor Cyan
    if ($ver -eq "latest") { choco install apache-httpd --force -y | Out-Null; $ver = "Latest" }
    else { choco install apache-httpd --version $ver --force -y | Out-Null }

    $apacheDir = @("C:\tools\Apache24","C:\Apache24","C:\ProgramData\chocolatey\lib\apache-httpd\tools\Apache24") `
        | Where-Object { Test-Path "$_\conf\httpd.conf" } | Select-Object -First 1
    if (-not $apacheDir) { Write-Host "[ERROR] No se encontro Apache." -ForegroundColor Red; return }

    $conf = "$apacheDir\conf\httpd.conf"
    $c = Get-Content $conf -Raw
    $c = $c -replace 'Listen \d+', "Listen $puerto"
    $c = $c -replace '#LoadModule headers_module', 'LoadModule headers_module'
    $c = $c -replace '#LoadModule rewrite_module', 'LoadModule rewrite_module'
    $c += "`nServerTokens Prod`nServerSignature Off"
    $c | Set-Content $conf

    Crear-PaginaWeb -ruta "$apacheDir\htdocs\index.html" `
        -servidor "Apache Win64" -version $ver -puerto $puerto
    Configurar-Firewall -puerto $puerto -nombre "Apache"
    Restart-Service "Apache*" -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] Apache en puerto $puerto" -ForegroundColor Green
}

function Instalar-Nginx {
    Write-Host "`n==========================================" -ForegroundColor White
    Write-Host "        INSTALACION DE NGINX              " -ForegroundColor White
    Write-Host "==========================================" -ForegroundColor White

    $puerto = Get-PuertoValido -porDefecto "8082"

    Write-Host "[INFO] Instalando Nginx con Chocolatey..." -ForegroundColor Cyan
    choco install nginx -y --force | Out-Null

    $nginxFile = Get-ChildItem -Path "C:\tools" -Filter "nginx.exe" `
        -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $nginxFile) {
        Write-Host "[ERROR] No se encontro nginx.exe." -ForegroundColor Red; return
    }

    $nginxDir = $nginxFile.DirectoryName
    $conf = Join-Path $nginxDir "conf\nginx.conf"
    (Get-Content $conf) -replace 'listen\s+80;', "listen $puerto;" | Set-Content $conf

    # Crear pagina web en el directorio html de nginx
    Crear-PaginaWeb -ruta "$nginxDir\html\index.html" `
        -servidor "NGINX" -version "latest" -puerto $puerto

    Configurar-Firewall -puerto $puerto -nombre "Nginx"
    Stop-Process -Name nginx -Force -ErrorAction SilentlyContinue
    Start-Process $nginxFile.FullName -WorkingDirectory $nginxDir
    Write-Host "[OK] Nginx en puerto $puerto" -ForegroundColor Green
}

function Instalar-Tomcat {
    Write-Host "`n==========================================" -ForegroundColor White
    Write-Host "      INSTALACION DE APACHE TOMCAT        " -ForegroundColor White
    Write-Host "==========================================" -ForegroundColor White

    $ver    = Select-Version -packageName "tomcat"
    $puerto = Get-PuertoValido -porDefecto "8083"

    Write-Host "[INFO] Instalando Tomcat con Chocolatey..." -ForegroundColor Cyan
    if ($ver -eq "latest") { choco install tomcat --force -y | Out-Null; $ver = "Latest" }
    else { choco install tomcat --version $ver --force -y | Out-Null }

    $basePath  = "C:\ProgramData\chocolatey\lib\Tomcat\tools"
    $tomcatDir = Get-ChildItem -Path $basePath -Directory -Filter "apache-tomcat*" `
        -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName -First 1
    if (-not $tomcatDir) { Write-Host "[ERROR] No se encontro Tomcat." -ForegroundColor Red; return }

    (Get-Content "$tomcatDir\conf\server.xml") `
        -replace 'port="8080"', "port=`"$puerto`"" | Set-Content "$tomcatDir\conf\server.xml"

    $rootDir = "$tomcatDir\webapps\ROOT"
    New-Item -ItemType Directory -Path $rootDir -Force | Out-Null
    Crear-PaginaWeb -ruta "$rootDir\index.html" `
        -servidor "Apache Tomcat" -version $ver -puerto $puerto

    Configurar-Firewall -puerto $puerto -nombre "Tomcat"
    $svc = Get-Service -Name "Tomcat*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($svc) { Restart-Service $svc.Name -Force -ErrorAction SilentlyContinue }
    Write-Host "[OK] Tomcat en puerto $puerto" -ForegroundColor Green
}

function Ver-EstadoHTTP {
    Write-Host "`n  Estado de servicios HTTP:" -ForegroundColor White
    Get-Service W3SVC -ErrorAction SilentlyContinue | ForEach-Object {
        $c = if ($_.Status -eq 'Running') {'Green'} else {'Red'}
        Write-Host "  IIS    | $($_.Status)" -ForegroundColor $c
    }
    Get-Service "Apache*" -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object {
        $c = if ($_.Status -eq 'Running') {'Green'} else {'Red'}
        Write-Host "  Apache | $($_.Status)" -ForegroundColor $c
    }
    if (Get-Process nginx -ErrorAction SilentlyContinue) {
        Write-Host "  NGINX  | Running" -ForegroundColor Green
    } else {
        Write-Host "  NGINX  | Stopped" -ForegroundColor Red
    }
    Get-Service "Tomcat*" -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object {
        $c = if ($_.Status -eq 'Running') {'Green'} else {'Red'}
        Write-Host "  Tomcat | $($_.Status)" -ForegroundColor $c
    }
}

function Instalar-Desde-FTP {
    param([string]$archivo, [string]$servicio)
    Write-Host "[INFO] Instalando $servicio desde $archivo ..." -ForegroundColor Cyan
    switch -Wildcard ($archivo) {
        "*.msi" { Start-Process msiexec -ArgumentList "/i `"$archivo`" /quiet" -Wait }
        "*.exe" { Start-Process $archivo -ArgumentList "/S /silent /quiet" -Wait }
        "*.zip" {
            $dest = "C:\tools\$servicio"
            Expand-Archive -Path $archivo -DestinationPath $dest -Force
            Write-Host "[OK] Extraido en $dest" -ForegroundColor Green
        }
        default { Write-Host "[ERROR] Formato no reconocido." -ForegroundColor Red }
    }
}
