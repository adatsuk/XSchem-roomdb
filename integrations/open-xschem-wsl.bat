@echo off
rem LibMan (Windows) -> Xschem (WSL) launcher for .sch / .sym / .schematic.room / .symbol.room
rem Tool Manager -> Schematic tab -> point to this .bat file (any checkout path).

setlocal EnableExtensions

if "%~1"=="" (
  echo usage: %~nx0 ^<view-file-path^>
  exit /b 1
)

rem Pass LibMan primitive-library env vars into WSL (/p = path translate, lists use : in WSL).
set "WSLENV=ROOM_PRIMITIVE_LIBS_FILE/p:ROOM_PRIMITIVE_LIBS/p:ROOM_PRIMITIVE_LIB/p:LIBMAN_TECH_LIBRARY/u:XSCHEM_PRIMITIVE_CACHE/p:COMMONDB_ROOT/p:XSCHEM_OPEN_ROOM/p:XSCHEM_OPEN_FILE/p:PDK_ROOT/u:PDK/u:XSCHEM_NETLIST_DIR/u"

wsl --cd "%~dp0" sed -i "s/\r$//" ./open-xschem-wsl.sh 2>nul
rem Launch WSL in the foreground; LibMan startDetached keeps this alive until xschem exits.
rem Do not use "start /b" here — it breaks WSLg window mapping.
wsl --cd "%~dp0" bash -lc "./open-xschem-wsl.sh '%~1'"
exit /b %ERRORLEVEL%
