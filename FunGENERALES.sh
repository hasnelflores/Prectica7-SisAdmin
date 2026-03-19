#!/bin/sh
# =============================================================================
# FunGENERALES.sh — Funciones utilitarias compartidas | Practica 7 | Alpine
# =============================================================================

# ── Colores ───────────────────────────────────────────────────────────────────
ROJO='\033[0;31m'
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

info()  { printf "${CYAN}[INFO]  %s${RESET}\n"     "$1"; }
ok()    { printf "${VERDE}[OK]    %s${RESET}\n"    "$1"; }
aviso() { printf "${AMARILLO}[AVISO] %s${RESET}\n" "$1"; }
error() { printf "${ROJO}[ERROR] %s${RESET}\n"     "$1"; }

# ── Pausa ─────────────────────────────────────────────────────────────────────
pause() {
    printf "\nPresiona Enter para continuar..."
    read -r _PAUSA
}

# ── Verificar root ────────────────────────────────────────────────────────────
VerificarRoot() {
    if [ "$(id -u)" -ne 0 ]; then
        error "Ejecuta el script como root: sudo ./Main7.sh"
        exit 1
    fi
}

# ── Leer numero en rango ──────────────────────────────────────────────────────
leer_numero() {
    _msg="$1"; _min="$2"; _max="$3"
    while true; do
        printf "%s [%s-%s]: " "$_msg" "$_min" "$_max" >&2
        read -r _v
        case "$_v" in
            ''|*[!0-9]*) aviso "Ingresa solo numeros entre $_min y $_max." >&2; continue ;;
        esac
        if [ "$_v" -lt "$_min" ] || [ "$_v" -gt "$_max" ]; then
            aviso "El numero debe estar entre $_min y $_max." >&2; continue
        fi
        printf "%s" "$_v"; return
    done
}

# ── Leer puerto libre ─────────────────────────────────────────────────────────
leer_puerto() {
    while true; do
        _p=$(leer_numero "Puerto de escucha" 1 65535)
        printf "\n" >&2
        case "$_p" in
            22|25|53|110|143|3306|5432|6379)
                aviso "Puerto $_p reservado. Elige otro." >&2 ;;
            *) printf "%s" "$_p"; return ;;
        esac
    done
}

# ── Verificar si puerto esta en uso ──────────────────────────────────────────
puerto_en_uso() {
    ss -tlnp 2>/dev/null | grep -q ":$1 " && return 0
    netstat -tlnp 2>/dev/null | grep -q ":$1 " && return 0
    return 1
}

# ── Abrir puerto en iptables ──────────────────────────────────────────────────
abrir_firewall() {
    _p="$1"
    if command -v iptables >/dev/null 2>&1; then
        iptables -C INPUT -p tcp --dport "$_p" -j ACCEPT 2>/dev/null \
            || iptables -A INPUT -p tcp --dport "$_p" -j ACCEPT
        ok "Puerto $_p abierto en iptables."
    else
        aviso "iptables no disponible. Abre el puerto $_p manualmente."
    fi
}

# ── Instalar paquete con apk ──────────────────────────────────────────────────
InstalarPaquete() {
    _pkg="$1"
    info "Instalando paquete: $_pkg ..."
    apk add --no-interactive "$_pkg" >/dev/null 2>&1 \
        && ok "$_pkg instalado." \
        || { error "No se pudo instalar $_pkg."; return 1; }
}

# ── Estado de un paquete ──────────────────────────────────────────────────────
EstadoPaquete() {
    _pkg="$1"
    if apk info -e "$_pkg" >/dev/null 2>&1; then
        _ver=$(apk info "$_pkg" 2>/dev/null | head -1 | sed "s/${_pkg}-//")
        ok "$_pkg instalado. Version: $_ver"
    else
        aviso "$_pkg NO esta instalado."
    fi
}

# ── Verificar que un servicio responde en un puerto ───────────────────────────
verificar_servicio() {
    _nombre="$1"; _puerto="$2"
    info "Verificando $_nombre en puerto $_puerto ..."
    sleep 2
    if nc -z 127.0.0.1 "$_puerto" 2>/dev/null; then
        ok "$_nombre responde en puerto $_puerto."
    else
        aviso "$_nombre no responde en puerto $_puerto."
    fi
}

# ── Crear usuario de sistema para un servicio ─────────────────────────────────
crear_usuario_servicio() {
    _usr="$1"; _dir="$2"
    if ! id "$_usr" >/dev/null 2>&1; then
        info "Creando usuario de sistema: $_usr ..."
        adduser -S -D -H -h "$_dir" -s /sbin/nologin "$_usr" 2>/dev/null \
            || adduser -S "$_usr" 2>/dev/null
        ok "Usuario $_usr creado."
    fi
    if [ -d "$_dir" ]; then
        chown -R "${_usr}:${_usr}" "$_dir" 2>/dev/null || true
        chmod 750 "$_dir"
    fi
}

