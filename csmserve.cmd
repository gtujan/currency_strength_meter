@echo off
rem csmserve run|stop|restart|status|logs   (Windows launcher; logic lives in csmserve.py)
set "D=%~dp0"
if exist "%D%.venv\Scripts\python.exe" (
  "%D%.venv\Scripts\python.exe" "%D%csmserve.py" %*
) else (
  where py >nul 2>nul && (py -3 "%D%csmserve.py" %*) || (python "%D%csmserve.py" %*)
)
