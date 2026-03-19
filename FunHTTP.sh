#!/bin/sh
# =============================================================================
# FunHTTP.sh — Instalacion HTTP (Apache2 / Nginx / Tomcat) | Practica 7 | Alpine
# =============================================================================
# Requiere: FunGENERALES.sh cargado previamente

APACHE_CONF="/etc/apache2/httpd.conf"
APACHE_WEBROOT="/var/www/localhost/htdocs"
NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_WEBROOT="/var/www/nginx"
TOMCAT_BASE="/opt/tomcat"

# =============================================================================
# APACHE2
# =============================================================================

instalar_apache() {
    _version="$1"; _puerto="$2"

    printf "\n========================================\n"
    printf "       INSTALACION DE APACHE2           \n"
    printf "========================================\n\n"

    info "Instalando apache2 ..."
    apk add --no-interactive apache2 >/dev/null 2>&1
    if ! apk info -e apache2 >/dev/null 2>&1; then
        error "Fallo la instalacion de Apache2."; return 1
    fi
    ok "Apache2 instalado."

    crear_usuario_servicio "apache" "$APACHE_WEBROOT"
    _apache_puerto "$_puerto"
    _apache_seguridad
    _apache_metodos
    crear_pagina_web "$APACHE_WEBROOT" "Apache HTTP Server" "$_version" "$_puerto"

    rc-service apache2 start  2>/dev/null || true
    rc-update add apache2 default 2>/dev/null || true

    ok "Apache2 corriendo en puerto $_puerto"
    ok "Prueba: curl -I http://localhost:$_puerto"
}

_apache_puerto() {
    _p="$1"
    [ ! -f "$APACHE_CONF" ] && { error "No encontre $APACHE_CONF"; return 1; }
    cp "$APACHE_CONF" "${APACHE_CONF}.bak.$(date +%s)"
    grep -q "^Listen " "$APACHE_CONF" \
        && sed -i "s/^Listen .*/Listen ${_p}/" "$APACHE_CONF" \
        || echo "Listen ${_p}" >> "$APACHE_CONF"
    abrir_firewall "$_p"
    rc-service apache2 restart 2>/dev/null || true
    ok "Apache2: puerto -> $_p"
}

_apache_seguridad() {
    grep -q "^ServerTokens" "$APACHE_CONF" \
        && sed -i "s/^ServerTokens.*/ServerTokens Prod/" "$APACHE_CONF" \
        || echo "ServerTokens Prod" >> "$APACHE_CONF"
    grep -q "^ServerSignature" "$APACHE_CONF" \
        && sed -i "s/^ServerSignature.*/ServerSignature Off/" "$APACHE_CONF" \
        || echo "ServerSignature Off" >> "$APACHE_CONF"
    ok "Apache2: version ocultada en encabezados."
}

_apache_metodos() {
    mkdir -p /etc/apache2/conf.d
    cat > /etc/apache2/conf.d/seguridad-extra.conf <<'EOF'
<LimitExcept GET POST HEAD OPTIONS>
    Deny from all
</LimitExcept>
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
EOF
    grep -q "mod_headers" "$APACHE_CONF" \
        || echo "LoadModule headers_module modules/mod_headers.so" >> "$APACHE_CONF"
    ok "Apache2: security headers aplicados."
}

# =============================================================================
# NGINX
# =============================================================================

instalar_nginx() {
    _version="$1"; _puerto="$2"

    printf "\n========================================\n"
    printf "         INSTALACION DE NGINX           \n"
    printf "========================================\n\n"

    info "Instalando nginx ..."
    apk add --no-interactive nginx >/dev/null 2>&1
    if ! apk info -e nginx >/dev/null 2>&1; then
        error "Fallo la instalacion de NGINX."; return 1
    fi
    ok "NGINX instalado."

    mkdir -p "$NGINX_WEBROOT"
    crear_usuario_servicio "nginx" "$NGINX_WEBROOT"
    _nginx_puerto "$_puerto"
    _nginx_seguridad
    _nginx_metodos
    crear_pagina_web "$NGINX_WEBROOT" "NGINX" "$_version" "$_puerto"

    rc-service nginx start 2>/dev/null || true
    rc-update add nginx default 2>/dev/null || true

    ok "NGINX corriendo en puerto $_puerto"
    ok "Prueba: curl -I http://localhost:$_puerto"
}

