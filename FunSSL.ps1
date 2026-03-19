# =============================================================================
# FunSSL.ps1 — SSL/TLS para IIS, Apache, Nginx, Tomcat y FTP | Windows
# =============================================================================

$script:sslResumen = @()

function Generar-Certificado {
    Write-Host "[INFO] Verificando certificado para $dominioSSL ..." -ForegroundColor Cyan
    $cert = Get-ChildItem $certStore | Where-Object { $_.Subject -like "*$dominioSSL*" } | Select-Object -First 1
    if ($cert) {
        Write-Host "[OK] Certificado ya existe: $($cert.Thumbprint)" -ForegroundColor Green
        return $cert
    }
    Write-Host "[INFO] Generando certificado autofirmado para www.$dominioSSL ..." -ForegroundColor Cyan
    $cert = New-SelfSignedCertificate `
        -DnsName "www.$dominioSSL", "$dominioSSL", "ftp.$dominioSSL" `
        -CertStoreLocation $certStore `
        -NotAfter (Get-Date).AddDays(365) `
        -FriendlyName "Practica7-$dominioSSL"
    Write-Host "[OK] Certificado generado. Thumbprint: $($cert.Thumbprint)" -ForegroundColor Green
    return $cert
}

function Preguntar-SSL {
    param([string]$servicio)
    Write-Host ""
    $r = Read-Host "Desea activar SSL en $servicio? [S/N]"
    if ($r -notmatch '^[sS]$') {
        Write-Host "[AVISO] SSL omitido para $servicio." -ForegroundColor Yellow; return
    }
    switch ($servicio.ToLower()) {
        "iis"    { Habilitar-SSL-IIS }
        "apache" { Habilitar-SSL-Apache }
        "nginx"  { Habilitar-SSL-Nginx }
        "tomcat" { Habilitar-SSL-Tomcat }
        "ftp"    { Habilitar-SSL-FTP }
    }
}

