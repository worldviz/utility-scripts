@echo off
REM Activate the virtual environment and run the CARLA agent

REM Check if uvicorn is already running on port 8081
netstat -ano | findstr ":8081" | findstr "LISTENING" >NUL
if "%ERRORLEVEL%"=="0" (
    echo Agent is already running on port 8081!
    echo If you need to restart it, please stop the existing process first.
    timeout /t 3
    exit /b
)

@REM cd /d "C:\Users\andybeall\Documents\SCSU\orchestrator"

REM Use external venv to avoid syncthing conflicts
REM Default location: C:\wvlab\venv-carla
REM You can change this path to match your setup
set "VENV_PATH=C:\wvlab\venv-orchestrator"

REM Check if .venv-location file exists (created by setup script)
if exist "..\\.venv-location" (
    set /p VENV_PATH=<..\.venv-location
    echo Using venv from .venv-location file: %VENV_PATH%
)

REM Verify venv exists
if not exist "%VENV_PATH%\Scripts\activate.bat" (
    echo ERROR: Virtual environment not found at: %VENV_PATH%
    echo.
    echo Please run setup_external_venv.ps1 first:
    echo   powershell -ExecutionPolicy Bypass -File ..\setup_external_venv.ps1
    echo.
    pause
    exit /b 1
)

call "%VENV_PATH%\Scripts\activate.bat"

REM Set token (optional - can be configured via environment variable)
if not defined CARLA_AGENT_TOKEN (
    set CARLA_AGENT_TOKEN=scsu-bect
)

python -m uvicorn agent:app --host 0.0.0.0 --port 8081

pause
