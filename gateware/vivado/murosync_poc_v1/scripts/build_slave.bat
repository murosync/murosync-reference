@echo off
REM #############################################################################
REM # Project    : MuroSync
REM # File       : build_slave.bat
REM # Created    : 2026-05-24
REM # Author     : Mikhail Vasilev
REM #
REM # Description:
REM #   Windows batch wrapper that invokes Vivado in batch mode to build the
REM #   SLAVE bitstream variant of the murosync_poc_v1 project.
REM #
REM #   Sets up paths to the Vivado executable and the build_bitstream.tcl
REM #   script, then launches the build with -tclargs SLAVE. After the build
REM #   completes (or fails) the window pauses so the user can inspect output.
REM #
REM # Usage:
REM #   Double-click in Explorer, or run from CMD: build_slave.bat
REM #
REM # Output:
REM #   C:\_vivado\murosync_poc_v1\bitstreams\murosync_SLAVE.bit
REM #   C:\_vivado\murosync_poc_v1\bitstreams\murosync_SLAVE.xsa
REM #
REM # Notes:
REM #   - Vivado must be closed before running (script opens the project).
REM #   - Build time: ~45-60 minutes (synthesis + implementation + bitstream).
REM #
REM # Copyright (c) 2026 Mikhail Vasilev / MuroSync
REM #
REM # License:
REM # This file is currently released under a restricted research license.
REM # Licensing terms may change in future revisions of the project.
REM #
REM # Commercial use, redistribution, or integration into commercial products
REM # requires an explicit license agreement.
REM #
REM # For licensing inquiries, please contact:
REM #     info@murosync.com
REM #
REM #############################################################################

set VIVADO="C:\Xilinx\Vivado\2022.2\bin\vivado.bat"
set SCRIPT="C:\_vivado\murosync_poc_v1\scripts\build_bitstream.tcl"

echo.
echo ============================================================
echo   Building SLAVE bitstream
echo ============================================================
echo.

%VIVADO% -mode batch -source %SCRIPT% -tclargs SLAVE

if errorlevel 1 (
    echo.
    echo BUILD FAILED. Check log above.
    pause
    exit /b 1
)

echo.
echo SLAVE build done. Bitstream + XSA in C:\_vivado\murosync_poc_v1\bitstreams\
echo.
pause
