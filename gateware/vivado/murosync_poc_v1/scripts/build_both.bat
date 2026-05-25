@echo off
REM #############################################################################
REM # Project    : MuroSync
REM # File       : build_both.bat
REM # Created    : 2026-05-24
REM # Author     : Mikhail Vasilev
REM #
REM # Description:
REM #   Windows batch wrapper that builds BOTH MASTER and SLAVE bitstreams
REM #   sequentially in one session.
REM #
REM #   Typical use: overnight build after RTL changes that affect both modes.
REM #   First builds MASTER, then SLAVE. If MASTER fails, SLAVE build is
REM #   skipped to avoid wasting time on a likely-broken project state.
REM #
REM # Usage:
REM #   Double-click in Explorer, or run from CMD: build_both.bat
REM #
REM # Output:
REM #   C:\_vivado\murosync_poc_v1\bitstreams\murosync_MASTER.bit + .xsa
REM #   C:\_vivado\murosync_poc_v1\bitstreams\murosync_SLAVE.bit  + .xsa
REM #
REM # Notes:
REM #   - Vivado must be closed before running (script opens the project).
REM #   - Total build time: ~1.5-2 hours (two full synth+impl runs).
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
echo   Building BOTH bitstreams (MASTER + SLAVE)
echo   Estimated time: ~1.5-2 hours
echo ============================================================
echo.

REM ---- MASTER ----
echo.
echo --- Phase 1/2: MASTER ---
echo.

%VIVADO% -mode batch -source %SCRIPT% -tclargs MASTER

if errorlevel 1 (
    echo.
    echo MASTER BUILD FAILED. Skipping SLAVE.
    pause
    exit /b 1
)

REM ---- SLAVE ----
echo.
echo --- Phase 2/2: SLAVE ---
echo.

%VIVADO% -mode batch -source %SCRIPT% -tclargs SLAVE

if errorlevel 1 (
    echo.
    echo SLAVE BUILD FAILED. MASTER bitstream is OK.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo   BOTH BUILDS COMPLETE
echo   Output: C:\_vivado\murosync_poc_v1\bitstreams\
echo     - murosync_MASTER.bit + .xsa
echo     - murosync_SLAVE.bit + .xsa
echo ============================================================
echo.
pause