function Habilitar-SSL-IIS {
    Write-Host "[INFO] Habilitando SSL en IIS..." -ForegroundColor Cyan
    $cert = Generar-Certificado
    Import-Module WebAdministration

    $sitio = "Default Web Site"

    # Agregar binding HTTPS si no existe
    $bindingExiste = Get-WebBinding -Name $sitio -Protocol "https" -ErrorAction SilentlyContinue
    if (-not $bindingExiste) {
        New-WebBinding -Name $sitio -Protocol "https" -Port 443 -IPAddress "*" | Out-Null
    }

    # Asignar certificado
    try {
        $binding = Get-WebBinding -Name $sitio -Protocol "https" -Port 443
        $binding.AddSslCertificate($cert.Thumbprint, "My")
    } catch {
        Write-Host "[AVISO] No se pudo asignar cert al binding: $_" -ForegroundColor Yellow
    }

    # web.config con redireccion y sin restricciones
    @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <defaultDocument>
      <files><clear /><add value="index.html" /></files>
    </defaultDocument>
    <httpProtocol>
      <customHeaders>
        <add name="Strict-Transport-Security" value="max-age=31536000; includeSubDomains" />
        <add name="X-Frame-Options" value="SAMEORIGIN" />
        <add name="X-Content-Type-Options" value="nosniff" />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
</configuration>
"@ | Out-File "C:\inetpub\wwwroot\web.config" -Encoding UTF8 -Force

    # Autenticacion anonima activa
    Set-WebConfigurationProperty `
        -Filter "system.webServer/security/authentication/anonymousAuthentication" `
        -PSPath "IIS:\Sites\$sitio" -Name enabled -Value $true -ErrorAction SilentlyContinue
    Set-WebConfigurationProperty `
        -Filter "system.webServer/security/authentication/windowsAuthentication" `
        -PSPath "IIS:\Sites\$sitio" -Name enabled -Value $false -ErrorAction SilentlyContinue

    icacls "C:\inetpub\wwwroot" /grant "IUSR:(OI)(CI)(RX)" `
        /grant "IIS_IUSRS:(OI)(CI)(RX)" /grant "Todos:(OI)(CI)(RX)" | Out-Null

    Configurar-Firewall -puerto "443" -nombre "IIS-HTTPS"
    Restart-Service W3SVC -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] IIS: SSL en puerto 443. Redireccion HTTP->HTTPS activa." -ForegroundColor Green
    Verificar-SSL -nombre "IIS" -puerto 443
}

function Habilitar-SSL-Apache {
    Write-Host "[INFO] Habilitando SSL en Apache Windows..." -ForegroundColor Cyan
    $cert = Generar-Certificado

    $apacheDir = @("C:\tools\Apache24","C:\Apache24") `
        | Where-Object { Test-Path "$_\conf\httpd.conf" } | Select-Object -First 1
    if (-not $apacheDir) { Write-Host "[ERROR] No se encontro Apache." -ForegroundColor Red; return }

    $pfxPath  = "$apacheDir\conf\reprobados.pfx"
    $certPath = "$apacheDir\conf\reprobados.crt"
    $keyPath  = "$apacheDir\conf\reprobados.key"
    $pfxPass  = ConvertTo-SecureString "reprobados123" -AsPlainText -Force

    Export-PfxCertificate -Cert "$certStore\$($cert.Thumbprint)" `
        -FilePath $pfxPath -Password $pfxPass | Out-Null

    $openssl = Get-Command openssl -ErrorAction SilentlyContinue
    if ($openssl) {
        & openssl pkcs12 -in $pfxPath -nokeys -out $certPath -passin pass:reprobados123 2>$null
        & openssl pkcs12 -in $pfxPath -nocerts -nodes -out $keyPath -passin pass:reprobados123 2>$null
    } else {
        $certPath = $pfxPath; $keyPath = $pfxPath
        Write-Host "[AVISO] openssl no encontrado. Usando PFX." -ForegroundColor Yellow
    }

    $conf   = "$apacheDir\conf\httpd.conf"
    $sslConf = @"

# SSL Practica 7
LoadModule ssl_module modules/mod_ssl.so
LoadModule rewrite_module modules/mod_rewrite.so
Listen 443
<VirtualHost *:443>
    ServerName www.$dominioSSL
    SSLEngine on
    SSLCertificateFile "$certPath"
    SSLCertificateKeyFile "$keyPath"
    SSLProtocol all -SSLv2 -SSLv3
    Header always set Strict-Transport-Security "max-age=31536000"
</VirtualHost>
<VirtualHost *:80>
    ServerName www.$dominioSSL
    RewriteEngine On
    RewriteRule ^(.*)$ https://%{HTTP_HOST}`$1 [R=301,L]
</VirtualHost>
"@
    Add-Content $conf $sslConf
    Configurar-Firewall -puerto "443" -nombre "Apache-HTTPS"
    Restart-Service "Apache*" -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] Apache: SSL en puerto 443." -ForegroundColor Green
    Verificar-SSL -nombre "Apache" -puerto 443
}

