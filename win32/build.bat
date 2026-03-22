@echo off
setlocal enabledelayedexpansion

set ROOT=C:\projects\librdkafka\librdkafka
set VCPKG_ROOT=C:\projects\librdkafka\vcpkg

echo ===== Detecting Visual Studio =====

set VSWHERE="%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"

if not exist %VSWHERE% (
    echo ERROR: vswhere.exe not found. Please install Visual Studio with C++ build tools.
    exit /b 1
)

set VS=
for /f "tokens=*" %%i in ('%VSWHERE% -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find VC\Auxiliary\Build\vcvarsall.bat 2^>nul') do set VS=%%i

if not defined VS (
    echo ERROR: Could not find vcvarsall.bat. Please install Visual Studio with C++ build tools.
    exit /b 1
)
echo Found vcvarsall.bat: %VS%

echo ===== Setting up vcpkg =====

if not exist "%VCPKG_ROOT%\vcpkg.exe" (
    echo Cloning vcpkg...
    git clone https://github.com/microsoft/vcpkg "%VCPKG_ROOT%"
    call "%VCPKG_ROOT%\bootstrap-vcpkg.bat"
)

"%VCPKG_ROOT%\vcpkg.exe" integrate install

cd "%ROOT%"

echo ===== Building librdkafka =====

FOR %%C IN (Debug Release) DO (
    call :build_config %%C
    if !ERRORLEVEL! NEQ 0 goto :error
)

echo ===== Build complete =====
exit /b 0

:build_config
set CFG=%1

echo ===== Building %CFG% Win32 =====
call "%VS%" x64_x86
"%VCPKG_ROOT%\vcpkg.exe" install --triplet x86-windows || exit /b 1
msbuild "%ROOT%\win32\librdkafka.sln" /p:Configuration=%CFG% /p:Platform=Win32 /p:VcpkgEnabled=true /p:VcpkgEnableManifest=true /p:VcpkgRoot="%VCPKG_ROOT%" /p:VcpkgTriplet=x86-windows /p:VcpkgManifestInstallDependencies=false
if %ERRORLEVEL% NEQ 0 exit /b 1

echo ===== Building %CFG% x64 =====
call "%VS%" x64
"%VCPKG_ROOT%\vcpkg.exe" install --triplet x64-windows || exit /b 1
msbuild "%ROOT%\win32\librdkafka.sln" /p:Configuration=%CFG% /p:Platform=x64 /p:VcpkgEnabled=true /p:VcpkgEnableManifest=true /p:VcpkgRoot="%VCPKG_ROOT%" /p:VcpkgTriplet=x64-windows /p:VcpkgManifestInstallDependencies=false
if %ERRORLEVEL% NEQ 0 exit /b 1

echo ===== Building %CFG% ARM64 =====
call "%VS%" x64_arm64
"%VCPKG_ROOT%\vcpkg.exe" install --triplet arm64-windows || exit /b 1
msbuild "%ROOT%\win32\librdkafka.sln" /p:Configuration=%CFG% /p:Platform=ARM64 /p:VcpkgEnabled=true /p:VcpkgEnableManifest=true /p:VcpkgRoot="%VCPKG_ROOT%" /p:VcpkgTriplet=arm64-windows /p:VcpkgManifestInstallDependencies=false
if %ERRORLEVEL% NEQ 0 exit /b 1

exit /b 0

:error
echo Build failed
exit /b 1