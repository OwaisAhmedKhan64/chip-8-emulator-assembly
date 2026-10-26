%ifndef PLATFORM_INC
%define PLATFORM_INC

%include "chip8.inc"

; Display Constants
PLATFORM_SCALE              equ 10
PLATFORM_WINDOW_WIDTH       equ (CHIP8_DISPLAY_WIDTH * PLATFORM_SCALE)      ; 640
PLATFORM_WINDOW_HEIGHT      equ (CHIP8_DISPLAY_HEIGHT * PLATFORM_SCALE)     ; 320
PLATFORM_FRAMEBUFFER_SIZE   equ (CHIP8_DISPLAY_WIDTH * CHIP8_DISPLAY_HEIGHT * 4) ; 8192

; Win32 Window Messages
WM_DESTROY                  equ 0x0002
WM_CLOSE                    equ 0x0010
WM_PAINT                    equ 0x000F
WM_KEYDOWN                  equ 0x0100
WM_KEYUP                    equ 0x0101
WM_QUIT                     equ 0x0012
WM_ERASEBKGND               equ 0x0014

; Win32 Window Styles
WS_OVERLAPPEDWINDOW         equ 0x00CF0000
WS_VISIBLE                  equ 0x10000000
CS_HREDRAW                  equ 0x0002
CS_VREDRAW                  equ 0x0001

; Win32 Constants
CW_USEDEFAULT               equ 0x80000000
SW_SHOW                     equ 5
PM_REMOVE                   equ 0x0001
IDC_ARROW                   equ 32512
COLOR_WINDOW                equ 5

; GDI Constants
DIB_RGB_COLORS              equ 0
SRCCOPY                     equ 0x00CC0020
BI_RGB                      equ 0

; Virtual Key Code
VK_ESCAPE                   equ 0x1B

; Audio Constants
WAVE_FORMAT_PCM             equ 1
AUDIO_SAMPLE_RATE           equ 44100
AUDIO_CHANNELS              equ 1
AUDIO_BITS_PER_SAMPLE       equ 16
AUDIO_BUFFER_SAMPLES        equ 4096
AUDIO_TONE_FREQUENCY        equ 440
WAVE_MAPPER                 equ 0xFFFFFFFF
CALLBACK_NULL               equ 0
WHDR_DONE                   equ 0x00000001
WHDR_PREPARED               equ 0x00000002
WHDR_BEGINLOOP              equ 0x00000004
WHDR_ENDLOOP                equ 0x00000008

; CHIP-8 Key Mapping Table (indexed by CHIP-8 key 0x0 to 0xF)
; Returns the corresponding Windows Virtual Key code
;
; Keyboard Layout:        CHIP-8 Keypad:
;   1  2  3  4              1  2  3  C
;   Q  W  E  R              4  5  6  D
;   A  S  D  F              7  8  9  E
;   Z  X  C  V              A  0  B  F

%macro PLATFORM_EMBED_KEYMAP 0
    db 0x58                 ; CHIP-8 key 0x0 -> 'X'
    db 0x31                 ; CHIP-8 key 0x1 -> '1'
    db 0x32                 ; CHIP-8 key 0x2 -> '2'
    db 0x33                 ; CHIP-8 key 0x3 -> '3'
    db 0x51                 ; CHIP-8 key 0x4 -> 'Q'
    db 0x57                 ; CHIP-8 key 0x5 -> 'W'
    db 0x45                 ; CHIP-8 key 0x6 -> 'E'
    db 0x41                 ; CHIP-8 key 0x7 -> 'A'
    db 0x53                 ; CHIP-8 key 0x8 -> 'S'
    db 0x44                 ; CHIP-8 key 0x9 -> 'D'
    db 0x5A                 ; CHIP-8 key 0xA -> 'Z'
    db 0x43                 ; CHIP-8 key 0xB -> 'C'
    db 0x34                 ; CHIP-8 key 0xC -> '4'
    db 0x52                 ; CHIP-8 key 0xD -> 'R'
    db 0x46                 ; CHIP-8 key 0xE -> 'F'
    db 0x56                 ; CHIP-8 key 0xF -> 'V'
%endmacro

