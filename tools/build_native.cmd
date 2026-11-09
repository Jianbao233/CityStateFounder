@echo off
setlocal
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1
cd /d "%~dp0.."
if not exist build\shared_native mkdir build\shared_native
set "OUT=build\shared_native"
set "API=native\vendor"
cl /nologo /std:c++17 /O2 /W3 /EHsc /MT /Gy /utf-8 /DC6FW_VARIANT=2 /DCIV6_PLUGIN_GAMECORE /I"%API%" /c /Fo"%OUT%\\" native\csf_plugin.cpp native\csf_bridge.cpp
if errorlevel 1 exit /b 1
rc /nologo /fo "%OUT%\csf_plugin.res" native\csf_plugin.rc
if errorlevel 1 exit /b 1
link /nologo /DLL /OPT:REF /OPT:ICF /OUT:"%OUT%\CityStateFounder.dll" "%OUT%\csf_plugin.obj" "%OUT%\csf_bridge.obj" "%OUT%\csf_plugin.res" bcrypt.lib
exit /b %errorlevel%
