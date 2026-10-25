%ifndef CHIP8_INC
%define CHIP8_INC

; Hardware Constants
CHIP8_MEMORY_SIZE           equ 4096
CHIP8_REGISTER_COUNT        equ 16
CHIP8_STACK_SIZE            equ 16
CHIP8_DISPLAY_WIDTH         equ 64
CHIP8_DISPLAY_HEIGHT        equ 32
CHIP8_DISPLAY_PIXELS        equ (CHIP8_DISPLAY_WIDTH * CHIP8_DISPLAY_HEIGHT) ; 2048 bytes
CHIP8_KEYPAD_SIZE           equ 16
CHIP8_FONTSET_SIZE          equ 80
CHIP8_FONTSET_START_ADDRESS equ 0x050
CHIP8_START_ADDRESS         equ 0x200

; Chip8State Structure

struc Chip8State
    ; 4KB RAM (0x000 - 0xFFF)
    .memory:            resb CHIP8_MEMORY_SIZE          ; 4096 bytes

    ; General purpose 8-bit registers (V0 - VF)
    .v:                 resb CHIP8_REGISTER_COUNT       ; 16 bytes

    ; 16-bit registers
    .i:                 resw 1                          ; 2 bytes
    .pc:                resw 1                          ; 2 bytes

    ; Call stack: 16 levels of 16-bit return addresses
    .stack:             resw CHIP8_STACK_SIZE           ; 32 bytes

    ; 8-bit registers and state flags
    .sp:                    resb 1                      ; 1 byte
    .delay_timer:           resb 1                      ; 1 byte
    .sound_timer:           resb 1                      ; 1 byte
    .has_drawn_this_frame:  resb 1                      ; 1 byte
    .key_pressed:           resb 1                      ; 1 byte

    ; 16-key hexadecimal keypad state
    .keypad:            resb CHIP8_KEYPAD_SIZE          ; 16 bytes

    ; Monochrome display buffer 
    .display:           resb CHIP8_DISPLAY_PIXELS       ; 2048 bytes

    ; 32-bit PRNG state
    .rng_seed:          resd 1                          ; 4 bytes
endstruc

%macro CHIP8_EMBED_FONTSET 0
    db 0xF0, 0x90, 0x90, 0x90, 0xF0 ; 0
    db 0x20, 0x60, 0x20, 0x20, 0x70 ; 1
    db 0xF0, 0x10, 0xF0, 0x80, 0xF0 ; 2
    db 0xF0, 0x10, 0xF0, 0x10, 0xF0 ; 3
    db 0x90, 0x90, 0xF0, 0x10, 0x10 ; 4
    db 0xF0, 0x80, 0xF0, 0x10, 0xF0 ; 5
    db 0xF0, 0x80, 0xF0, 0x90, 0xF0 ; 6
    db 0xF0, 0x10, 0x20, 0x40, 0x40 ; 7
    db 0xF0, 0x90, 0xF0, 0x90, 0xF0 ; 8
    db 0xF0, 0x90, 0xF0, 0x10, 0xF0 ; 9
    db 0xF0, 0x90, 0xF0, 0x90, 0x90 ; A
    db 0xE0, 0x90, 0xE0, 0x90, 0xE0 ; B
    db 0xF0, 0x80, 0x80, 0x80, 0xF0 ; C
    db 0xE0, 0x90, 0x90, 0x90, 0xE0 ; D
    db 0xF0, 0x80, 0xF0, 0x80, 0xF0 ; E
    db 0xF0, 0x80, 0xF0, 0x80, 0x80 ; F
%endmacro

%endif ; CHIP8_INC
