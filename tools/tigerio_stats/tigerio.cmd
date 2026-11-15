@echo off
setlocal
set "TIGERIO_PYTHON=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
if not exist "%TIGERIO_PYTHON%" goto system_python
"%TIGERIO_PYTHON%" "%~dp0tigerio.py" %*
exit /b %errorlevel%
:system_python
where py >nul 2>nul
if errorlevel 1 goto no_python
py -3 "%~dp0tigerio.py" %*
exit /b %errorlevel%
:no_python
echo {"error":"Python 3 is unavailable"} 1>&2
exit /b 1
