@echo off
cd /d "%~dp0"
echo   Installing dependencies if needed...
python -m pip install --quiet -r requirements.txt
echo.
python touchbar_server.py
pause
