#!/bin/sh
# =============================================================================
# Main77.sh — Orquestador | Practica 7 | Alpine Linux
# Instalacion Hibrida (WEB/FTP) + SSL/TLS en servicios HTTP y FTP
# =============================================================================

DIRECTORIO_SCRIPT="$(cd "$(dirname "$0")" && pwd)"

. "${DIRECTORIO_SCRIPT}/FunGENERALES.sh"
. "${DIRECTORIO_SCRIPT}/FunFTP.sh"
. "${DIRECTORIO_SCRIPT}/FunHTTP.sh"
. "${DIRECTORIO_SCRIPT}/FunSSL.sh"
. "${DIRECTORIO_SCRIPT}/FunClienteFTP.sh"

BLANCO='\033[1;37m'

VerificarRoot

# =============================================================================
# MENU PRINCIPAL
# =============================================================================

menu_principal() {
    while true; do
        clear
        printf "${BLANCO}"
        printf "=========================================\n"
        printf "   PRACTICA 07 - DESPLIEGUE SEGURO       \n"
        printf "=========================================\n"
        printf "  -- SERVIDOR FTP --\n"
        printf "  1. Instalar y configurar vsftpd\n"
        printf "  2. Administrar usuarios FTP\n"
        printf "  3. Administrar grupos FTP\n"
        printf "  -- SERVICIOS HTTP --\n"
        printf "  4. Instalar Apache2 / Nginx / Tomcat\n"
        printf "  -- SSL / TLS --\n"
        printf "  5. Habilitar SSL en un servicio\n"
        printf "  6. Habilitar SSL en TODOS los servicios\n"
        printf "  7. Ver resumen de verificacion SSL\n"
        printf "  0. Salir\n"
        printf "=========================================\n"
        printf "${RESET}"
        printf "Selecciona una opcion [0-7]: "
        read -r OPT

        case "$OPT" in
            1) menu_ftp_servidor   ;;
            2) menu_ftp_usuarios   ;;
            3) menu_ftp_grupos     ;;
            4) menu_http           ;;
            5) menu_ssl_individual ;;
            6) ssl_todos; pause    ;;
            7) resumen_ssl; pause  ;;
            0) ok "Saliendo. Hasta luego."; exit 0 ;;
            *) error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

# =============================================================================
# BLOQUE FTP
# =============================================================================

menu_ftp_servidor() {
    clear
    printf "${BLANCO}"
    printf "=========================================\n"
    printf "   SERVIDOR FTP - CONFIGURACION          \n"
    printf "=========================================\n"
    printf "${RESET}"

    info "Verificando vsftpd ..."
    if apk info -e vsftpd >/dev/null 2>&1; then
        ok "vsftpd ya esta instalado."
        printf "Desea reinstalar / reconfigurar? (s/N): "
        read -r _R
        case "$_R" in [sS]) ;; *) pause; return ;; esac
    fi

    InstalarPaquete "vsftpd"
    aplicarConfiguracion
    preguntar_ssl "vsftpd"
    EstadoPaquete "vsftpd"
    pause
}

menu_ftp_usuarios() {
    while true; do
        clear
        printf "${BLANCO}"
        printf "=========================================\n"
        printf "   ADMINISTRAR USUARIOS FTP              \n"
        printf "=========================================\n"
        printf "  1. Alta usuario\n"
        printf "  2. Baja usuario\n"
        printf "  3. Consultar usuarios\n"
        printf "  4. Mover usuario a otro grupo\n"
        printf "  0. Volver\n"
        printf "=========================================\n"
        printf "${RESET}"

        printf "Opcion: "
        read -r OPU
        case "$OPU" in
            1)
                printf "Numero de usuarios a crear: "
                read -r no_users
                printf "Nombres (separados por coma, ej: user1,user2): "
                read -r names
                printf "Contrasenas (mismo orden, separadas por coma): "
                read -r passwords
                registrarUsuarios
                pause ;;
            2)
                printf "Nombre del usuario a eliminar: "
                read -r _usr_del
                eliminarUsuario "$_usr_del"
                pause ;;
            3)
                consultarAlumnos
                pause ;;
            4)
                printf "Usuario: "
                read -r names
                printf "Grupo destino (reprobados/recursadores): "
                read -r groups
                moverGrupoUsuario
                pause ;;
            0) return ;;
            *) error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

menu_ftp_grupos() {
    while true; do
        clear
        printf "${BLANCO}"
        printf "=========================================\n"
        printf "   ADMINISTRAR GRUPOS FTP                \n"
        printf "=========================================\n"
        printf "  1. Alta grupo\n"
        printf "  2. Baja grupo\n"
        printf "  3. Consultar grupos\n"
        printf "  0. Volver\n"
        printf "=========================================\n"
        printf "${RESET}"

        printf "Opcion: "
        read -r OPG
        case "$OPG" in
            1)
                printf "Nombre del grupo (ej: GrupoA): "
                read -r _grp_nuevo
                registrarGrupo "$_grp_nuevo"
                pause ;;
            2)
                printf "Nombre del grupo a eliminar: "
                read -r _grp_del
                eliminarGrupo "$_grp_del"
                pause ;;
            3)
                consultarGrupos
                pause ;;
            0) return ;;
            *) error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

