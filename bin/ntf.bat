@echo off
setlocal
if "%NTF_NVIM%"=="" set "NTF_NVIM=nvim"
"%NTF_NVIM%" --clean --headless -l "%~dp0ntf" %*