function Habilitar-SSL-Nginx {
    Write-Host "[INFO] Habilitando SSL en Nginx Windows..." -ForegroundColor Cyan
    $cert = Generar-Certificado

    $nginxFile = Get-ChildItem -Path "C:\tools" -Filter "nginx.exe" `
        -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $nginxFile) { Write-Host "[ERROR] No se encontro nginx.exe." -ForegroundColor Red; return }

    $nginxDir = $nginxFile.DirectoryName
    $certDir  = "$nginxDir\conf\ssl"
    New-Item -ItemType Directory -Path $certDir -Force | Out-Null

    $pfxPath  = "$certDir\reprobados.pfx"
    $certPath = "$certDir\reprobados.crt"
    $keyPath  = "$certDir\reprobados.key"
    $pfxPass  = ConvertTo-SecureString "reprobados123" -AsPlainText -Force
    Export-PfxCertificate -Cert "$certStore\$($cert.Thumbprint)" `
        -FilePath $pfxPath -Password $pfxPass | Out-Null

    $openssl = Get-Command openssl -ErrorAction SilentlyContinue
    if ($openssl) {
        & openssl pkcs12 -in $pfxPath -nokeys -out $certPath -passin pass:reprobados123 2>$null
        & openssl pkcs12 -in $pfxPath -nocerts -nodes -out $keyPath -passin pass:reprobados123 2>$null
    }

    $conf    = "$nginxDir\conf\nginx.conf"
    $sslBlock = @"

    server {
        listen 443 ssl;
        server_name www.$dominioSSL $dominioSSL;
        ssl_certificate     conf/ssl/reprobados.crt;
        ssl_certificate_key conf/ssl/reprobados.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        add_header Strict-Transport-Security "max-age=31536000" always;
        location / { root html; index index.html; }
    }
    server {
        listen 80;
        server_name www.$dominioSSL $dominioSSL;
        return 301 https://`$host`$request_uri;
    }
"@
    $contenido = Get-Content $conf -Raw
    $contenido = $contenido -replace '(\s*\}\s*)$', "$sslBlock`n}"
    $contenido | Set-Content $conf

    Configurar-Firewall -puerto "443" -nombre "Nginx-HTTPS"
    Stop-Process -Name nginx -Force -ErrorAction SilentlyContinue
    Start-Process $nginxFile.FullName -WorkingDirectory $nginxDir
    Write-Host "[OK] Nginx: SSL en puerto 443." -ForegroundColor Green
    Verificar-SSL -nombre "Nginx" -puerto 443
}

function Habilitar-SSL-Tomcat {
    Write-Host "[INFO] Habilitando SSL en Tomcat Windows..." -ForegroundColor Cyan
    $cert = Generar-Certificado

    $basePath  = "C:\ProgramData\chocolatey\lib\Tomcat\tools"
    $tomcatDir = Get-ChildItem -Path $basePath -Directory -Filter "apache-tomcat*" `
        -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName -First 1
    if (-not $tomcatDir) { Write-Host "[ERROR] No se encontro Tomcat." -ForegroundColor Red; return }

    $p12Path = "$tomcatDir\conf\reprobados.p12"
    $pfxPass = ConvertTo-SecureString "reprobados123" -AsPlainText -Force
    Export-PfxCertificate -Cert "$certStore\$($cert.Thumbprint)" `
        -FilePath $p12Path -Password $pfxPass | Out-Null

    $serverXml = "$tomcatDir\conf\server.xml"
    $connector  = @"

    <Connector port="443" protocol="org.apache.coyote.http11.Http11NioProtocol"
               SSLEnabled="true" scheme="https" secure="true">
        <SSLHostConfig>
            <Certificate certificateKeystoreFile="conf/reprobados.p12"
                         certificateKeystorePassword="reprobados123"
                         certificateKeystoreType="PKCS12" type="RSA" />
        </SSLHostConfig>
    </Connector>
"@
    $xml = Get-Content $serverXml -Raw
    if ($xml -notmatch 'port="443"') {
        $xml = $xml -replace '</Service>', "$connector`n</Service>"
        $xml | Set-Content $serverXml
    }

    Configurar-Firewall -puerto "443" -nombre "Tomcat-HTTPS"
    $svc = Get-Service -Name "Tomcat*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($svc) { Restart-Service $svc.Name -Force -ErrorAction SilentlyContinue }
    Write-Host "[OK] Tomcat: SSL en puerto 443." -ForegroundColor Green
    Verificar-SSL -nombre "Tomcat" -puerto 443
}

