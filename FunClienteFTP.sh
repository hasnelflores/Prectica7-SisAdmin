#!/bin/sh
# =============================================================================
# FunClienteFTP.sh — Cliente FTP dinamico + validacion de integridad SHA256
# Practica 7 | Alpine Linux
# =============================================================================
# Requiere: FunGENERALES.sh cargado previamente
#
# Flujo:
#   1. Solicitar IP/usuario/password del servidor FTP
#   2. Listar carpetas de servicios disponibles en /http/Linux/
#   3. El usuario elige servicio
#   4. Listar instaladores disponibles (.apk, .tar.gz)
#   5. El usuario elige version
#   6. Descargar instalador + archivo .sha256
#   7. Verificar integridad SHA256
#   8. Retornar ruta local del instalador en FTP_INSTALADOR
#      y nombre del servicio en FTP_SERVICIO
# =============================================================================

FTP_INSTALADOR=""    # Ruta local del instalador descargado
FTP_SERVICIO=""      # Nombre del servicio seleccionado (apache, nginx, tomcat)
FTP_DESCARGA_DIR="/tmp/ftp_descarga"

# =============================================================================
# NAVEGADOR FTP DINAMICO
# =============================================================================

navegador_ftp() {
    # Asegurar dependencias
    apk add --no-interactive curl openssl >/dev/null 2>&1

    printf "\n"
    printf "╔══════════════════════════════════════════════════════════╗\n"
    printf "║        CLIENTE FTP — REPOSITORIO PRIVADO                 ║\n"
    printf "╚══════════════════════════════════════════════════════════╝\n\n"

    # ── 1. Credenciales ───────────────────────────────────────────────────────
    printf "IP del servidor FTP: "
    read -r FTP_IP
    printf "Usuario FTP: "
    read -r FTP_USER
    printf "Password FTP: "
    read -r FTP_PASS   # En sh posix no hay -s, aceptable para practica
    printf "\n"

    FTP_BASE="ftp://${FTP_USER}:${FTP_PASS}@${FTP_IP}"
    FTP_REPO_RUTA="http/Linux"

    # ── 2. Listar servicios disponibles en /http/Linux/ ───────────────────────
    info "Conectando a ftp://$FTP_IP/$FTP_REPO_RUTA/ ..."

    _lista_servicios=$(curl -s --list-only \
        "${FTP_BASE}/${FTP_REPO_RUTA}/" 2>/dev/null)

    if [ -z "$_lista_servicios" ]; then
        error "No se pudo conectar al servidor FTP o la ruta esta vacia."
        error "Verifica IP, credenciales y que el servidor FTP este corriendo."
        return 1
    fi

    # Filtrar solo directorios (lineas que terminan en /)
    _servicios=""
    _idx=1
    printf "\n  Servicios disponibles en el repositorio:\n"
    printf "  ----------------------------------------\n"
    while IFS= read -r _item; do
        _item=$(echo "$_item" | tr -d '\r' | sed 's|/$||')
        [ -z "$_item" ] && continue
        printf "  %d) %s\n" "$_idx" "$_item"
        _servicios="${_servicios}${_item}\n"
        _idx=$((_idx+1))
    done <<EOF
$(echo "$_lista_servicios")
EOF
    _total_srv=$((_idx-1))

    if [ "$_total_srv" -eq 0 ]; then
        error "No se encontraron carpetas de servicios en $FTP_REPO_RUTA/"
        return 1
    fi
    printf "  ----------------------------------------\n\n"

    # ── 3. Seleccionar servicio ────────────────────────────────────────────────
    while true; do
        printf "  Elige un servicio [1-%d]: " "$_total_srv" >&2
        read -r _op_srv
        case "$_op_srv" in ''|*[!0-9]*) aviso "Numero valido." >&2; continue ;; esac
        if [ "$_op_srv" -ge 1 ] && [ "$_op_srv" -le "$_total_srv" ]; then break; fi
        aviso "Fuera de rango." >&2
    done

    FTP_SERVICIO=$(printf "%b" "$_servicios" | awk "NR==$_op_srv")
    ok "Servicio seleccionado: $FTP_SERVICIO"

    # ── 4. Listar instaladores disponibles (.apk, .tar.gz) ────────────────────
    _ruta_srv="${FTP_REPO_RUTA}/${FTP_SERVICIO}"
    info "Listando instaladores en /$_ruta_srv/ ..."

    _lista_archivos=$(curl -s --list-only \
        "${FTP_BASE}/${_ruta_srv}/" 2>/dev/null)

    if [ -z "$_lista_archivos" ]; then
        error "La carpeta $FTP_SERVICIO esta vacia o no accesible."
        return 1
    fi

    # Solo mostrar instaladores (no .sha256)
    _instaladores=""
    _idxi=1
    printf "\n  Instaladores disponibles para %s:\n" "$FTP_SERVICIO"
    printf "  ----------------------------------------\n"
    while IFS= read -r _arch; do
        _arch=$(echo "$_arch" | tr -d '\r')
        [ -z "$_arch" ] && continue
        # Mostrar solo archivos instalables, no los .sha256
        case "$_arch" in
            *.sha256|*.md5) continue ;;
        esac
        printf "  %d) %s\n" "$_idxi" "$_arch"
        _instaladores="${_instaladores}${_arch}\n"
        _idxi=$((_idxi+1))
    done <<EOF
