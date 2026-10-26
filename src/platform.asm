default rel

%include "platform.inc"

; ------------------------------------------------------------------------------
; Read-Only Data Section
; ------------------------------------------------------------------------------
section .rdata
class_name:
    db "Chip8WindowClass", 0

default_title:
    db "CHIP-8 Emulator", 0

align 8
keymap_table:
    PLATFORM_EMBED_KEYMAP

; ------------------------------------------------------------------------------
; BSS Section (Uninitialized Data)
; ------------------------------------------------------------------------------
section .bss
align 8
wnd_class:          resb WNDCLASSEXA_size       ; 80 bytes
wfx:                resb WAVEFORMATEX_size      ; 18 bytes
wave_hdr:           resb WAVEHDR_size           ; 48 bytes
audio_buffer:       resw AUDIO_BUFFER_SAMPLES   ; 4096 * 2 = 8192 bytes

; ------------------------------------------------------------------------------
; Win32 API Imports
; ------------------------------------------------------------------------------
; User32
extern RegisterClassExA
extern UnregisterClassA
extern CreateWindowExA
extern DestroyWindow
extern ShowWindow
extern UpdateWindow
extern GetDC
extern ReleaseDC
extern DefWindowProcA
extern PostQuitMessage
extern PeekMessageA
extern TranslateMessage
extern DispatchMessageA
extern LoadCursorA
extern AdjustWindowRect
extern ValidateRect

; Kernel32
extern GetModuleHandleA

; Gdi32
extern StretchDIBits

; Winmm
extern waveOutOpen
extern waveOutPrepareHeader
extern waveOutUnprepareHeader
extern waveOutWrite
extern waveOutPause
extern waveOutRestart
extern waveOutReset
extern waveOutClose

; ------------------------------------------------------------------------------
; Exported Functions
; ------------------------------------------------------------------------------
section .text
global platform_init
global platform_destroy
global platform_update
global platform_process_input
global platform_beep

; ==============================================================================
; Internal Window Procedure (wnd_proc)
;
; Parameters (Windows x64 ABI):
;   RCX = HWND   hwnd
;   EDX = UINT   uMsg
;   R8  = WPARAM wParam
;   R9  = LPARAM lParam
; ==============================================================================
wnd_proc:
    sub rsp, 40

    cmp edx, WM_ERASEBKGND
    je .on_erasebkgnd
    cmp edx, WM_PAINT
    je .on_paint
    cmp edx, WM_CLOSE
    je .on_close
    cmp edx, WM_DESTROY
    je .on_destroy

    call DefWindowProcA
    add rsp, 40
    ret

.on_erasebkgnd:
    ; Return 1 to prevent Windows from clearing background (eliminates flicker)
    mov eax, 1
    add rsp, 40
    ret

.on_paint:
    ; Validate the client rect so Windows stops re-issuing WM_PAINT
    xor edx, edx                                ; lpRect = NULL
    call ValidateRect
    xor eax, eax
    add rsp, 40
    ret

.on_close:
    call DestroyWindow
    xor eax, eax
    add rsp, 40
    ret

.on_destroy:
    xor ecx, ecx                                ; Exit code = 0
    call PostQuitMessage
    xor eax, eax
    add rsp, 40
    ret

; ==============================================================================
; Platform Constructor / Initializer
; Equivalent to: Platform::Platform(...)
;
; Parameters (Windows x64 ABI):
;   RCX = PlatformState* state
;   RDX = const char*    title (NULL = default)
;   R8D = int            windowWidth (0 = default 640)
;   R9D = int            windowHeight (0 = default 320)
;
; Returns:
;   EAX = 1 on success, 0 on failure
; ==============================================================================
platform_init:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 112                                ; 32 shadow + 80 stack parameters/locals

    mov rbx, rcx                                ; RBX = PlatformState*
    mov rsi, rdx                                ; RSI = title
    mov r12d, r8d                               ; R12D = windowWidth
    mov r13d, r9d                               ; R13D = windowHeight

    ; 1. Apply defaults if parameters are NULL / 0
    test rsi, rsi
    jnz .title_set
    lea rsi, [default_title]
