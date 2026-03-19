#!/bin/sh
# =============================================================================
# FunSSL.sh — SSL/TLS para HTTP y FTP | Practica 7 | Alpine Linux
# =============================================================================
# Requiere: FunGENERALES.sh cargado previamente

SSL_DIR="/etc/ssl/reprobados"
DOMINIO="reprobados.com"
CERT="${SSL_DIR}/reprobados.crt"
KEY="${SSL_DIR}/reprobados.key"

# Archivo de resumen de verificaciones
SSL_RESUMEN="/tmp/ssl_resumen.txt"

# =============================================================================
# GENERAR CERTIFICADO AUTOFIRMADO COMPARTIDO
# =============================================================================

_generar_cert() {
    apk add --no-interactive openssl >/dev/null 2>&1
    mkdir -p "$SSL_DIR"
    chmod 700 "$SSL_DIR"

    if [ -f "$CERT" ] && [ -f "$KEY" ]; then
        ok "Certificado ya existe: $CERT"; return 0
    fi

    info "Generando certificado autofirmado para $DOMINIO ..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$KEY" \
        -out "$CERT" \
        -subj "/C=MX/ST=Michoacan/L=Morelia/O=reprobados/OU=TI/CN=www.${DOMINIO}" \
        -addext "subjectAltName=DNS:${DOMINIO},DNS:www.${DOMINIO},DNS:ftp.${DOMINIO}" \
        >/dev/null 2>&1

    chmod 600 "$KEY"
    chmod 644 "$CERT"
    ok "Certificado generado:"
    ok "  CERT: $CERT"
    ok "  KEY:  $KEY"
}

# =============================================================================
# SSL PARA APACHE2
# =============================================================================

habilitar_ssl_apache() {
    info "Habilitando SSL en Apache2 ..."
    _generar_cert

    apk add --no-interactive apache2-ssl >/dev/null 2>&1

    _ssl_conf="/etc/apache2/conf.d/ssl.conf"
    cat > "$_ssl_conf" <<CONF
LoadModule ssl_module modules/mod_ssl.so
LoadModule rewrite_module modules/mod_rewrite.so

Listen 443

# ── Redireccion HTTP -> HTTPS (HSTS basico) ────────────────────────────────
<VirtualHost *:80>
    ServerName www.${DOMINIO}
    RewriteEngine On
    RewriteRule ^(.*)$ https://%{HTTP_HOST}$1 [R=301,L]
</VirtualHost>

# ── VirtualHost HTTPS ──────────────────────────────────────────────────────
<VirtualHost *:443>
    ServerName www.${DOMINIO}
    DocumentRoot /var/www/localhost/htdocs

    SSLEngine on
    SSLCertificateFile    ${CERT}
    SSLCertificateKeyFile ${KEY}

    SSLProtocol all -SSLv2 -SSLv3
    SSLCipherSuite HIGH:!aNULL:!MD5

    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
</VirtualHost>
CONF

    grep -q "mod_headers" "$APACHE_CONF" \
        || echo "LoadModule headers_module modules/mod_headers.so" >> "$APACHE_CONF"

    abrir_firewall 443
    rc-service apache2 restart 2>/dev/null || true
    ok "Apache2: SSL habilitado en puerto 443. Redireccion HTTP->HTTPS activa."
}

# =============================================================================
# SSL PARA NGINX
# =============================================================================

habilitar_ssl_nginx() {
    info "Habilitando SSL en NGINX ..."
    _generar_cert

    mkdir -p /etc/nginx/conf.d
    _ssl_conf="/etc/nginx/conf.d/ssl.conf"

    cat > "$_ssl_conf" <<CONF
# ── Redireccion HTTP -> HTTPS ──────────────────────────────────────────────
server {
    listen 80;
    server_name ${DOMINIO} www.${DOMINIO};
    return 301 https://\$host\$request_uri;
}

# ── VirtualHost HTTPS ──────────────────────────────────────────────────────
server {
    listen 443 ssl;
    server_name ${DOMINIO} www.${DOMINIO};
    root ${NGINX_WEBROOT:-/var/www/nginx};
    index index.html;

    ssl_certificate     ${CERT};
    ssl_certificate_key ${KEY};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:10m;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
}
CONF

    grep -q "conf.d" "$NGINX_CONF" \
        || sed -i "/http {/a\\    include /etc/nginx/conf.d/*.conf;" "$NGINX_CONF"

    abrir_firewall 443
    rc-service nginx reload 2>/dev/null || rc-service nginx restart 2>/dev/null || true
    ok "NGINX: SSL habilitado en puerto 443. Redireccion HTTP->HTTPS activa."
}

