default rel

%include "chip8.inc"
%include "platform.inc"

; ------------------------------------------------------------------------------
; Read-Only Constants & Strings
; ------------------------------------------------------------------------------
section .rdata
window_title:
    db "CHIP-8 Emulator", 0

err_title:
    db "CHIP-8 Error", 0

err_usage_msg:
    db "Invalid number of arguments.", 10
    db "Usage: chip8.exe <ROM_PATH>", 0

err_load_msg:
    db "Could not load the specified ROM file.", 10
    db "Please check the file path and ensure it is a valid CHIP-8 ROM.", 0

; Win32 File Constants
GENERIC_READ                equ 0x80000000
FILE_SHARE_READ             equ 0x00000001
OPEN_EXISTING               equ 3
FILE_ATTRIBUTE_NORMAL       equ 0x00000080
INVALID_HANDLE_VALUE        equ -1
INVALID_FILE_SIZE           equ 0xFFFFFFFF
MB_ICONERROR                equ 0x00000010

; Emulation & Timing Constants
TARGET_FPS                  equ 60
TARGET_FRAME_TIME_MS        equ (1000 / TARGET_FPS) ; 16 ms
CYCLES_PER_FRAME            equ 12                  ; 12 * 60 = 720 Hz CPU clock
MAX_ROM_SIZE                equ (CHIP8_MEMORY_SIZE - CHIP8_START_ADDRESS) ; 3584 bytes

; ------------------------------------------------------------------------------
; Uninitialized Static Data
; ------------------------------------------------------------------------------
section .bss
align 16
chip8_state:        resb Chip8State_size        ; Defined in chip8.inc
platform_state:     resb PlatformState_size     ; Defined in platform.inc

; ------------------------------------------------------------------------------
; External Imports
; ------------------------------------------------------------------------------
; User32
extern MessageBoxA

; Kernel32
extern CreateFileA
extern GetFileSize
extern ReadFile
extern CloseHandle
extern Sleep
extern ExitProcess

; WinMM
extern timeGetTime

; CHIP-8 Core (src/chip8.asm)
extern chip8_init
extern chip8_cycle
extern chip8_decrement_timers
extern chip8_get_sound_timer

; Platform Layer (src/platform.asm)
extern platform_init
extern platform_destroy
extern platform_update
extern platform_process_input
extern platform_beep

; ------------------------------------------------------------------------------
; Code Section
; ------------------------------------------------------------------------------
section .text
global main

; ==============================================================================
; Helper Function: load_rom
; Opens a binary file and reads it directly into chip8_state.memory starting at 0x200
;
; Parameters (Windows x64 ABI):
;   RCX = const char* filepath (LPCSTR)
;
; Returns:
;   EAX = 1 on success, 0 on failure
;
; Register Usage across function:
;   RBX = File Handle (callee-saved)
;   R12 = File Size in bytes (callee-saved)
;   R13 = ROM file path pointer (callee-saved)
; ==============================================================================
load_rom:
    push rbx
    push r12
    push r13
    sub rsp, 64                                 ; 32 shadow + 24 params + 8 scratch

    mov r13, rcx                                ; Save filepath pointer

    ; 1. Open file via CreateFileA
    mov rcx, r13                                ; lpFileName
    mov edx, GENERIC_READ                       ; dwDesiredAccess
    mov r8d, FILE_SHARE_READ                    ; dwShareMode
    xor r9d, r9d                                ; lpSecurityAttributes = NULL
    mov qword [rsp + 32], OPEN_EXISTING         ; dwCreationDisposition
    mov qword [rsp + 40], FILE_ATTRIBUTE_NORMAL ; dwFlagsAndAttributes
    mov qword [rsp + 48], 0                     ; hTemplateFile = NULL
    call CreateFileA

    cmp rax, INVALID_HANDLE_VALUE
    je .file_error
    mov rbx, rax                                ; RBX = hFile

    ; 2. Determine file size via GetFileSize
    mov rcx, rbx
    xor edx, edx                                ; lpFileSizeHigh = NULL
    call GetFileSize

    cmp eax, INVALID_FILE_SIZE
    je .read_error
    test eax, eax                               ; Empty file check
    jz .read_error
    cmp eax, MAX_ROM_SIZE                       ; Must fit in RAM (max 3584 bytes)
    ja .read_error

    mov r12d, eax                               ; R12D = file size (bytes to read)

    ; 3. Stream bytes into CHIP-8 memory at 0x200
    mov rcx, rbx                                ; hFile
    lea rdx, [chip8_state + Chip8State.memory + CHIP8_START_ADDRESS] ; lpBuffer
    mov r8d, r12d                               ; nNumberOfBytesToRead
    lea r9, [rsp + 56]                          ; lpNumberOfBytesRead (&bytes_read)
    mov qword [rsp + 32], 0                     ; lpOverlapped = NULL
    call ReadFile

    test eax, eax
    jz .read_error

    ; Verify all bytes were read
    mov eax, [rsp + 56]
    cmp eax, r12d
    jne .read_error

    ; 4. Close file and return success (1)
    mov rcx, rbx
    call CloseHandle
    mov eax, 1
    jmp .done

