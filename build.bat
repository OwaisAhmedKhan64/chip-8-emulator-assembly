@echo off
if not exist "build" mkdir build

echo [1/2] Assembling NASM modules...
nasm -f win64 src/chip8.asm -i include/ -o build/chip8.obj
if %errorlevel% neq 0 exit /b %errorlevel%

nasm -f win64 src/platform.asm -i include/ -o build/platform.obj
if %errorlevel% neq 0 exit /b %errorlevel%

nasm -f win64 src/main.asm -i include/ -o build/main.obj
if %errorlevel% neq 0 exit /b %errorlevel%

echo [2/2] Linking with Windows libraries...
gcc build/main.obj build/chip8.obj build/platform.obj -o build/chip8.exe -luser32 -lgdi32 -lkernel32 -lwinmm -mwindows
if %errorlevel% neq 0 exit /b %errorlevel%

echo Build successful: build\chip8.exe
