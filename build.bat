@echo off
rem Compila IMSAI8080 para Chameleon96 (rama ch96) con Quartus 17.0 desde linea de comandos
set QUARTUS=C:\altera_lite\17.0\quartus\bin64
set REV=IMSAI8080_ch96
"%QUARTUS%\quartus_sh.exe" --flow compile IMSAI8080_ch96 -c %REV%
if errorlevel 1 goto :error
for /f %%i in ('powershell -nologo -noprofile -command "Get-Date -Format yyyyMMdd"') do set DT=%%i
copy /y output_files\%REV%.rbf releases\%REV%_%DT%.rbf >nul
echo Hecho: releases\%REV%_%DT%.rbf
goto :eof
:error
echo Error de compilacion
exit /b 1