_nginx_puerto() {
    _p="$1"
    [ ! -f "$NGINX_CONF" ] && { error "No encontre $NGINX_CONF"; return 1; }
    cp "$NGINX_CONF" "${NGINX_CONF}.bak.$(date +%s)"
    sed -i "s/listen[[:space:]]*[0-9]*/listen $_p/g" "$NGINX_CONF"
    abrir_firewall "$_p"
    rc-service nginx reload 2>/dev/null || rc-service nginx restart 2>/dev/null || true
    ok "NGINX: puerto -> $_p"
}

_nginx_seguridad() {
    grep -q "server_tokens" "$NGINX_CONF" \
        && sed -i "s/.*server_tokens.*/    server_tokens off;/" "$NGINX_CONF" \
        || sed -i "/http {/a\\    server_tokens off;" "$NGINX_CONF"
    ok "NGINX: version ocultada."
}

_nginx_metodos() {
    mkdir -p /etc/nginx/conf.d
    cat > /etc/nginx/conf.d/seguridad-extra.conf <<'EOF'
if ($request_method !~ ^(GET|POST|HEAD)$) { return 405; }
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
EOF
    grep -q "conf.d" "$NGINX_CONF" \
        || sed -i "/http {/a\\    include /etc/nginx/conf.d/*.conf;" "$NGINX_CONF"
    ok "NGINX: security headers aplicados."
}

# =============================================================================
# APACHE TOMCAT
# =============================================================================

instalar_tomcat() {
    _version="$1"; _puerto="$2"

    printf "\n========================================\n"
    printf "      INSTALACION DE APACHE TOMCAT      \n"
    printf "========================================\n\n"

    info "Instalando dependencias (openjdk17-jre, curl, tar) ..."
    apk add --no-interactive openjdk17-jre curl tar >/dev/null 2>&1
    ok "Dependencias instaladas."

    _mayor=$(echo "$_version" | cut -d. -f1)
    _url="https://downloads.apache.org/tomcat/tomcat-${_mayor}/v${_version}/bin/apache-tomcat-${_version}.tar.gz"
    _tmp="/tmp/tomcat-${_version}.tar.gz"

    info "Descargando Apache Tomcat $_version ..."
    if ! curl -fsSL --progress-bar "$_url" -o "$_tmp"; then
        error "No se pudo descargar Tomcat desde: $_url"; return 1
    fi

    info "Extrayendo en $TOMCAT_BASE ..."
    mkdir -p "$TOMCAT_BASE"
    tar -xzf "$_tmp" -C "$TOMCAT_BASE" --strip-components=1
    rm -f "$_tmp"
    ok "Tomcat extraido en $TOMCAT_BASE"

    crear_usuario_servicio "tomcat" "$TOMCAT_BASE"
    chown -R tomcat:tomcat "$TOMCAT_BASE" 2>/dev/null || true
    chmod -R 750 "$TOMCAT_BASE"

    _tomcat_puerto "$_puerto"
    _tomcat_seguridad
    mkdir -p "${TOMCAT_BASE}/webapps/ROOT"
    crear_pagina_web "${TOMCAT_BASE}/webapps/ROOT" "Apache Tomcat" "$_version" "$_puerto"
    _tomcat_openrc

    rc-service tomcat start 2>/dev/null || true
    rc-update add tomcat default 2>/dev/null || true

    ok "Tomcat $_version corriendo en puerto $_puerto"
    ok "Prueba: curl -I http://localhost:$_puerto"
}

_tomcat_puerto() {
    _p="$1"
    _sx="${TOMCAT_BASE}/conf/server.xml"
    [ ! -f "$_sx" ] && { error "No encontre server.xml"; return 1; }
    cp "$_sx" "${_sx}.bak.$(date +%s)"
    sed -i "s/port=\"[0-9]*\" protocol=\"HTTP\/1.1\"/port=\"${_p}\" protocol=\"HTTP\/1.1\"/" "$_sx"
    abrir_firewall "$_p"
    ok "Tomcat: puerto -> $_p"
}

_tomcat_seguridad() {
    _sx="${TOMCAT_BASE}/conf/server.xml"
    sed -i 's/protocol="HTTP\/1.1"/protocol="HTTP\/1.1" server="Servidor-Web"/' "$_sx"
    ok "Tomcat: version ocultada."
}

