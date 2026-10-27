@echo off
setlocal
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo ERROR: Flutter is not installed or its bin folder is not in PATH.
  echo Install Flutter from https://docs.flutter.dev/get-started/install/windows
  pause
  exit /b 1
)

echo [1/4] Checking Flutter and Android setup...
call flutter doctor
if errorlevel 1 goto failed

if not exist "android\settings.gradle" (
  echo [2/4] Generating Android project...
  call flutter create --platforms=android --org com.reqeuss .
  if errorlevel 1 goto failed
) else (
  echo [2/4] Android project already exists.
)

echo [3/4] Downloading dependencies...
call flutter pub get
if errorlevel 1 goto failed

echo [4/4] Building debug APK...
call flutter build apk --debug
if errorlevel 1 goto failed

echo.
echo SUCCESS! APK created at:
echo %~dp0build\app\outputs\flutter-apk\app-debug.apk
echo Transfer that file to your Android phone to install it.
pause
exit /b 0

:failed
echo.
echo Build failed. Read the error shown above and check flutter doctor.
pause
exit /b 1
