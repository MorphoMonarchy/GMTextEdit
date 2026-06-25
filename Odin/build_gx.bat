@echo off
setlocal

set "ODIN_DIR=C:\Users\jhwar\OneDrive\Documents\Odin\OdinRepo"
set "PROJECT_DIR=%~dp0"
set "BUILD_DIR=%PROJECT_DIR%build"
set "OUT_WASM=%BUILD_DIR%\gmtextedit.wasm"
set "OUT_GX_JS=%PROJECT_DIR%..\GM\extensions\ext_gmtextedit\gmtextedit.js"
set "GX_BRIDGE_SCRIPT=%PROJECT_DIR%build_gx_bridge.ps1"

echo Running GMTextEdit GX build: %~f0

if not exist "%ODIN_DIR%\odin.exe" (
    echo Odin compiler not found: "%ODIN_DIR%\odin.exe"
    exit /b 1
)

pushd "%PROJECT_DIR%" || exit /b 1

if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
if errorlevel 1 (
    popd
    exit /b 1
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

echo Built %OUT_WASM%
echo Built %OUT_GX_JS%

popd
exit /b 0
