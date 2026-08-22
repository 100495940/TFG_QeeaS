@echo off
setlocal enabledelayedexpansion

echo =========================================
echo   Conectando ESP32-C6 a Docker
echo =========================================
echo.

:: Comprobar dependencia: usbipd
where usbipd >nul 2>nul
if %errorlevel% neq 0 (
    echo [CRITICO] La herramienta 'usbipd' no se encuentra instalada en el equipo
    echo Iniciando instalacion automatica
    winget install --interactive --exact dorssel.usbipd-win
    echo.
    echo [INFO] Instalacion completada. Por favor, cierra esta ventana y vuelva a ejecutar el script.
    pause
    exit /b
)

echo [1/3] Buscando placa ESP32 compatible conectada
echo %TEMP%
set "BUSID="
set "BUSID_FILE=%TEMP%\qeeas_usb_list.txt"

echo --- Lista de dispositivos detectados por Windows ---
usbipd list
usbipd list > temp_usb_list.txt
echo --------------------------------------------------
echo.

REM IDs soportados:
REM CH340     = 1a86:7523
REM CP210x    = 10c4:ea60
REM Espressif = 303a:xxxx

powershell -NoProfile -Command "$line = usbipd list | Where-Object { $_ -match '^\s*\d+-\d+\s+(1a86:7523|10c4:ea60|303a:[0-9a-fA-F]{4})\s+' } | Select-Object -First 1; if ($line -match '^\s*(\d+-\d+)') { $Matches[1] }" > "%BUSID_FILE%"

set /p BUSID=<"%BUSID_FILE%"
del "%BUSID_FILE%" >nul 2>nul

if not defined BUSID (
    echo [ERROR] No se ha detectado ninguna placa ESP32 compatible conectada.
    echo Asegurate de que la placa esta conectada por USB y encendida.
    pause
    exit /b
)

echo [INFO] Placa ESP32 detectada con BUSID: !BUSID!

:: ==========================================
:: PERMISOS DE RED (FIREWALL) AUTOMATIZADOS
:: ==========================================
echo [INFO] Comprobando reglas de red interna (Firewall WSL)...
netsh advfirewall firewall show rule name="usbipd Bind Port" >nul 2>nul
if %errorlevel% neq 0 (
    echo [ALERTA] Es la primera vez que se ejecuta. Se necesita abrir el puerto 3240.
    echo [ALERTA] Por favor, ACEPTA la ventana de Administrador emergente.
    powershell -Command "Start-Process netsh -ArgumentList 'advfirewall firewall add rule name=\"usbipd Bind Port\" dir=in action=allow protocol=TCP localport=3240' -Verb RunAs"
    
    :: Damos 3 segundos para que Windows aplique la regla de seguridad
    timeout /t 3 >nul
    echo [INFO] Regla de Firewall inyectada con exito.
) else (
    echo [INFO] Regla de Firewall ya estaba configurada. Todo en orden.
)
echo.

:: Vincular e inyectar el hardware al contenedor
echo [2/3] Conectando hardware a la maquina virtual de Docker

:: Forzar vinculación previa por si alguna conexión se ha quedado colgada
usbipd detach --busid !BUSID! >nul 2>nul
timeout /t 2 >nul

:: Vincular puerto de nuevo
usbipd bind --busid !BUSID! >nul 2>nul

:: Inyectar la placa en WSL 
usbipd attach --wsl --busid !BUSID!
if %errorlevel% neq 0 (
    echo [ERROR] Fallo al intentar pasar el USB a Docker. ¿Esta Docker Desktop abierto?
    pause
    exit /b
)

:: Abrir el entorno
echo [3/3] Abriendo Visual Studio Code
:: code .

echo.
echo ===================================================
echo EXITO: El entorno esta listo.
echo En VS Code, abre una terminal y ejecuta:
echo bash ejecutar_tfg.sh
echo ===================================================
pause