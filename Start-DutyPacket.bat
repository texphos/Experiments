@echo off
setlocal
cd /d "%~dp0"
title Duty Packet
echo Duty Packet
echo Packet and checklist only. Nothing is filed to Grants.gov or JustGrants.
echo.

where py >nul 2>nul
if %ERRORLEVEL%==0 (
  set "PY=py -3"
) else (
  set "PY=python"
)

if not exist ".venv\Scripts\python.exe" (
  echo Creating a local virtual environment...
  %PY% -m venv .venv
  if errorlevel 1 (
    echo Python 3 is required.
    pause
    exit /b 1
  )
)

call ".venv\Scripts\activate.bat"
python -m pip install -q -r requirements.txt
if errorlevel 1 (
  echo Could not install requirements.
  pause
  exit /b 1
)

if exist ".env" (
  echo Using .env in this folder for Census ACS and FBI CDE keys.
) else (
  echo No .env found. Copy .env.example to .env and add keys.
  echo Census ACS and FBI CDE will fail closed and leave those fields blank.
)

echo.
echo Open http://127.0.0.1:8765
start "" "http://127.0.0.1:8765"
python server.py
endlocal