.title_set:

    test r12d, r12d
    jnz .width_set
    mov r12d, PLATFORM_WINDOW_WIDTH
.width_set:

    test r13d, r13d
    jnz .height_set
    mov r13d, PLATFORM_WINDOW_HEIGHT
.height_set:

    mov [rbx + PlatformState.window_width], r12d
    mov [rbx + PlatformState.window_height], r13d
    mov byte [rbx + PlatformState.running], 1
    mov byte [rbx + PlatformState.audio_playing], 0

    ; 2. Obtain hInstance
    xor ecx, ecx
    call GetModuleHandleA
    mov [rbx + PlatformState.hinstance], rax

    ; 3. Setup WNDCLASSEXA
    mov dword [wnd_class + WNDCLASSEXA.cbSize], WNDCLASSEXA_size
    mov dword [wnd_class + WNDCLASSEXA.style], (CS_HREDRAW | CS_VREDRAW)
    lea rax, [wnd_proc]
    mov [wnd_class + WNDCLASSEXA.lpfnWndProc], rax
    mov rax, [rbx + PlatformState.hinstance]
    mov [wnd_class + WNDCLASSEXA.hInstance], rax

    ; Cursor = IDC_ARROW
    xor ecx, ecx
    mov edx, IDC_ARROW
    call LoadCursorA
    mov [wnd_class + WNDCLASSEXA.hCursor], rax

    mov qword [wnd_class + WNDCLASSEXA.hbrBackground], 0 ; NULL brush avoids redraw flash
    lea rax, [class_name]
    mov [wnd_class + WNDCLASSEXA.lpszClassName], rax

    lea rcx, [wnd_class]
    call RegisterClassExA

    ; 4. Calculate full window frame rect for an exact client canvas
    mov dword [rsp + 32 + RECT.left], 0
    mov dword [rsp + 32 + RECT.top], 0
    mov dword [rsp + 32 + RECT.right], r12d
    mov dword [rsp + 32 + RECT.bottom], r13d

    lea rcx, [rsp + 32]                          ; LPRECT
    mov edx, WS_OVERLAPPEDWINDOW                 ; dwStyle
    xor r8d, r8d                                 ; bMenu = FALSE
    call AdjustWindowRect

    ; Save adjusted width & height in R12D and R13D (safe from RDX clobbering)
    mov r12d, [rsp + 32 + RECT.right]
    sub r12d, [rsp + 32 + RECT.left]             ; R12D = Total Window Frame Width
    mov r13d, [rsp + 32 + RECT.bottom]
    sub r13d, [rsp + 32 + RECT.top]              ; R13D = Total Window Frame Height

    ; 5. Create Window
    xor ecx, ecx                                 ; dwExStyle = 0
    lea rdx, [class_name]                        ; lpClassName (RDX is now safe to set)
    mov r8, rsi                                  ; lpWindowName
    mov r9d, (WS_OVERLAPPEDWINDOW | WS_VISIBLE)  ; dwStyle

    mov eax, CW_USEDEFAULT
    mov [rsp + 32], rax                          ; X
    mov [rsp + 40], rax                          ; Y
    movsxd rax, r12d
    mov [rsp + 48], rax                          ; nWidth
    movsxd rax, r13d
    mov [rsp + 56], rax                          ; nHeight
    mov qword [rsp + 64], 0                      ; hWndParent
    mov qword [rsp + 72], 0                      ; hMenu
    mov rax, [rbx + PlatformState.hinstance]
    mov [rsp + 80], rax                          ; hInstance
    mov qword [rsp + 88], 0                      ; lpParam
    call CreateWindowExA

    test rax, rax
    jz .init_failed
    mov [rbx + PlatformState.hwnd], rax

    ; Show and update window
    mov rcx, [rbx + PlatformState.hwnd]
    mov edx, SW_SHOW
    call ShowWindow

    mov rcx, [rbx + PlatformState.hwnd]
    call UpdateWindow

    ; Obtain Device Context
    mov rcx, [rbx + PlatformState.hwnd]
    call GetDC
    mov [rbx + PlatformState.hdc], rax

    ; 6. Configure BITMAPINFOHEADER for StretchDIBits (top-down 32-bit ARGB)
    lea rdi, [rbx + PlatformState.bmi]
    mov dword [rdi + BITMAPINFOHEADER.biSize], BITMAPINFOHEADER_size
    mov dword [rdi + BITMAPINFOHEADER.biWidth], CHIP8_DISPLAY_WIDTH
    mov dword [rdi + BITMAPINFOHEADER.biHeight], -CHIP8_DISPLAY_HEIGHT ; Negative = top-down
    mov word  [rdi + BITMAPINFOHEADER.biPlanes], 1
    mov word  [rdi + BITMAPINFOHEADER.biBitCount], 32
    mov dword [rdi + BITMAPINFOHEADER.biCompression], BI_RGB
    mov dword [rdi + BITMAPINFOHEADER.biSizeImage], PLATFORM_FRAMEBUFFER_SIZE

    ; 7. Configure Audio (44100 Hz, 16-bit Mono PCM)
    mov word  [wfx + WAVEFORMATEX.wFormatTag], WAVE_FORMAT_PCM
    mov word  [wfx + WAVEFORMATEX.nChannels], AUDIO_CHANNELS
    mov dword [wfx + WAVEFORMATEX.nSamplesPerSec], AUDIO_SAMPLE_RATE
    mov dword [wfx + WAVEFORMATEX.nAvgBytesPerSec], (AUDIO_SAMPLE_RATE * AUDIO_CHANNELS * (AUDIO_BITS_PER_SAMPLE / 8))
    mov word  [wfx + WAVEFORMATEX.nBlockAlign], (AUDIO_CHANNELS * (AUDIO_BITS_PER_SAMPLE / 8))
    mov word  [wfx + WAVEFORMATEX.wBitsPerSample], AUDIO_BITS_PER_SAMPLE
    mov word  [wfx + WAVEFORMATEX.cbSize], 0

    lea rcx, [rbx + PlatformState.wave_out]
    mov edx, WAVE_MAPPER
    lea r8, [wfx]
    xor r9d, r9d
    mov qword [rsp + 32], 0
    mov qword [rsp + 40], CALLBACK_NULL
    call waveOutOpen
    test eax, eax
    jnz .init_success                           ; If audio device fails, video still runs

    ; Generate 441Hz square wave matching audioCallback (50-sample half-period)
    lea rdi, [audio_buffer]
    xor ecx, ecx