# ── Crear pagina web de prueba ────────────────────────────────────────────────
crear_pagina_web() {
    _dir="$1"; _srv="$2"; _ver="$3"; _prt="$4"
    mkdir -p "$_dir"
    cat > "${_dir}/index.html" <<HTML
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>$_srv - Practica 7</title>
    <style>
        body{font-family:Arial,sans-serif;background:#1e1e2e;color:#cdd6f4;
             display:flex;justify-content:center;align-items:center;height:100vh;margin:0}
        .box{background:#313244;border-radius:12px;padding:40px 60px;
             text-align:center;box-shadow:0 4px 20px rgba(0,0,0,.5)}
        h1{color:#89b4fa;margin-bottom:20px}
        p{font-size:1.2rem;margin:8px 0}
        b{color:#a6e3a1}
        .ssl{color:#f38ba8;font-size:0.9rem;margin-top:16px}
    </style>
</head>
<body>
  <div class="box">
    <h1>Practica 7 — Infraestructura Segura</h1>
    <p>Servidor: <b>$_srv</b></p>
    <p>Version:  <b>$_ver</b></p>
    <p>Puerto:   <b>$_prt</b></p>
    <p class="ssl">reprobados.com | SSL/TLS Activo</p>
  </div>
</body>
</html>
HTML
    ok "index.html creado en $_dir"
}

# ── Seleccionar version de un paquete apk ─────────────────────────────────────
VERSION_ELEGIDA=""
PKG_INSTALAR=""

seleccionar_version() {
    _pkg="$1"
    VERSION_ELEGIDA=""; PKG_INSTALAR=""

    if grep -q "^#.*community" /etc/apk/repositories 2>/dev/null; then
        sed -i 's|^#\(.*community\)|\1|' /etc/apk/repositories
    fi
    apk update -q 2>/dev/null

    info "Buscando versiones de $_pkg ..."
    _tmp="/tmp/vers_${_pkg}.txt"; rm -f "$_tmp"

    apk list --available 2>/dev/null \
        | grep "^${_pkg}-[0-9]" | awk '{print $1}' \
        | sort -t'-' -k2 -Vr | head -8 > "$_tmp"

    _total=0
    while IFS= read -r _l; do _total=$((_total+1)); done < "$_tmp"

    if [ "$_total" -eq 0 ]; then
        apk search "${_pkg}" 2>/dev/null \
            | grep "^${_pkg}-[0-9]" | sort -t'-' -k2 -Vr | head -8 > "$_tmp"
        _total=0
        while IFS= read -r _l; do _total=$((_total+1)); done < "$_tmp"
    fi

    if [ "$_total" -eq 0 ]; then
        error "No se encontraron versiones para $_pkg."; rm -f "$_tmp"; return 1
    fi

    printf "\n  Versiones disponibles para %s:\n" "$_pkg"
    printf "  ----------------------------------------\n"
    _i=1
    while IFS= read -r _linea; do
        _ver=$(echo "$_linea" | sed "s/^${_pkg}-//" | sed 's/-r[0-9]*$//')
        if   [ "$_i" -eq 1 ];      then printf "  %d) %s  <- latest\n"       "$_i" "$_ver"
        elif [ "$_i" -eq "$_total" ]; then printf "  %d) %s  <- LTS/estable\n" "$_i" "$_ver"
        else printf "  %d) %s\n" "$_i" "$_ver"
        fi
        _i=$((_i+1))
    done < "$_tmp"
    printf "  ----------------------------------------\n\n"

    while true; do
        printf "  Elige una version [1-%s]: " "$_total" >&2
        read -r _op
        case "$_op" in ''|*[!0-9]*) aviso "Numero valido." >&2; continue ;; esac
        if [ "$_op" -ge 1 ] && [ "$_op" -le "$_total" ]; then break; fi
        aviso "Fuera de rango." >&2
    done

    _RAW=$(awk "NR==$_op" "$_tmp")
    VERSION_ELEGIDA=$(echo "$_RAW" | sed "s/^${_pkg}-//" | sed 's/-r[0-9]*$//')
    PKG_INSTALAR="$_pkg"
    rm -f "$_tmp"
    ok "Seleccionaste: $VERSION_ELEGIDA"
}

# ── Solicitar puerto con validacion ───────────────────────────────────────────
PUERTO_ELEGIDO=""

solicitar_puerto() {
    while true; do
        PUERTO_ELEGIDO=$(leer_puerto)
        if puerto_en_uso "$PUERTO_ELEGIDO"; then
            error "Puerto $PUERTO_ELEGIDO en uso. Elige otro."
        else
            break
        fi
    done
}
