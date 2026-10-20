@echo off
rem LibMan (Windows) -> Xschem (WSL) launcher for .sch / .sym / .schematic.room / .symbol.room
rem Tool Manager -> Schematic tab -> point to this .bat file (any checkout path).

setlocal EnableExtensions

if "%~1"=="" (
  echo usage: %~nx0 ^<view-file-path^>
  exit /b 1
)

rem Pass LibMan primitive-library env vars into WSL (/p = path translate, lists use : in WSL).
rem Include CORE_* aliases — LibMan sets those (mapped to ROOM_* inside the .sh).
set "WSLENV=ROOM_PRIMITIVE_LIBS_FILE/p:ROOM_PRIMITIVE_LIBS/p:ROOM_PRIMITIVE_LIB/p:CORE_PRIMITIVE_LIBS_FILE/p:CORE_PRIMITIVE_LIBS/p:CORE_PRIMITIVE_LIB/p:LIBMAN_TECH_LIBRARY/u:XSCHEM_PRIMITIVE_CACHE/p:COMMONDB_ROOT/p:XSCHEM_OPEN_ROOM/p:XSCHEM_OPEN_FILE/p:XSCHEM_OPEN_CORE/p:PDK_ROOT/u:PDK/u:XSCHEM_NETLIST_DIR/u"

rem Single wsl.exe invoke (no prior sed, no login shell). Double wsl + bash -lc
rem was a multi-second stall before the script even started.
rem LibMan startDetached keeps this alive until xschem exits.
wsl --cd "%~dp0" bash ./open-xschem-wsl.sh "%~1"
exit /b %ERRORLEVEL%