.gen_audio:
    cmp ecx, AUDIO_BUFFER_SAMPLES
    jge .gen_audio_done
    mov eax, ecx
    xor edx, edx
    mov r8d, 50                                 ; 44100 / (441 * 2) = 50 samples
    div r8d
    test eax, 1
    jnz .neg_sample
    mov word [rdi + rcx * 2], 3000              ; +AMPLITUDE
    jmp .sample_next
.neg_sample:
    mov word [rdi + rcx * 2], -3000             ; -AMPLITUDE
.sample_next:
    inc ecx
    jmp .gen_audio
.gen_audio_done:

    ; Prepare looping audio header
    lea rax, [audio_buffer]
    mov [wave_hdr + WAVEHDR.lpData], rax
    mov dword [wave_hdr + WAVEHDR.dwBufferLength], (AUDIO_BUFFER_SAMPLES * 2)
    mov dword [wave_hdr + WAVEHDR.dwFlags], (WHDR_BEGINLOOP | WHDR_ENDLOOP)
    mov dword [wave_hdr + WAVEHDR.dwLoops], 0xFFFFFFFF ; Infinite loop

    mov rcx, [rbx + PlatformState.wave_out]
    lea rdx, [wave_hdr]
    mov r8d, WAVEHDR_size
    call waveOutPrepareHeader

    ; Pause initially so the tone is silent until beep(true) is invoked
    mov rcx, [rbx + PlatformState.wave_out]
    call waveOutPause

    mov rcx, [rbx + PlatformState.wave_out]
    lea rdx, [wave_hdr]
    mov r8d, WAVEHDR_size
    call waveOutWrite

.init_success:
    mov eax, 1
    jmp .init_done

.init_failed:
    xor eax, eax

