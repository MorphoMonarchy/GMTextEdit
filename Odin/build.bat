@echo off
setlocal

set "MSVC_VER=14.51.36231"
set "SDK_VER=10.0.28000.0"

set "MSVC_DIR=C:\msvc\VC\Tools\MSVC\%MSVC_VER%"
set "SDK_DIR=C:\Program Files (x86)\Windows Kits\10"
set "ODIN_DIR=C:\Users\jhwar\OneDrive\Documents\Odin\OdinRepo"
set "PROJECT_DIR=%~dp0"
set "BUILD_DIR=%PROJECT_DIR%build"
set "OUT_DLL=%BUILD_DIR%\gmtextedit.dll"
set "OUT_EXE=%BUILD_DIR%\textedit.exe"
set "OUT_WASM=%BUILD_DIR%\gmtextedit.wasm"
set "OUT_GM_DLL=%PROJECT_DIR%..\GM\extensions\ext_gmtextedit\gmtextedit.dll"
set "OUT_GX_JS=%PROJECT_DIR%..\GM\extensions\ext_gmtextedit\gmtextedit.js"
set "GX_BRIDGE_SCRIPT=%PROJECT_DIR%build_gx_bridge.ps1"
set "RUN_AFTER_BUILD=1"

if /i "%~1"=="build" set "RUN_AFTER_BUILD=0"

echo Running GMTextEdit Odin build: %~f0

if not exist "%ODIN_DIR%\odin.exe" (
    echo Odin compiler not found: "%ODIN_DIR%\odin.exe"
    exit /b 1
)

if not exist "%MSVC_DIR%\bin\Hostx64\x64\link.exe" (
    echo MSVC linker not found: "%MSVC_DIR%\bin\Hostx64\x64\link.exe"
    exit /b 1
)

if not exist "%SDK_DIR%\Lib\%SDK_VER%\um\x64\kernel32.lib" (
    echo Windows SDK libraries not found: "%SDK_DIR%\Lib\%SDK_VER%"
    exit /b 1
)

set "PATH=%MSVC_DIR%\bin\Hostx64\x64;%ODIN_DIR%;%PATH%"
set "INCLUDE=%MSVC_DIR%\include;%SDK_DIR%\Include\%SDK_VER%\ucrt;%SDK_DIR%\Include\%SDK_VER%\um;%SDK_DIR%\Include\%SDK_VER%\shared"
set "LIB=%MSVC_DIR%\lib\x64;%SDK_DIR%\Lib\%SDK_VER%\ucrt\x64;%SDK_DIR%\Lib\%SDK_VER%\um\x64"
set "LIBPATH=%MSVC_DIR%\lib\x64;%SDK_DIR%\UnionMetadata\%SDK_VER%;%SDK_DIR%\References\%SDK_VER%;%LIBPATH%"
set "VCToolsInstallDir=%MSVC_DIR%\"
set "VCINSTALLDIR=C:\msvc\VC\"
set "VSINSTALLDIR=C:\msvc\"
set "WindowsSdkDir=%SDK_DIR%\"
set "WindowsSDKVersion=%SDK_VER%\"
set "UniversalCRTSdkDir=%SDK_DIR%\"
set "UCRTVersion=%SDK_VER%"

pushd "%PROJECT_DIR%" || exit /b 1

if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
if errorlevel 1 (
    popd
    exit /b 1
)

"%ODIN_DIR%\odin.exe" build . -out:"%OUT_EXE%"
set "STATUS=%ERRORLEVEL%"
if not "%STATUS%"=="0" (
    popd
    exit /b %STATUS%
)

if "%RUN_AFTER_BUILD%"=="1" (
    "%OUT_EXE%"
    set "STATUS=%ERRORLEVEL%"
    if not "%STATUS%"=="0" (
        popd
        exit /b %STATUS%
    )
)

"%ODIN_DIR%\odin.exe" build . -build-mode:dll -out:"%OUT_DLL%"
set "STATUS=%ERRORLEVEL%"
if not "%STATUS%"=="0" (
    popd
    exit /b %STATUS%
)

copy /Y "%OUT_DLL%" "%OUT_GM_DLL%" >nul
set "STATUS=%ERRORLEVEL%"
if not "%STATUS%"=="0" (
    popd
    exit /b %STATUS%
)

"%ODIN_DIR%\odin.exe" build . -target:js_wasm32 -no-entry-point -out:"%OUT_WASM%"
set "STATUS=%ERRORLEVEL%"
if not "%STATUS%"=="0" (
    popd
    exit /b %STATUS%
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%GX_BRIDGE_SCRIPT%" -WasmPath "%OUT_WASM%" -OutJs "%OUT_GX_JS%"
set "STATUS=%ERRORLEVEL%"
if not "%STATUS%"=="0" (
    popd
    exit /b %STATUS%
)

if "%RUN_AFTER_BUILD%"=="0" (
    echo Built %OUT_EXE%
    echo Built %OUT_DLL%
    echo Built %OUT_GM_DLL%
    echo Built %OUT_WASM%
    echo Built %OUT_GX_JS%
)

popd
if not "%STATUS%"=="0" exit /b %STATUS%
exit /b 0