# =============================================================================
# BLOQUE HTTP
# =============================================================================

menu_http() {
    clear
    printf "${BLANCO}"
    printf "=========================================\n"
    printf "   INSTALAR SERVICIO HTTP                \n"
    printf "=========================================\n"
    printf "  ORIGEN DE INSTALACION:\n"
    printf "  1. WEB - repositorio oficial apk\n"
    printf "  2. FTP - repositorio privado\n"
    printf "  0. Volver\n"
    printf "=========================================\n"
    printf "${RESET}"

    printf "Origen [0-2]: "
    read -r ORIGEN
    case "$ORIGEN" in
        1) menu_http_web ;;
        2) menu_http_ftp ;;
        0) return ;;
        *) error "Opcion invalida."; sleep 1 ;;
    esac
}

menu_http_web() {
    clear
    printf "${BLANCO}"
    printf "=========================================\n"
    printf "   INSTALAR HTTP - DESDE APK (WEB)       \n"
    printf "=========================================\n"
    printf "  1. Apache2\n"
    printf "  2. Nginx\n"
    printf "  3. Tomcat\n"
    printf "  0. Volver\n"
    printf "=========================================\n"
    printf "${RESET}"

    printf "Servicio [0-3]: "
    read -r SRV
    case "$SRV" in
        1)
            seleccionar_version apache2
            solicitar_puerto
            instalar_apache "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO"
            verificar_servicio "apache2" "$PUERTO_ELEGIDO"
            preguntar_ssl "apache"
            pause ;;
        2)
            seleccionar_version nginx
            solicitar_puerto
            instalar_nginx "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO"
            verificar_servicio "nginx" "$PUERTO_ELEGIDO"
            preguntar_ssl "nginx"
            pause ;;
        3)
            seleccionar_version_tomcat
            solicitar_puerto
            instalar_tomcat "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO"
            verificar_servicio "tomcat" "$PUERTO_ELEGIDO"
            preguntar_ssl "tomcat"
            pause ;;
        0) return ;;
        *) error "Opcion invalida."; sleep 1 ;;
    esac
}

menu_http_ftp() {
    printf "\n"
    info "Instalacion desde repositorio FTP privado"
    aviso "Asegurate de que el servidor FTP esta corriendo y tiene la estructura:"
    aviso "  /http/Linux/Apache/   /http/Linux/Nginx/   /http/Linux/Tomcat/"
    printf "\n"

    navegador_ftp || { pause; return; }

    if [ -z "$FTP_INSTALADOR" ] || [ ! -f "$FTP_INSTALADOR" ]; then
        error "No se obtuvo un instalador valido."; pause; return
    fi

    instalar_desde_ftp "$FTP_INSTALADOR" "$FTP_SERVICIO"

    _srv_lower=$(echo "$FTP_SERVICIO" | tr '[:upper:]' '[:lower:]')
    case "$_srv_lower" in
        apache*) preguntar_ssl "apache" ;;
        nginx*)  preguntar_ssl "nginx"  ;;
        tomcat*) preguntar_ssl "tomcat" ;;
    esac

    pause
}

# =============================================================================
# BLOQUE SSL
# =============================================================================

menu_ssl_individual() {
    clear
    printf "${BLANCO}"
    printf "=========================================\n"
    printf "   HABILITAR SSL - SERVICIO INDIVIDUAL   \n"
    printf "=========================================\n"
    printf "  1. Apache2  (HTTPS 443 + HTTP->HTTPS)\n"
    printf "  2. Nginx    (HTTPS 443 + HTTP->HTTPS)\n"
    printf "  3. Tomcat   (HTTPS 443)\n"
    printf "  4. vsftpd   (FTPS canal cifrado)\n"
    printf "  0. Volver\n"
    printf "=========================================\n"
    printf "${RESET}"

    printf "Opcion [0-4]: "
    read -r SSL_OPT
    case "$SSL_OPT" in
        1) habilitar_ssl_apache;  verificar_ssl_servicio "apache2" "443";       pause ;;
        2) habilitar_ssl_nginx;   verificar_ssl_servicio "nginx"   "443";       pause ;;
        3) habilitar_ssl_tomcat;  verificar_ssl_servicio "tomcat"  "443";       pause ;;
        4) habilitar_ssl_vsftpd;  verificar_ssl_servicio "vsftpd"  "21" "true"; pause ;;
        0) return ;;
        *) error "Opcion invalida."; sleep 1 ;;
    esac
}

# =============================================================================
# ARRANCAR
# =============================================================================
menu_principal