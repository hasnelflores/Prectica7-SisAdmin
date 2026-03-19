#  Automatización de Servidor FTP (Windows & Alpine Linux)

**Práctica 7 - Administración de Sistemas Operativos / Seguridad Informática**

Este repositorio contiene los scripts de aprovisionamiento desatendido (Zero-Touch Provisioning) para el despliegue de un servidor FTP seguro en entornos híbridos. El objetivo es garantizar una estructura de directorios estandarizada, aplicando políticas de seguridad como autenticación básica y enjaulamiento de usuarios (chroot jail).

##  Tecnologías y Entornos
* **Windows Server 2026:** PowerShell, Internet Information Services (IIS), Módulo WebAdministration.
* **Alpine Linux:** Ash/Bash, gestor de paquetes `apk`, demonio `vsftpd`, `OpenRC`.

##  Características Principales
1. **Zero-Touch Provisioning:** Despliegue completo sin intervención manual.
2. **Resolución de Conflictos TCP:** El script de Windows detecta y mitiga errores de *bindings* en el puerto 21 (HRESULT `0x800710D8`).
3. **Aislamiento (Chroot Jail):** Configuración estricta en Linux para evitar el escalamiento de privilegios de los usuarios FTP.
4. **Saneamiento Automático:** Búsqueda y destrucción recursiva de directorios no autorizados (ej. `Tomcat`).
5. **Inyección de Archivos:** Creación dinámica de la estructura de carpetas (`Apache`, `IIS`, `Nginx`) y sus respectivos binarios simulados `.zip`.

##  Estructura del Repositorio
* `main.ps1` - Script principal de automatización para Windows Server (IIS).
* `main.sh` - Script principal de automatización para Alpine Linux (vsftpd).
* `Reporte_Practica7.pdf` - Documentación detallada, arquitectura, bitácora de errores y capturas de validación.

##  Instrucciones de Ejecución

### Entorno Windows (PowerShell)
Requiere ejecutar PowerShell con privilegios de Administrador y tener el rol de IIS/FTP instalado.
```powershell
.\main.ps1
