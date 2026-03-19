#!/bin/sh
# =============================================================================
# FunFTP.sh — Servidor vsftpd con repositorio HTTP | Practica 7 | Alpine
# =============================================================================
# Requiere: FunGENERALES.sh cargado previamente

FTP_ROOT="/srv/ftp"
FTP_REPO="/srv/ftp/http"          # Repositorio de instaladores
VSFTPD_CONF="/etc/vsftpd/vsftpd.conf"
SSL_CERT_DIR="/etc/vsftpd/ssl"

# =============================================================================
# INSTALACION Y CONFIGURACION BASE
# =============================================================================

aplicarConfiguracion() {
    info "Configurando vsftpd ..."

    # Grupos
    for grupo in reprobados recursadores; do
        getent group "$grupo" >/dev/null 2>&1 || addgroup "$grupo"
    done

    # Directorios base
    mkdir -p "$FTP_ROOT/general"
    mkdir -p "$FTP_ROOT/reprobados"
    mkdir -p "$FTP_ROOT/recursadores"
    chmod 755 "$FTP_ROOT"
    chmod 777 "$FTP_ROOT/general"
    chmod 770 "$FTP_ROOT/reprobados"
    chmod 770 "$FTP_ROOT/recursadores"
    chown ftp:ftp "$FTP_ROOT/general" 2>/dev/null || true
    chown root:reprobados "$FTP_ROOT/reprobados"
    chown root:recursadores "$FTP_ROOT/recursadores"

    # Repositorio HTTP para la practica 7
    _crear_estructura_repo

    mkdir -p "$(dirname $VSFTPD_CONF)"
    cat > "$VSFTPD_CONF" <<'CONF'
listen=YES
anonymous_enable=YES
local_enable=YES
write_enable=YES
local_umask=022
anon_root=/srv/ftp/general
anon_upload_enable=NO
anon_mkdir_write_enable=NO
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
allow_writeable_chroot=YES
secure_chroot_dir=/var/empty
pam_service_name=login
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=50000
seccomp_sandbox=NO
CONF

    killall vsftpd 2>/dev/null; sleep 1
    vsftpd "$VSFTPD_CONF" &
    sleep 1
    ok "vsftpd configurado e iniciado."
}

# ── Crear estructura del repositorio FTP ─────────────────────────────────────
_crear_estructura_repo() {
    info "Preparando estructura del repositorio FTP (/srv/ftp/http) ..."

    for srv in Apache Nginx Tomcat; do
        mkdir -p "$FTP_REPO/Linux/$srv"
    done

    # Crear archivos placeholder + sha256 si no existen ya instaladores
    for srv in Apache Nginx Tomcat; do
        _dir="$FTP_REPO/Linux/$srv"
        _nombre_lower=$(echo "$srv" | tr '[:upper:]' '[:lower:]')

        # Solo crear placeholder si no hay ningun instalador real
        if [ -z "$(ls "$_dir"/*.apk 2>/dev/null)$(ls "$_dir"/*.tar.gz 2>/dev/null)" ]; then
            _fake="${_dir}/${_nombre_lower}_placeholder.apk"
            echo "# Coloca aqui el instalador real de $srv (.apk o .tar.gz)" > "$_fake"
            sha256sum "$_fake" > "${_fake}.sha256"
            aviso "Placeholder creado en $_dir — reemplaza con el instalador real."
        fi
    done

    chmod -R 755 "$FTP_REPO"
    ok "Estructura del repositorio lista en $FTP_REPO"
}

# =============================================================================
# SSL/FTPS EN VSFTPD
# =============================================================================

habilitar_ssl_vsftpd() {
    info "Configurando FTPS (SSL/TLS) en vsftpd ..."
    apk add --no-interactive openssl >/dev/null 2>&1

    mkdir -p "$SSL_CERT_DIR"
    _cert="$SSL_CERT_DIR/vsftpd.pem"
    _key="$SSL_CERT_DIR/vsftpd.key"

    if [ ! -f "$_cert" ]; then
        info "Generando certificado autofirmado para vsftpd ..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$_key" \
            -out "$_cert" \
            -subj "/C=MX/ST=Michoacan/L=Morelia/O=reprobados/CN=ftp.reprobados.com" \
            >/dev/null 2>&1
        chmod 600 "$_key" "$_cert"
        ok "Certificado generado: $_cert"
    else
        ok "Certificado ya existe: $_cert"
    fi

    # Agregar directivas SSL al vsftpd.conf (sin duplicar)
    for _linea in \
        "ssl_enable=YES" \
        "allow_anon_ssl=NO" \
        "force_local_data_ssl=YES" \
        "force_local_logins_ssl=YES" \
        "ssl_tlsv1=YES" \
        "ssl_sslv2=NO" \
        "ssl_sslv3=NO" \
        "require_ssl_reuse=NO" \
        "ssl_ciphers=HIGH" \
        "rsa_cert_file=$_cert" \
        "rsa_private_key_file=$_key"
    do
        _clave=$(echo "$_linea" | cut -d= -f1)
        if grep -q "^${_clave}=" "$VSFTPD_CONF" 2>/dev/null; then
            sed -i "s|^${_clave}=.*|${_linea}|" "$VSFTPD_CONF"
        else
            echo "$_linea" >> "$VSFTPD_CONF"
        fi
    done

    killall vsftpd 2>/dev/null; sleep 1
    vsftpd "$VSFTPD_CONF" &
    sleep 1
    ok "FTPS habilitado. Canal de control y datos cifrados."
}

# =============================================================================
# GESTION DE USUARIOS
# =============================================================================

