@echo off
if not exist "build" mkdir build

echo [1/2] Assembling NASM modules...
nasm -f win64 src/main.asm -i include/ -o build/main.obj
if %errorlevel% neq 0 exit /b %errorlevel%

echo [2/2] Linking with Windows libraries...
gcc build/main.obj -o build/chip-8.exe -luser32 -lgdi32 -lkernel32 -lwinmm -mwindows

echo Build successful: build\chip8.exe