# =============================================================================
# SSL PARA TOMCAT
# =============================================================================

habilitar_ssl_tomcat() {
    _tver="${1:-tomcat}"   # "tomcat9" o "tomcat10" o "tomcat"
    _base="${TOMCAT_BASE:-/opt/tomcat}"
    _sx="${_base}/conf/server.xml"

    info "Habilitando SSL en Tomcat ($_tver) ..."

    [ ! -f "$_sx" ] && { error "No encontre server.xml en $_base"; return 1; }

    _generar_cert

    # Crear keystore PKCS12 a partir del cert/key PEM
    _ks="${_base}/conf/reprobados.p12"
    openssl pkcs12 -export \
        -in "$CERT" -inkey "$KEY" \
        -out "$_ks" \
        -name reprobados \
        -passout pass:reprobados123 >/dev/null 2>&1
    chmod 600 "$_ks"
    ok "Keystore PKCS12 creado: $_ks"

    # Agregar conector HTTPS en server.xml (sin duplicar)
    if grep -q "port=\"443\"" "$_sx"; then
        aviso "Ya existe un conector en puerto 443 en server.xml."
    else
        cp "$_sx" "${_sx}.bak.$(date +%s)"
        # Insertar antes del cierre </Service>
        sed -i "s|</Service>|    <Connector port=\"443\" protocol=\"org.apache.coyote.http11.Http11NioProtocol\"\n               SSLEnabled=\"true\" scheme=\"https\" secure=\"true\"\n               keystoreFile=\"${_ks}\" keystorePass=\"reprobados123\"\n               keystoreType=\"PKCS12\" clientAuth=\"false\"\n               sslProtocol=\"TLS\" />\n</Service>|" "$_sx"
    fi

    abrir_firewall 443
    rc-service tomcat restart 2>/dev/null || true
    ok "Tomcat: SSL habilitado en puerto 443."
}

# =============================================================================
# SSL PARA VSFTPD (FTPS)  — delegado a FunFTP.sh
# =============================================================================
# habilitar_ssl_vsftpd ya esta definida en FunFTP.sh
# Esta entrada es solo un alias de conveniencia si se llama desde FunSSL

# =============================================================================
# VERIFICACION AUTOMATIZADA POR SERVICIO
# =============================================================================

verificar_ssl_servicio() {
    _nombre="$1"
    _puerto="${2:-443}"
    _es_ftp="${3:-false}"

    printf "\n"
    info "Verificando SSL en $_nombre (puerto $_puerto) ..."

    apk add --no-interactive openssl >/dev/null 2>&1

    # Primero verificar que el puerto este abierto
    if ! nc -z -w 3 127.0.0.1 "$_puerto" 2>/dev/null; then
        aviso "$_nombre: puerto $_puerto no responde."
        printf "%s | Puerto %-5s | [!] PUERTO CERRADO\n" "$_nombre" "$_puerto" >> "$SSL_RESUMEN"
        return
    fi

    if [ "$_es_ftp" = "true" ]; then
        # Para FTPS: verificar que el certificado existe y el puerto responde
        if [ -f "/etc/vsftpd/ssl/vsftpd.pem" ]; then
            _expiry=$(openssl x509 -enddate -noout -in /etc/vsftpd/ssl/vsftpd.pem 2>/dev/null | sed 's/notAfter=//')
            _cn=$(openssl x509 -subject -noout -in /etc/vsftpd/ssl/vsftpd.pem 2>/dev/null | grep -oE "CN=[^,/]+" | head -1)
            ok "$_nombre: FTPS configurado. Puerto $_puerto activo."
            ok "  CN: $(echo "$_cn" | cut -d= -f2)"
            ok "  Vence: $_expiry"
            _estado="[OK] FTPS ACTIVO"
        else
            aviso "$_nombre: certificado FTPS no encontrado."
            _estado="[!] CERT NO ENCONTRADO"
        fi
    else
        # Para HTTPS: conectar con timeout de 5 segundos
        _resultado=$(echo "Q" | timeout 5 openssl s_client \
            -connect "127.0.0.1:${_puerto}" \
            -servername "www.${DOMINIO}" 2>&1)

        if echo "$_resultado" | grep -q "CONNECTED"; then
            _cn=$(echo "$_resultado" | grep "subject=" | grep -oE "CN=[^,/]+" | head -1)
            _expiry=$(echo "$_resultado" | grep "notAfter=" | head -1 | sed 's/notAfter=//')
            ok "$_nombre: conexion SSL exitosa."
            ok "  CN: $(echo "$_cn" | cut -d= -f2)"
            ok "  Vence: $_expiry"
            _estado="[OK] SSL ACTIVO"
        else
            aviso "$_nombre: no se pudo verificar SSL en puerto $_puerto."
            _estado="[!] SSL NO VERIFICADO"
        fi
    fi

    printf "%s | Puerto %-5s | %s\n" "$_nombre" "$_puerto" "$_estado" >> "$SSL_RESUMEN"
}