.init_done:
    add rsp, 112
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; ==============================================================================
; Platform Destructor / Cleanup
; Equivalent to: Platform::~Platform()
;
; Parameters (Windows x64 ABI):
;   RCX = PlatformState* state
; ==============================================================================
platform_destroy:
    push rbx
    sub rsp, 32

    mov rbx, rcx
    test rbx, rbx
    jz .cleanup_done

    ; 1. Audio Cleanup
    mov rcx, [rbx + PlatformState.wave_out]
    test rcx, rcx
    jz .skip_audio

    call waveOutReset
    mov rcx, [rbx + PlatformState.wave_out]
    lea rdx, [wave_hdr]
    mov r8d, WAVEHDR_size
    call waveOutUnprepareHeader
    mov rcx, [rbx + PlatformState.wave_out]
    call waveOutClose
    mov qword [rbx + PlatformState.wave_out], 0

.skip_audio:
    ; 2. Release GDI Device Context
    mov rcx, [rbx + PlatformState.hwnd]
    mov rdx, [rbx + PlatformState.hdc]
    test rdx, rdx
    jz .skip_dc
    call ReleaseDC
    mov qword [rbx + PlatformState.hdc], 0

.skip_dc:
    ; 3. Destroy Window
    mov rcx, [rbx + PlatformState.hwnd]
    test rcx, rcx
    jz .skip_window
    call DestroyWindow
    mov qword [rbx + PlatformState.hwnd], 0

.skip_window:
    ; 4. Unregister Window Class
    lea rcx, [class_name]
    mov rdx, [rbx + PlatformState.hinstance]
    call UnregisterClassA

.cleanup_done:
    add rsp, 32
    pop rbx
    ret

; ==============================================================================
; Platform Update / Render
; Equivalent to: Platform::update(const void* buffer, int pitch)
;
; Parameters (Windows x64 ABI):
;   RCX = PlatformState* state
;   RDX = const void*    buffer (Monochrome 2048-byte buffer or 32-bit ARGB buffer)
;   R8D = int            pitch  (64 for monochrome, 256 for 32-bit ARGB)
; ==============================================================================
platform_update:
    push rbx
    push rsi
    push rdi
    sub rsp, 112                                ; Shadow space + StretchDIBits stack args

    mov rbx, rcx                                ; RBX = PlatformState*
    mov rsi, rdx                                ; RSI = buffer
    mov edi, r8d                                ; EDI = pitch

    test rsi, rsi
    jz .use_internal_fb

    ; If pitch <= 64, expand CHIP-8 monochrome bytes (0x00/0xFF) into 32-bit ARGB
    cmp edi, CHIP8_DISPLAY_WIDTH
    ja .is_direct_32bit

    lea rdi, [rbx + PlatformState.framebuffer]
    xor ecx, ecx
.convert_loop:
    cmp ecx, CHIP8_DISPLAY_PIXELS
    jge .use_internal_fb
    movzx eax, byte [rsi + rcx]
    test al, al
    jz .pixel_black
    mov dword [rdi + rcx * 4], 0xFFFFFFFF       ; White
    jmp .next_pixel
.pixel_black:
    mov dword [rdi + rcx * 4], 0xFF000000       ; Black
.next_pixel:
    inc ecx
    jmp .convert_loop

.is_direct_32bit:
    mov r10, rsi                                ; Use external 32-bit buffer directly
    jmp .blit

.use_internal_fb:
    lea r10, [rbx + PlatformState.framebuffer]

.blit:
    mov rcx, [rbx + PlatformState.hdc]          ; hdc
    xor edx, edx                                ; xDest = 0
    xor r8d, r8d                                ; yDest = 0
    mov r9d, [rbx + PlatformState.window_width] ; DestWidth

    mov eax, [rbx + PlatformState.window_height]
    mov [rsp + 32], rax                         ; DestHeight
    mov qword [rsp + 40], 0                     ; xSrc = 0
    mov qword [rsp + 48], 0                     ; ySrc = 0
    mov qword [rsp + 56], CHIP8_DISPLAY_WIDTH   ; SrcWidth = 64
    mov qword [rsp + 64], CHIP8_DISPLAY_HEIGHT  ; SrcHeight = 32
    mov [rsp + 72], r10                         ; lpBits
    lea rax, [rbx + PlatformState.bmi]
    mov [rsp + 80], rax                         ; lpbmi
    mov qword [rsp + 88], DIB_RGB_COLORS        ; iUsage = 0
    mov qword [rsp + 96], SRCCOPY               ; rop = 0x00CC0020
    call StretchDIBits

    add rsp, 112
    pop rdi
    pop rsi
    pop rbx
    ret