.read_error:
    mov rcx, rbx
    call CloseHandle

.file_error:
    xor eax, eax                                ; Return failure (0)

.done:
    add rsp, 64
    pop r13
    pop r12
    pop rbx
    ret

; ==============================================================================
; Program Entry Point: main
;
; Parameters (MinGW C Runtime CRT0):
;   ECX = int   argc
;   RDX = char* argv[]
;
; Register Map across main():
;   RBX  = Pointer to ROM filepath (argv[1])
;   R12D = Frame start timestamp (ms)
;   R13D = Cycle counter for inner CPU loop
; ==============================================================================
main:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 48                                 ; 32 shadow + 16 locals/alignment

    ; 1. Validate argument count (argc >= 2)
    cmp ecx, 2
    jge .args_valid

    ; Show usage error dialog
    xor ecx, ecx                                ; hWnd = NULL
    lea rdx, [err_usage_msg]                    ; lpText
    lea r8, [err_title]                         ; lpCaption
    mov r9d, MB_ICONERROR                       ; uType
    call MessageBoxA

    mov eax, -1
    jmp .exit_app

.args_valid:
    ; Extract argv[1] (ROM path)
    mov rbx, [rdx + 8]                          ; RBX = argv[1]

    ; 2. Initialize Platform (Window, GDI, WinMM Audio)
    lea rcx, [platform_state]
    lea rdx, [window_title]
    mov r8d, PLATFORM_WINDOW_WIDTH              ; 640
    mov r9d, PLATFORM_WINDOW_HEIGHT             ; 320
    call platform_init

    test eax, eax
    jz .init_failed

    ; 3. Initialize CHIP-8 CPU State
    lea rcx, [chip8_state]
    call chip8_init

    ; 4. Load ROM into CHIP-8 Memory
    mov rcx, rbx
    call load_rom

    test eax, eax
    jnz .game_loop_start

    ; Show load error dialog
    xor ecx, ecx                                ; hWnd = NULL
    lea rdx, [err_load_msg]                     ; lpText
    lea r8, [err_title]                         ; lpCaption
    mov r9d, MB_ICONERROR                       ; uType
    call MessageBoxA

    ; Teardown window and exit
    lea rcx, [platform_state]
    call platform_destroy
    mov eax, -1
    jmp .exit_app

.init_failed:
    mov eax, -1
    jmp .exit_app

; ==============================================================================
; 5. Main Emulation Loop (60 Hz Game Loop)
; ==============================================================================
.game_loop_start:

.frame_loop:
    ; A. Record frame start time (in milliseconds)
    call timeGetTime
    mov r12d, eax                               ; R12D = frameStart

    ; B. Process Windows input & window messages
    lea rcx, [platform_state]
    lea rdx, [chip8_state + Chip8State.keypad]
    call platform_process_input

    ; If quit requested (WM_QUIT or VK_ESCAPE), break out of loop
    test al, al
    jnz .game_loop_end

    ; C. Emulate CPU Cycles (12 instructions per 60Hz frame = 720 Hz)
    mov r13d, CYCLES_PER_FRAME
.cpu_cycle_loop:
    lea rcx, [chip8_state]
    call chip8_cycle
    dec r13d
    jnz .cpu_cycle_loop

    ; D. Decrement Delay and Sound Timers at 60 Hz
    lea rcx, [chip8_state]
    call chip8_decrement_timers

    ; E. Audio Playback: Beep if sound_timer > 0
    lea rcx, [chip8_state]
    call chip8_get_sound_timer
    test eax, eax
    setg dl                                     ; DL = 1 if sound_timer > 0, else 0
    movzx edx, dl                               ; EDX = bool play

    lea rcx, [platform_state]
    call platform_beep

    ; F. Render Display Buffer (Scales monochrome to 32-bit ARGB on the fly)
    lea rcx, [platform_state]
    lea rdx, [chip8_state + Chip8State.display]
    mov r8d, CHIP8_DISPLAY_WIDTH               ; pitch = 64 bytes
    call platform_update

    ; G. Frame Pacing: Enforce 60 FPS (TARGET_FRAME_TIME_MS = 16 ms)
    call timeGetTime
    sub eax, r12d                               ; EAX = elapsed time (timeGetTime - frameStart)

    cmp eax, TARGET_FRAME_TIME_MS
    jae .skip_delay

    mov ecx, TARGET_FRAME_TIME_MS
    sub ecx, eax                                ; ECX = delay needed
    call Sleep

.skip_delay:
    jmp .frame_loop

; ==============================================================================
; 6. Teardown and Clean Exit
; ==============================================================================
.game_loop_end:
    lea rcx, [platform_state]
    call platform_destroy
    xor eax, eax                                ; Return 0

.exit_app:
    add rsp, 48
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret