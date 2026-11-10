@echo off
setlocal
rem Run from an x64 Native Tools command prompt for Visual Studio.
pushd "%~dp0"
cl /nologo /W4 /GS- /Gs9999999 /Zl /LD core_tests.cpp /Fe:core_tests.dll /link /NOENTRY /NODEFAULTLIB
if errorlevel 1 exit /b 1
python run_tests.py
set "test_result=%errorlevel%"
popd
exit /b %test_result%