registrarUsuarios() {
    # Espera variables: no_users (numero), names (csv), passwords (csv)
    _i=1
    _IFS_BAK="$IFS"
    IFS=','
    set -- $names
    _nombres="$@"
    set -- $passwords
    _claves="$@"
    IFS="$_IFS_BAK"

    _idx=1
    for _usr in $_nombres; do
        _usr=$(echo "$_usr" | tr -d ' ')
        _pwd=$(echo "$_claves" | cut -d',' -f"$_idx" | tr -d ' ')
        _idx=$((_idx+1))

        if id "$_usr" >/dev/null 2>&1; then
            aviso "El usuario $_usr ya existe."
            continue
        fi

        printf "Grupo para %s (reprobados/recursadores): " "$_usr"
        read -r _grupo
        while [ "$_grupo" != "reprobados" ] && [ "$_grupo" != "recursadores" ]; do
            printf "Grupo invalido. Ingresa reprobados o recursadores: "
            read -r _grupo
        done

        adduser -D -h "$FTP_ROOT/$_usr" -s /bin/sh "$_usr" 2>/dev/null
        echo "${_usr}:${_pwd}" | chpasswd 2>/dev/null
        addgroup "$_usr" "$_grupo" 2>/dev/null

        _montar_usuario "$_usr" "$_grupo"
        ok "Usuario $_usr creado en grupo $_grupo."
        _i=$((_i+1))
    done
}

_montar_usuario() {
    _usr="$1"; _grp="$2"
    _udir="$FTP_ROOT/$_usr"

    mkdir -p "$_udir/general" "$_udir/$_grp" "$_udir/$_usr"
    chown "$_usr:$_usr" "$_udir" "$_udir/$_usr"
    chmod 755 "$_udir"; chmod 750 "$_udir/$_usr"

    mount --bind "$FTP_ROOT/general" "$_udir/general" 2>/dev/null   || true
    mount --bind "$FTP_ROOT/$_grp"   "$_udir/$_grp"   2>/dev/null   || true
    ok "Bind mounts aplicados para $_usr."
}

eliminarUsuario() {
    _usr="$1"
    if ! id "$_usr" >/dev/null 2>&1; then
        error "El usuario $_usr no existe."; return 1
    fi
    umount "$FTP_ROOT/$_usr/general"    2>/dev/null || true
    umount "$FTP_ROOT/$_usr/reprobados" 2>/dev/null || true
    umount "$FTP_ROOT/$_usr/recursadores" 2>/dev/null || true
    deluser "$_usr" 2>/dev/null
    rm -rf "$FTP_ROOT/$_usr"
    ok "Usuario $_usr eliminado."
}

consultarAlumnos() {
    printf "\n  Usuarios FTP del sistema:\n"
    printf "  %-20s %-15s\n" "USUARIO" "GRUPO(S)"
    printf "  %-20s %-15s\n" "-------" "--------"
    for _grp in reprobados recursadores; do
        if getent group "$_grp" >/dev/null 2>&1; then
            _miembros=$(getent group "$_grp" | cut -d: -f4 | tr ',' ' ')
            for _usr in $_miembros; do
                [ -n "$_usr" ] && printf "  %-20s %-15s\n" "$_usr" "$_grp"
            done
        fi
    done
    printf "\n"
}

moverGrupoUsuario() {
    # Espera variables: names (usuario), groups (nuevo grupo sin prefijo)
    _usr="$names"; _nuevo="$groups"

    if ! id "$_usr" >/dev/null 2>&1; then
        error "El usuario $_usr no existe."; return 1
    fi

    if [ "$_nuevo" = "reprobados" ]; then _viejo="recursadores"
    else _viejo="reprobados"; fi

    delgroup "$_usr" "$_viejo" 2>/dev/null || true
    addgroup "$_usr" "$_nuevo" 2>/dev/null

    umount "$FTP_ROOT/$_usr/$_viejo" 2>/dev/null || true
    rmdir  "$FTP_ROOT/$_usr/$_viejo" 2>/dev/null || true
    mkdir -p "$FTP_ROOT/$_usr/$_nuevo"
    mount --bind "$FTP_ROOT/$_nuevo" "$FTP_ROOT/$_usr/$_nuevo" 2>/dev/null || true

    chown "$_usr:$_nuevo" "$FTP_ROOT/$_usr/$_usr" 2>/dev/null || true
    ok "$_usr movido de $_viejo a $_nuevo."
}

# =============================================================================
# GESTION DE GRUPOS
# =============================================================================

registrarGrupo() {
    _grp="$1"
    if getent group "$_grp" >/dev/null 2>&1; then
        aviso "El grupo $_grp ya existe."; return
    fi
    addgroup "$_grp"
    mkdir -p "$FTP_ROOT/$_grp"
    chmod 770 "$FTP_ROOT/$_grp"
    ok "Grupo $_grp creado."
}

eliminarGrupo() {
    _grp="$1"
    if ! getent group "$_grp" >/dev/null 2>&1; then
        error "El grupo $_grp no existe."; return 1
    fi
    delgroup "$_grp" 2>/dev/null
    ok "Grupo $_grp eliminado del sistema."
    aviso "Directorio $FTP_ROOT/$_grp conservado. Elimina manualmente si lo deseas."
}

consultarGrupos() {
    printf "\n  Grupos FTP:\n"
    printf "  %-20s %s\n" "GRUPO" "MIEMBROS"
    printf "  %-20s %s\n" "-----" "--------"
    for _g in reprobados recursadores; do
        if getent group "$_g" >/dev/null 2>&1; then
            _m=$(getent group "$_g" | cut -d: -f4)
            printf "  %-20s %s\n" "$_g" "${_m:-(sin miembros)}"
        fi
    done
    printf "\n"
}