# =============================================================================
# RESUMEN FINAL DE VERIFICACIONES SSL
# =============================================================================

resumen_ssl() {
    printf "\n"
    printf "╔══════════════════════════════════════════════════════════╗\n"
    printf "║          RESUMEN DE VERIFICACION SSL/TLS                 ║\n"
    printf "╠══════════════════════════════════════════════════════════╣\n"
    printf "║  Dominio objetivo: %-38s║\n" "www.${DOMINIO}"
    printf "║  Certificado:      %-38s║\n" "$CERT"
    printf "╠══════════════════════════════════════════════════════════╣\n"

    if [ ! -f "$SSL_RESUMEN" ] || [ ! -s "$SSL_RESUMEN" ]; then
        printf "║  (Sin verificaciones registradas aun)                    ║\n"
    else
        while IFS= read -r _linea; do
            printf "║  %-56s║\n" "$_linea"
        done < "$SSL_RESUMEN"
    fi

    printf "╠══════════════════════════════════════════════════════════╣\n"

    # Verificacion en vivo de todos los servicios comunes
    printf "║  Verificacion en vivo:                                   ║\n"
    for _srv_puerto in "apache2:443" "nginx:443" "tomcat:443" "vsftpd:21"; do
        _s=$(echo "$_srv_puerto" | cut -d: -f1)
        _p=$(echo "$_srv_puerto" | cut -d: -f2)
        if nc -z 127.0.0.1 "$_p" 2>/dev/null; then
            printf "║  %-12s puerto %-5s -> ${VERDE}ESCUCHANDO${RESET}                  ║\n" "$_s" "$_p"
        else
            printf "║  %-12s puerto %-5s -> ${AMARILLO}NO RESPONDE${RESET}                 ║\n" "$_s" "$_p"
        fi
    done

    printf "╚══════════════════════════════════════════════════════════╝\n\n"
}

# ── Preguntar SSL e invocar funcion correcta ──────────────────────────────────
preguntar_ssl() {
    _tipo="$1"; _paquete="${2:-tomcat}"
    printf "\n"
    printf "¿Desea activar SSL en este servicio? [S/N]: "
    read -r _R
    case "$_R" in
        [sS])
            case "$_tipo" in
                apache)  habilitar_ssl_apache;               verificar_ssl_servicio "apache2" "443"        ;;
                nginx)   habilitar_ssl_nginx;                verificar_ssl_servicio "nginx"   "443"        ;;
                tomcat)  habilitar_ssl_tomcat "$_paquete";   verificar_ssl_servicio "tomcat"  "443"        ;;
                vsftpd)  habilitar_ssl_vsftpd;               verificar_ssl_servicio "vsftpd"  "21" "true"  ;;
            esac
            ;;
        *) aviso "SSL omitido para $_tipo." ;;
    esac
}

# ── Aplicar SSL a todos los servicios instalados ──────────────────────────────
ssl_todos() {
    info "Aplicando SSL a todos los servicios instalados ..."
    > "$SSL_RESUMEN"   # Limpiar resumen previo

    apk info -e apache2 >/dev/null 2>&1 && {
        habilitar_ssl_apache
        verificar_ssl_servicio "apache2" "443"
    }
    apk info -e nginx >/dev/null 2>&1 && {
        habilitar_ssl_nginx
        verificar_ssl_servicio "nginx" "443"
    }
    [ -f "${TOMCAT_BASE}/conf/server.xml" ] && {
        habilitar_ssl_tomcat "tomcat"
        verificar_ssl_servicio "tomcat" "443"
    }
    apk info -e vsftpd >/dev/null 2>&1 && {
        habilitar_ssl_vsftpd
        verificar_ssl_servicio "vsftpd" "21" "true"
    }

    resumen_ssl
}