_tomcat_openrc() {
    cat > /etc/init.d/tomcat <<INIT
#!/sbin/openrc-run
name="tomcat"
description="Apache Tomcat"
JAVA_HOME=\$(dirname \$(dirname \$(readlink -f \$(which java))))
CATALINA_HOME="${TOMCAT_BASE}"
pidfile="/run/tomcat.pid"
depend() { need net; }
start() {
    ebegin "Iniciando Tomcat"
    export JAVA_HOME=\$JAVA_HOME CATALINA_HOME=\$CATALINA_HOME
    start-stop-daemon --start --background --user tomcat \
        --pidfile \$pidfile --make-pidfile \
        --exec \${CATALINA_HOME}/bin/startup.sh
    eend \$?
}
stop() {
    ebegin "Deteniendo Tomcat"
    start-stop-daemon --stop --pidfile \$pidfile
    eend \$?
}
INIT
    chmod +x /etc/init.d/tomcat
    ok "Servicio OpenRC de Tomcat creado."
}

# ── Seleccion de version de Tomcat (sin apk, se descarga manualmente) ─────────
seleccionar_version_tomcat() {
    printf "\n  Versiones disponibles de Apache Tomcat:\n"
    printf "  ----------------------------------------\n"
    printf "  1) 10.1.36  <- latest  (Jakarta EE 10)\n"
    printf "  2) 9.0.106  <- LTS     (Servlet 4.0)\n"
    printf "  3) Ingresar version manualmente\n"
    printf "  ----------------------------------------\n\n"

    while true; do
        printf "  Elige una version [1-3]: " >&2
        read -r _op
        case "$_op" in
            1) VERSION_ELEGIDA="10.1.36"; break ;;
            2) VERSION_ELEGIDA="9.0.106";  break ;;
            3)
                printf "  Version exacta (ej: 10.1.36): " >&2
                read -r VERSION_ELEGIDA
                case "$VERSION_ELEGIDA" in
                    [0-9]*.[0-9]*.[0-9]*) break ;;
                    *) aviso "Formato invalido. Ejemplo: 10.1.36" >&2 ;;
                esac ;;
            *) aviso "Elige entre 1 y 3." >&2 ;;
        esac
    done
    ok "Seleccionaste Tomcat: $VERSION_ELEGIDA"
}

# =============================================================================
# INSTALAR DESDE BINARIO (opcion FTP)
# =============================================================================

instalar_desde_ftp() {
    _archivo="$1"   # ruta local del instalador descargado
    _servicio="$2"  # nombre del servicio (apache, nginx, tomcat)

    info "Instalando $_servicio desde archivo: $_archivo ..."

    case "$_archivo" in
        *.apk)
            apk add --allow-untrusted "$_archivo" >/dev/null 2>&1 \
                && ok "$_servicio instalado desde .apk" \
                || { error "Fallo la instalacion del .apk"; return 1; }
            ;;
        *.tar.gz)
            case "$_servicio" in
                tomcat*|Tomcat*)
                    mkdir -p "$TOMCAT_BASE"
                    tar -xzf "$_archivo" -C "$TOMCAT_BASE" --strip-components=1 \
                        && ok "Tomcat extraido en $TOMCAT_BASE" \
                        || { error "Fallo la extraccion del tar.gz"; return 1; }
                    ;;
                *)
                    error "Instalacion manual de tar.gz no soportada para $_servicio."
                    return 1 ;;
            esac
            ;;
        *)
            error "Formato de instalador no reconocido: $_archivo"
            return 1 ;;
    esac
}

# =============================================================================
# ESTADO Y DESINSTALACION
# =============================================================================

mostrar_servicios_http() {
    printf "\n========================================\n"
    printf "       SERVICIOS HTTP INSTALADOS        \n"
    printf "========================================\n"
    _ok=0

    if rc-service apache2 status >/dev/null 2>&1; then
        _p=$(grep -E "^Listen " "$APACHE_CONF" 2>/dev/null | awk '{print $2}')
        printf "  Apache2 | ACTIVO | Puerto: %s\n" "${_p:-desconocido}"
        _ok=1
    fi
    if rc-service nginx status >/dev/null 2>&1; then
        _p=$(grep -oE 'listen [0-9]+' "$NGINX_CONF" 2>/dev/null | head -1 | awk '{print $2}')
        printf "  NGINX   | ACTIVO | Puerto: %s\n" "${_p:-desconocido}"
        _ok=1
    fi
    if rc-service tomcat status >/dev/null 2>&1; then
        _p=$(grep -oE 'port="[0-9]+" protocol="HTTP' \
             "${TOMCAT_BASE}/conf/server.xml" 2>/dev/null \
             | grep -oE '[0-9]+' | head -1)
        printf "  Tomcat  | ACTIVO | Puerto: %s\n" "${_p:-desconocido}"
        _ok=1
    fi

    [ "$_ok" -eq 0 ] && aviso "Ningun servicio HTTP activo detectado."
    printf "========================================\n\n"
}