; Win32 Structure: WNDCLASSEXA (80 bytes on x64)
struc WNDCLASSEXA
    .cbSize:            resd 1          ; UINT       (offset 0)
    .style:             resd 1          ; UINT       (offset 4)
    .lpfnWndProc:       resq 1          ; WNDPROC    (offset 8)
    .cbClsExtra:        resd 1          ; int        (offset 16)
    .cbWndExtra:        resd 1          ; int        (offset 20)
    .hInstance:         resq 1          ; HINSTANCE  (offset 24)
    .hIcon:             resq 1          ; HICON      (offset 32)
    .hCursor:           resq 1          ; HCURSOR    (offset 40)
    .hbrBackground:     resq 1          ; HBRUSH     (offset 48)
    .lpszMenuName:      resq 1          ; LPCSTR     (offset 56)
    .lpszClassName:     resq 1          ; LPCSTR     (offset 64)
    .hIconSm:           resq 1          ; HICON      (offset 72)
endstruc

; Win32 Structure: MSG (48 bytes on x64)
struc MSG
    .hwnd:              resq 1          ; HWND       (offset 0)
    .message:           resd 1          ; UINT       (offset 8)
    .pad0:              resd 1          ;            (offset 12)
    .wParam:            resq 1          ; WPARAM     (offset 16)
    .lParam:            resq 1          ; LPARAM     (offset 24)
    .time:              resd 1          ; DWORD      (offset 32)
    .pt_x:              resd 1          ; LONG       (offset 36)
    .pt_y:              resd 1          ; LONG       (offset 40)
    .pad1:              resd 1          ;            (offset 44)
endstruc

; Win32 Structure: RECT (16 bytes)
struc RECT
    .left:              resd 1          ; LONG
    .top:               resd 1          ; LONG
    .right:             resd 1          ; LONG
    .bottom:            resd 1          ; LONG
endstruc

; Win32 Structure: BITMAPINFOHEADER (40 bytes)
struc BITMAPINFOHEADER
    .biSize:            resd 1
    .biWidth:           resd 1
    .biHeight:          resd 1
    .biPlanes:          resw 1
    .biBitCount:        resw 1
    .biCompression:     resd 1
    .biSizeImage:       resd 1
    .biXPelsPerMeter:   resd 1
    .biYPelsPerMeter:   resd 1
    .biClrUsed:         resd 1
    .biClrImportant:    resd 1
endstruc

; Win32 Structure: PAINTSTRUCT (72 bytes on x64)
struc PAINTSTRUCT
    .hdc:               resq 1          ; HDC        (offset 0)
    .fErase:            resd 1          ; BOOL       (offset 8)
    .rcPaint:           resb RECT_size  ; RECT       (offset 12)
    .fRestore:          resd 1          ; BOOL       (offset 28)
    .fIncUpdate:        resd 1          ; BOOL       (offset 32)
    .rgbReserved:       resb 32         ;            (offset 36)
    .pad:               resd 1          ;            (offset 68)
endstruc

; Win32 Structure: WAVEFORMATEX (18 bytes)
struc WAVEFORMATEX
    .wFormatTag:        resw 1
    .nChannels:         resw 1
    .nSamplesPerSec:    resd 1
    .nAvgBytesPerSec:   resd 1
    .nBlockAlign:       resw 1
    .wBitsPerSample:    resw 1
    .cbSize:            resw 1
endstruc

; Win32 Structure: WAVEHDR (48 bytes on x64)
struc WAVEHDR
    .lpData:            resq 1          ; LPSTR      (offset 0)
    .dwBufferLength:    resd 1          ; DWORD      (offset 8)
    .dwBytesRecorded:   resd 1          ; DWORD      (offset 12)
    .dwUser:            resq 1          ; DWORD_PTR  (offset 16)
    .dwFlags:           resd 1          ; DWORD      (offset 24)
    .dwLoops:           resd 1          ; DWORD      (offset 28)
    .lpNext:            resq 1          ; pointer    (offset 32)
    .reserved:          resq 1          ; DWORD_PTR  (offset 40)
endstruc

; Platform State Structure
struc PlatformState
    ; Window handles (8 bytes each)
    .hwnd:              resq 1
    .hdc:               resq 1
    .hinstance:         resq 1

    ; State flags
    .running:           resb 1
    .audio_playing:     resb 1
    .pad:               resb 6

    ; Window dimensions
    .window_width:      resd 1
    .window_height:     resd 1

    ; Embedded BITMAPINFOHEADER for StretchDIBits (40 bytes)
    .bmi:               resb BITMAPINFOHEADER_size

    ; Audio handle
    .wave_out:          resq 1          ; HWAVEOUT

    ; 32-bit ARGB framebuffer (64 * 32 * 4 = 8192 bytes)
    .framebuffer:       resb PLATFORM_FRAMEBUFFER_SIZE
endstruc

%endif ; PLATFORM_INC
