@echo off
setlocal
if "%NTF_NVIM%"=="" set "NTF_NVIM=nvim"
set "NTF_SCRIPT=%~dp0ntf"
if not exist "%NTF_SCRIPT%" (>&2 echo ntf: entry point not found: "%NTF_SCRIPT%"& >&2 echo ntf: cmd.exe runs a .bat from where the file itself sits, so put the plugin's bin directory on the PATH instead of copying or linking ntf.bat out of it.& exit /b 2)
"%NTF_NVIM%" --clean --headless -l "%NTF_SCRIPT%" %*
