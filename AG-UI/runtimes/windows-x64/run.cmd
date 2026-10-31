@echo off
setlocal
set SCRIPT_DIR=%~dp0
dotnet "%SCRIPT_DIR%..\..\src\csharp\AGUI.dll" %*
