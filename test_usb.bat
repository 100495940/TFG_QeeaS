@echo off
setlocal

echo =========================================
echo Conectando ESP32 a Docker
echo =========================================
echo.

echo ANTES: %g

where usbipd

echo DESPUES_WHERE

usbipd list

echo DESPUES_USBIPD

echo HOLA

pause