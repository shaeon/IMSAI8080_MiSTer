@echo off
rem Compila IMSAI8080 para MiSTer con Quartus 17.0 desde linea de comandos
set QUARTUS=C:\altera_lite\17.0\quartus\bin64
"%QUARTUS%\quartus_sh.exe" --flow compile IMSAI8080 -c IMSAI8080
if errorlevel 1 goto :error
for /f %%i in ('powershell -nologo -noprofile -command "Get-Date -Format yyyyMMdd"') do set DT=%%i
copy /y output_files\IMSAI8080.rbf releases\IMSAI8080_%DT%.rbf >nul
echo Hecho: releases\IMSAI8080_%DT%.rbf
goto :eof
:error
echo Error de compilacion
exit /b 1
