@echo off
REM ============================================================================
REM build_master.bat — build only MASTER bitstream
REM ============================================================================

set VIVADO="C:\Xilinx\Vivado\2022.2\bin\vivado.bat"
set SCRIPT="C:\_vivado\murosync_poc_v1\scripts\build_bitstream.tcl"

echo.
echo ============================================================
echo   Building MASTER bitstream
echo ============================================================
echo.

%VIVADO% -mode batch -source %SCRIPT% -tclargs MASTER

if errorlevel 1 (
    echo.
    echo BUILD FAILED. Check log above.
    pause
    exit /b 1
)

echo.
echo MASTER build done. Bitstream + XSA in C:\_vivado\murosync_poc_v1\bitstreams\
echo.
pause