function Habilitar-SSL-FTP {
    Write-Host "[INFO] Habilitando FTPS en IIS-FTP..." -ForegroundColor Cyan
    $cert = Generar-Certificado
    Import-Module WebAdministration

    Set-ItemProperty "IIS:\Sites\$siteName" -Name "ftpServer.security.ssl.serverCertHash"    -Value $cert.Thumbprint
    Set-ItemProperty "IIS:\Sites\$siteName" -Name "ftpServer.security.ssl.controlChannelPolicy" -Value 1
    Set-ItemProperty "IIS:\Sites\$siteName" -Name "ftpServer.security.ssl.dataChannelPolicy"    -Value 1

    Restart-Service FTPSVC -ErrorAction SilentlyContinue
    Write-Host "[OK] FTPS habilitado. Thumbprint: $($cert.Thumbprint)" -ForegroundColor Green
    Verificar-SSL -nombre "IIS-FTP" -puerto 21
}

function Verificar-SSL {
    param([string]$nombre, [int]$puerto = 443)
    Write-Host "[INFO] Verificando SSL en $nombre (puerto $puerto)..." -ForegroundColor Cyan
    Start-Sleep -Seconds 2
    $conn = Test-NetConnection -ComputerName localhost -Port $puerto -WarningAction SilentlyContinue
    if ($conn.TcpTestSucceeded) {
        Write-Host "[OK] $nombre : puerto $puerto ESCUCHANDO." -ForegroundColor Green
        $script:sslResumen += "[OK] $nombre | Puerto $puerto | SSL ACTIVO"
    } else {
        Write-Host "[AVISO] $nombre : puerto $puerto no responde." -ForegroundColor Yellow
        $script:sslResumen += "[!]  $nombre | Puerto $puerto | NO VERIFICADO"
    }
}

function Resumen-SSL {
    Separador
    Write-Host "   RESUMEN DE VERIFICACION SSL/TLS" -ForegroundColor White
    Separador
    Write-Host "  Dominio: www.$dominioSSL"
    Write-Host "  Certificados en: $certStore"
    Separador
    if ($script:sslResumen.Count -eq 0) {
        Write-Host "  (Sin verificaciones registradas aun)" -ForegroundColor Yellow
    } else {
        foreach ($linea in $script:sslResumen) {
            if ($linea -match '^\[OK\]') { Write-Host "  $linea" -ForegroundColor Green }
            else { Write-Host "  $linea" -ForegroundColor Yellow }
        }
    }
    Separador
    Write-Host "  Estado actual de puertos:" -ForegroundColor White
    foreach ($sp in @("IIS:443","IIS-FTP:21","Apache:443","Nginx:443","Tomcat:443")) {
        $s = $sp.Split(':')[0]; $p = [int]$sp.Split(':')[1]
        $c = Test-NetConnection -ComputerName localhost -Port $p -WarningAction SilentlyContinue
        if ($c.TcpTestSucceeded) { Write-Host "  $s puerto $p -> ESCUCHANDO" -ForegroundColor Green }
        else { Write-Host "  $s puerto $p -> NO RESPONDE" -ForegroundColor Yellow }
    }
    Separador
}

function SSL-Todos {
    Write-Host "[INFO] Aplicando SSL a todos los servicios instalados..." -ForegroundColor Cyan
    if (Get-Service W3SVC -ErrorAction SilentlyContinue) { Habilitar-SSL-IIS }
    $apacheDir = @("C:\tools\Apache24","C:\Apache24") `
        | Where-Object { Test-Path "$_\conf\httpd.conf" } | Select-Object -First 1
    if ($apacheDir) { Habilitar-SSL-Apache }
    $nginxExe = Get-ChildItem -Path "C:\tools" -Filter "nginx.exe" `
        -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($nginxExe) { Habilitar-SSL-Nginx }
    $tomcatDir = Get-ChildItem "C:\ProgramData\chocolatey\lib\Tomcat\tools" `
        -Directory -Filter "apache-tomcat*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($tomcatDir) { Habilitar-SSL-Tomcat }
    if (Get-Service FTPSVC -ErrorAction SilentlyContinue) { Habilitar-SSL-FTP }
    Resumen-SSL
}
