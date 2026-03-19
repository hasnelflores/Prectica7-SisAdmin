#!/bin/sh
# =============================================================================
# PrepararRepo.sh — Prepara el repositorio FTP con instaladores reales
# Practica 7 | Alpine Linux
# =============================================================================
# Ejecutar UNA vez en el servidor FTP antes de usar el cliente FTP.
# Descarga los .apk de Alpine y genera sus .sha256 automaticamente.
# =============================================================================

FTP_REPO="/srv/ftp/http"

info()  { printf "\033[0;36m[INFO]  %s\033[0m\n" "$1"; }
ok()    { printf "\033[0;32m[OK]    %s\033[0m\n" "$1"; }
aviso() { printf "\033[1;33m[AVISO] %s\033[0m\n" "$1"; }
error() { printf "\033[0;31m[ERROR] %s\033[0m\n" "$1"; }

if [ "$(id -u)" -ne 0 ]; then
    error "Ejecuta como root."; exit 1
fi

apk add --no-interactive curl >/dev/null 2>&1

# ── Crear estructura de directorios ──────────────────────────────────────────
info "Creando estructura del repositorio en $FTP_REPO ..."
for srv in Apache Nginx Tomcat; do
    mkdir -p "$FTP_REPO/Linux/$srv"
done
chmod -R 755 "$FTP_REPO"
ok "Estructura creada."

# ── Descargar .apk de Alpine para cada servicio ───────────────────────────────

_descargar_apk() {
    _paquete="$1"
    _destino="$2"

    info "Descargando paquete Alpine: $_paquete ..."
    apk update -q 2>/dev/null

    # Obtener la URL del paquete desde el cache de apk
    apk fetch --output "$_destino" "$_paquete" >/dev/null 2>&1
    _arch=$(ls "$_destino"/${_paquete}-*.apk 2>/dev/null | head -1)

    if [ -n "$_arch" ] && [ -f "$_arch" ]; then
        sha256sum "$_arch" > "${_arch}.sha256"
        ok "Descargado: $(basename "$_arch")"
        ok "Hash:       $(basename "${_arch}").sha256"
    else
        aviso "No se pudo descargar $_paquete. Coloca el .apk manualmente en $_destino"
    fi
}

# Apache2
_descargar_apk "apache2"  "$FTP_REPO/Linux/Apache"

# Nginx
_descargar_apk "nginx"    "$FTP_REPO/Linux/Nginx"

# Tomcat — se distribuye como tar.gz, no hay .apk oficial
# Descargamos el tar.gz directamente
_descargar_tomcat() {
    _version="${1:-10.1.36}"
    _destino="$FTP_REPO/Linux/Tomcat"
    _mayor=$(echo "$_version" | cut -d. -f1)
    _url="https://downloads.apache.org/tomcat/tomcat-${_mayor}/v${_version}/bin/apache-tomcat-${_version}.tar.gz"
    _archivo="${_destino}/tomcat-${_version}.tar.gz"

    info "Descargando Apache Tomcat $_version ..."
    if curl -fsSL "$_url" -o "$_archivo" 2>/dev/null; then
        sha256sum "$_archivo" > "${_archivo}.sha256"
        ok "Descargado: $(basename "$_archivo")"
        ok "Hash:       $(basename "$_archivo").sha256"
    else
        aviso "No se pudo descargar Tomcat $_version desde Apache."
        aviso "Coloca el tar.gz manualmente en $_destino"
    fi
}

_descargar_tomcat "10.1.36"

# ── Resumen ───────────────────────────────────────────────────────────────────
printf "\n"
printf "╔══════════════════════════════════════════════════════════╗\n"
printf "║        CONTENIDO DEL REPOSITORIO FTP                     ║\n"
printf "╚══════════════════════════════════════════════════════════╝\n"
find "$FTP_REPO" -type f | sort | while read -r _f; do
    printf "  %s\n" "$_f"
done
printf "\n"
ok "Repositorio listo. Ya puedes ejecutar Main7.sh y usar la opcion FTP."