; ==============================================================================
; Platform Process Input
; Equivalent to: bool Platform::processInput(uint8_t* keys)
;
; Parameters (Windows x64 ABI):
;   RCX = PlatformState* state
;   RDX = uint8_t*       keys (16-byte keypad array)
;
; Returns:
;   AL = 1 if quit requested (WM_QUIT or VK_ESCAPE), else 0
; ==============================================================================
platform_process_input:
    push rbx
    push rsi
    push r12
    sub rsp, 96                                 ; 32 shadow + 8 param5 + 48 MSG + 8 align

    mov rbx, rcx                                ; RBX = PlatformState*
    mov rsi, rdx                                ; RSI = keys*
    xor r12d, r12d                              ; R12D = quit flag (false)

.poll_loop:
    lea rcx, [rsp + 40]                         ; lpMsg = &msg
    xor edx, edx                                ; hWnd = NULL (all thread windows)
    xor r8d, r8d                                ; wMsgFilterMin = 0
    xor r9d, r9d                                ; wMsgFilterMax = 0
    mov qword [rsp + 32], PM_REMOVE             ; wRemoveMsg = PM_REMOVE
    call PeekMessageA
    test eax, eax
    jz .poll_done

    ; Handle WM_QUIT
    cmp dword [rsp + 40 + MSG.message], WM_QUIT
    je .handle_quit

    ; Handle WM_KEYDOWN
    cmp dword [rsp + 40 + MSG.message], WM_KEYDOWN
    je .key_down

    ; Handle WM_KEYUP
    cmp dword [rsp + 40 + MSG.message], WM_KEYUP
    je .key_up

    jmp .dispatch

.key_down:
    mov r10b, 1
    jmp .translate_key

.key_up:
    xor r10b, r10b

.translate_key:
    mov rax, [rsp + 40 + MSG.wParam]            ; RAX = Virtual Key code

    cmp eax, VK_ESCAPE
    je .handle_quit

    test rsi, rsi
    jz .dispatch

    ; Map Virtual Key code to CHIP-8 key index (0x0 to 0xF)
    lea r11, [keymap_table]
    xor ecx, ecx
.key_search:
    cmp ecx, CHIP8_KEYPAD_SIZE
    jge .dispatch
    cmp al, byte [r11 + rcx]
    je .key_found
    inc ecx
    jmp .key_search

.key_found:
    mov byte [rsi + rcx], r10b                  ; keys[ecx] = state

.dispatch:
    lea rcx, [rsp + 40]
    call TranslateMessage
    lea rcx, [rsp + 40]
    call DispatchMessageA
    jmp .poll_loop

.handle_quit:
    mov r12d, 1
    mov byte [rbx + PlatformState.running], 0
    jmp .poll_loop

.poll_done:
    mov eax, r12d
    add rsp, 96
    pop r12
    pop rsi
    pop rbx
    ret

; ==============================================================================
; Platform Beep
; Equivalent to: Platform::beep(bool play)
;
; Parameters (Windows x64 ABI):
;   RCX = PlatformState* state
;   EDX = bool           play (1 = play, 0 = pause)
; ==============================================================================
platform_beep:
    sub rsp, 40

    mov rax, [rcx + PlatformState.wave_out]
    test rax, rax
    jz .beep_done

    test edx, edx
    jz .stop_sound

.start_sound:
    cmp byte [rcx + PlatformState.audio_playing], 1
    je .beep_done
    mov byte [rcx + PlatformState.audio_playing], 1
    mov rcx, rax
    call waveOutRestart
    jmp .beep_done

.stop_sound:
    cmp byte [rcx + PlatformState.audio_playing], 0
    je .beep_done
    mov byte [rcx + PlatformState.audio_playing], 0
    mov rcx, rax
    call waveOutPause

.beep_done:
    add rsp, 40
    ret