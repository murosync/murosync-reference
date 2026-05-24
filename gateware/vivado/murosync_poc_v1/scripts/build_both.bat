@echo off
REM ============================================================================
REM build_both.bat — build both MASTER and SLAVE bitstreams sequentially
REM
REM Typical use: overnight build after RTL changes that affect both modes.
REM Total time: ~1.5-2 hours (synth + impl × 2).
REM ============================================================================

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