$(echo "$_lista_archivos")
EOF
    _total_inst=$((_idxi-1))

    if [ "$_total_inst" -eq 0 ]; then
        error "No se encontraron instaladores en la carpeta $FTP_SERVICIO."
        return 1
    fi
    printf "  ----------------------------------------\n\n"

    # ── 5. Seleccionar version ─────────────────────────────────────────────────
    while true; do
        printf "  Elige un instalador [1-%d]: " "$_total_inst" >&2
        read -r _op_inst
        case "$_op_inst" in ''|*[!0-9]*) aviso "Numero valido." >&2; continue ;; esac
        if [ "$_op_inst" -ge 1 ] && [ "$_op_inst" -le "$_total_inst" ]; then break; fi
        aviso "Fuera de rango." >&2
    done

    _nombre_arch=$(printf "%b" "$_instaladores" | awk "NR==$_op_inst")
    ok "Instalador seleccionado: $_nombre_arch"

    # ── 6. Descargar instalador + sha256 ──────────────────────────────────────
    mkdir -p "$FTP_DESCARGA_DIR"
    _local_arch="${FTP_DESCARGA_DIR}/${_nombre_arch}"
    _local_hash="${_local_arch}.sha256"

    info "Descargando $_nombre_arch ..."
    if ! curl -s --progress-bar \
            "${FTP_BASE}/${_ruta_srv}/${_nombre_arch}" \
            -o "$_local_arch"; then
        error "Error al descargar el instalador."
        return 1
    fi
    ok "Instalador descargado en: $_local_arch"

    info "Descargando archivo de hash: ${_nombre_arch}.sha256 ..."
    if ! curl -s \
            "${FTP_BASE}/${_ruta_srv}/${_nombre_arch}.sha256" \
            -o "$_local_hash" 2>/dev/null; then
        aviso "No se encontro ${_nombre_arch}.sha256 en el servidor."
        aviso "No se podra verificar la integridad."
        _local_hash=""
    else
        ok "Hash descargado: $_local_hash"
    fi

    # ── 7. Verificar integridad SHA256 ────────────────────────────────────────
    _verificar_hash "$_local_arch" "$_local_hash" || return 1

    # ── 8. Retornar resultado ─────────────────────────────────────────────────
    FTP_INSTALADOR="$_local_arch"
    ok "Instalador listo para instalar: $FTP_INSTALADOR"
    return 0
}

# =============================================================================
# VERIFICACION DE INTEGRIDAD SHA256
# =============================================================================

_verificar_hash() {
    _archivo="$1"
    _archivo_hash="$2"

    if [ -z "$_archivo_hash" ] || [ ! -f "$_archivo_hash" ]; then
        aviso "Sin archivo .sha256 — omitiendo verificacion de integridad."
        return 0
    fi

    info "Verificando integridad SHA256 de $(basename "$_archivo") ..."

    # Calcular hash local
    _hash_local=$(sha256sum "$_archivo" 2>/dev/null | awk '{print $1}')

    if [ -z "$_hash_local" ]; then
        error "No se pudo calcular el hash local. ¿Esta instalado sha256sum?"
        apk add --no-interactive coreutils >/dev/null 2>&1
        _hash_local=$(sha256sum "$_archivo" 2>/dev/null | awk '{print $1}')
    fi

    # Leer hash esperado del archivo .sha256
    # El archivo puede contener "HASH  nombre_archivo" o solo "HASH"
    _hash_esperado=$(awk '{print $1}' "$_archivo_hash" | tr -d '[:space:]')

    printf "\n"
    printf "  Hash esperado  (servidor): %s\n" "$_hash_esperado"
    printf "  Hash calculado (local):    %s\n" "$_hash_local"
    printf "\n"

    if [ "$_hash_local" = "$_hash_esperado" ]; then
        ok "INTEGRIDAD VERIFICADA — El archivo no fue corrompido."
        return 0
    else
        error "FALLO DE INTEGRIDAD — Los hashes NO coinciden."
        error "El archivo puede estar corrompido o modificado."
        rm -f "$_archivo"
        return 1
    fi
}

# =============================================================================
# UTILIDAD: Generar .sha256 para un archivo (usado al preparar el repo FTP)
# =============================================================================

generar_hash_para_repo() {
    _dir="$1"
    info "Generando archivos .sha256 en: $_dir ..."
    find "$_dir" -type f \( -name "*.apk" -o -name "*.tar.gz" \) | while read -r _f; do
        _hfile="${_f}.sha256"
        sha256sum "$_f" > "$_hfile"
        ok "Generado: $_hfile"
    done
}
