default rel

%include "chip8.inc"

; ------------------------------------------------------------------------------
; Read-Only Data Section
; ------------------------------------------------------------------------------
section .rdata
fontset_data:
    CHIP8_EMBED_FONTSET

; 16-entry Jump Table for opcode categories (0x0 to 0xF)
align 8
op_table:
    dq op_0
    dq op_1
    dq op_2
    dq op_3
    dq op_4
    dq op_5
    dq op_6
    dq op_7
    dq op_8
    dq op_9
    dq op_a
    dq op_b
    dq op_c
    dq op_d
    dq op_e
    dq op_f

; ------------------------------------------------------------------------------
; Executable Code Section
; ------------------------------------------------------------------------------
section .text
global chip8_init
global chip8_decrement_timers
global chip8_get_sound_timer
global chip8_cycle

; ==============================================================================
; Initialize Method
;
; Parameters (Windows x64 ABI):
;   RCX = pointer to Chip8State instance
;
; Register Map across init():
;   RBX = Pointer to Chip8State (callee-saved)
;   RDI = Destination pointer for rep stosb / rep movsb (callee-saved)
;   RSI = Source pointer for fontset rep movsb (callee-saved)
;   RAX = Zero value for stosb (volatile)
;   RCX = Byte count for rep stosb / rep movsb (volatile)
; ==============================================================================
chip8_init:
    ; Preserve non-volatile registers
    push rdi
    push rsi
    push rbx

    mov rbx, rcx                                ; Save state pointer in RBX

    ; Zero out the entire Chip8State struct
    mov rdi, rbx                                ; Destination address = start of Chip8State
    xor eax, eax                                ; AL = 0
    mov ecx, Chip8State_size                    ; ECX = total number of bytes to fill
    rep stosb                                   ; Repeat store byte: fills struct with 0x00

    ; Copy the 80 fontset bytes into memory at address 0x050
    lea rsi, [fontset_data]                                             ; RSI = source (read-only fontset data)
    lea rdi, [rbx + Chip8State.memory + CHIP8_FONTSET_START_ADDRESS]    ; RDI = destination (RAM at 0x050)
    mov ecx, CHIP8_FONTSET_SIZE                                         ; ECX = count (80 bytes)
    rep movsb                                                           ; Repeat move string byte: copies 80 bytes

    ; Set Program Counter (PC) to 0x200
    mov word [rbx + Chip8State.pc], CHIP8_START_ADDRESS

    ; Set key_pressed = -1
    mov byte [rbx + Chip8State.key_pressed], -1

    ; Initialize PRNG seed with a non-zero value
    mov dword [rbx + Chip8State.rng_seed], 0x12345678

    ; Restore non-volatile registers and return to caller
    pop rbx
    pop rsi
    pop rdi
    ret

; ==============================================================================
; Decrement Timers Method
;
; Parameters (Windows x64 ABI):
;   RCX = pointer to Chip8State instance
;
; Register Map across decrement_timers():
;   RCX = Pointer to Chip8State instance (volatile)
;   AL  = Current timer value for zero-testing (volatile)
; ==============================================================================
chip8_decrement_timers:
    ; has_drawn_this_frame = false
    mov byte [rcx + Chip8State.has_drawn_this_frame], 0

    ; if delay_timer > 0
    mov al, [rcx + Chip8State.delay_timer]          ; Load current delayTimer
    test al, al                                     ; Is it zero?
    jz .check_sound                                 ; If AL == 0, skip decrement
    dec byte [rcx + Chip8State.delay_timer]         ; Otherwise, decrement by 1

.check_sound:
    ; if sound_timer > 0
    mov al, [rcx + Chip8State.sound_timer]          ; Load current soundTimer
    test al, al                                     ; Is it zero?
    jz .done                                        ; If AL == 0, skip decrement
    dec byte [rcx + Chip8State.sound_timer]         ; Otherwise, decrement by 1

.done:
    ret

; ==============================================================================
; Get Sound Timer Method
;
; Parameters (Windows x64 ABI):
;   RCX = pointer to Chip8State instance
;
; Returns:
;   EAX = Sound timer value (0 to 255)
;
; Register Map across get_sound_timer():
;   RCX = Pointer to Chip8State instance (volatile)
;   EAX = Return value with zero-extension (volatile)
; ==============================================================================
chip8_get_sound_timer:
    ; Load the 1-byte sound_timer into EAX
    movzx eax, byte [rcx + Chip8State.sound_timer]
    ret

; ==============================================================================
; Cycle Method
;
; Parameters (Windows x64 ABI):
;   RCX = pointer to Chip8State instance
;
; Register Map across cycle():
;   RBX  = Pointer to Chip8State (callee-saved)
;   R12D = Saved X coordinate / scratch (callee-saved)
;   R13D = Saved Y coordinate / scratch (callee-saved)
;   RSI  = Row counter / scratch (callee-saved)
;   RDI  = Column counter / destination (callee-saved)
;   EDX  = Raw 16-bit Opcode / NNN (volatile)
;   R8D  = X register index: (opcode & 0x0F00) >> 8 (volatile)
;   R9D  = Y register index: (opcode & 0x00F0) >> 4 (volatile)
;   R10D = N nibble: opcode & 0x000F (volatile)
;   R11D = NN byte: opcode & 0x00FF (volatile)
;   EAX  = Opcode category: (opcode >> 12) (volatile)
; ==============================================================================
chip8_cycle:
    ; 1. Preserve non-volatile registers
    push rbx
    push rsi
    push rdi
    push r12
    push r13

    mov rbx, rcx                                

    ; 2. Fetch 16-bit Big-Endian Opcode from memory[pc]
    movzx eax, word [rbx + Chip8State.pc]
    movzx edx, word [rbx + Chip8State.memory + rax]
    rol dx, 8                                   ; Big-Endian to Little-Endian

    ; 3. Increment Program Counter
    add word [rbx + Chip8State.pc], 2           

    ; 4. Decode Nibbles
    ; For X
    mov r8d, edx
    shr r8d, 8
    and r8d, 0x0F                               ; X = R8D

    ; For Y
    mov r9d, edx
    shr r9d, 4
    and r9d, 0x0F                               ; Y = R9D

    ; For N
    mov r10d, edx
    and r10d, 0x0F                              ; N = R10D

    ; For NN
    mov r11d, edx
    and r11d, 0xFF                              ; NN = R11D

    ; For opcode category
    mov eax, edx
    shr eax, 12                                 ; opcode category = EAX

    ; 5. Dispatch via Jump Table
    lea rcx, [op_table]
    jmp [rcx + rax * 8]

; ------------------------------------------------------------------------------
; Category 0x0: 00E0 (CLS) and 00EE (RET)
; ------------------------------------------------------------------------------
op_0:
    cmp r11b, 0xE0
    je .cls
    cmp r11b, 0xEE
    je .ret
    jmp cycle_done

.cls:
    ; Clear 2048-byte display buffer
    lea rdi, [rbx + Chip8State.display]
    xor eax, eax
    mov ecx, (CHIP8_DISPLAY_PIXELS / 8)
.cls_loop:
    mov [rdi + rcx * 8 - 8], rax
    dec ecx
    jnz .cls_loop
    jmp cycle_done

.ret:
    movzx eax, byte [rbx + Chip8State.sp]
    test eax, eax
    jz cycle_done
    dec eax
    mov byte [rbx + Chip8State.sp], al
    mov dx, word [rbx + Chip8State.stack + rax * 2]
    mov word [rbx + Chip8State.pc], dx
    jmp cycle_done

; ------------------------------------------------------------------------------
; Category 0x1: 1NNN
; ------------------------------------------------------------------------------
op_1:
    and edx, 0x0FFF                             ; EDX = NNN
    mov word [rbx + Chip8State.pc], dx
    jmp cycle_done

; ------------------------------------------------------------------------------
; Category 0x2: 2NNN
; ------------------------------------------------------------------------------
op_2:
    movzx eax, byte [rbx + Chip8State.sp]
    cmp eax, CHIP8_STACK_SIZE
    jae cycle_done
    mov cx, word [rbx + Chip8State.pc]
    mov word [rbx + Chip8State.stack + rax * 2], cx
    inc eax
    mov byte [rbx + Chip8State.sp], al
    and edx, 0x0FFF                             ; EDX = NNN
    mov word [rbx + Chip8State.pc], dx
    jmp cycle_done

; ------------------------------------------------------------------------------
; Category 0x3: 3XNN
; ------------------------------------------------------------------------------
op_3:
    mov al, byte [rbx + Chip8State.v + r8]
    cmp al, r11b
    jne cycle_done
    add word [rbx + Chip8State.pc], 2
    jmp cycle_done

; ------------------------------------------------------------------------------
; Category 0x4: 4XNN
; ------------------------------------------------------------------------------
op_4:
    mov al, byte [rbx + Chip8State.v + r8]
    cmp al, r11b
    je cycle_done
    add word [rbx + Chip8State.pc], 2
    jmp cycle_done

; ------------------------------------------------------------------------------
; Category 0x5: 5XY0
; ------------------------------------------------------------------------------
op_5:
    test r10d, r10d                             ; N must be 0
    jnz cycle_done
    mov al, byte [rbx + Chip8State.v + r8]
    cmp al, byte [rbx + Chip8State.v + r9]
    jne cycle_done
    add word [rbx + Chip8State.pc], 2
    jmp cycle_done

; ------------------------------------------------------------------------------
; Category 0x6: 6XNN
; ------------------------------------------------------------------------------
op_6:
    mov byte [rbx + Chip8State.v + r8], r11b
    jmp cycle_done

; ------------------------------------------------------------------------------
; Category 0x7: 7XNN
; ------------------------------------------------------------------------------
op_7:
    add byte [rbx + Chip8State.v + r8], r11b
    jmp cycle_done

; ------------------------------------------------------------------------------
; Category 0x8: Arithmetic and Bitwise Operations (8XY0 to 8XYE)
; ------------------------------------------------------------------------------
op_8:
    cmp r10d, 0x0
    je .op_8_set
    cmp r10d, 0x1
    je .op_8_or
    cmp r10d, 0x2
    je .op_8_and
    cmp r10d, 0x3
    je .op_8_xor
    cmp r10d, 0x4
    je .op_8_add
    cmp r10d, 0x5
    je .op_8_sub
    cmp r10d, 0x6
    je .op_8_shr
    cmp r10d, 0x7
    je .op_8_subn
    cmp r10d, 0xE
    je .op_8_shl
    jmp cycle_done

.op_8_set:
    mov al, byte [rbx + Chip8State.v + r9]
    mov byte [rbx + Chip8State.v + r8], al
    jmp cycle_done

.op_8_or:
    mov al, byte [rbx + Chip8State.v + r9]
    or byte [rbx + Chip8State.v + r8], al
    mov byte [rbx + Chip8State.v + 0xF], 0
    jmp cycle_done

.op_8_and:
    mov al, byte [rbx + Chip8State.v + r9]
    and byte [rbx + Chip8State.v + r8], al
    mov byte [rbx + Chip8State.v + 0xF], 0
    jmp cycle_done

.op_8_xor:
    mov al, byte [rbx + Chip8State.v + r9]
    xor byte [rbx + Chip8State.v + r8], al
    mov byte [rbx + Chip8State.v + 0xF], 0
    jmp cycle_done

.op_8_add:
    movzx eax, byte [rbx + Chip8State.v + r8]
    movzx ecx, byte [rbx + Chip8State.v + r9]
    add eax, ecx
    mov byte [rbx + Chip8State.v + r8], al
    shr eax, 8                                  ; AL = 1 if overflow occurred, else 0
    mov byte [rbx + Chip8State.v + 0xF], al
    jmp cycle_done

.op_8_sub:
    mov al, byte [rbx + Chip8State.v + r8]
    mov cl, byte [rbx + Chip8State.v + r9]
    cmp al, cl
    setae dl                                    ; DL = 1 if AL >= CL, else 0
    sub al, cl
    mov byte [rbx + Chip8State.v + r8], al
    mov byte [rbx + Chip8State.v + 0xF], dl
    jmp cycle_done

.op_8_shr:
    mov al, byte [rbx + Chip8State.v + r9]
    mov cl, al
    and cl, 1                                   ; CL = LSB of V[Y]
    shr al, 1
    cmp r8d, 0xF
    je .skip_shr_x
    mov byte [rbx + Chip8State.v + r8], al
.skip_shr_x:
    mov byte [rbx + Chip8State.v + 0xF], cl
    jmp cycle_done

.op_8_subn:
    mov al, byte [rbx + Chip8State.v + r8]
    mov cl, byte [rbx + Chip8State.v + r9]
    cmp cl, al
    setae dl                                    ; DL = 1 if CL >= AL, else 0
    sub cl, al
    mov byte [rbx + Chip8State.v + r8], cl
    mov byte [rbx + Chip8State.v + 0xF], dl
    jmp cycle_done

.op_8_shl:
    mov al, byte [rbx + Chip8State.v + r9]
    mov cl, al
    shr cl, 7                                   ; CL = MSB of V[Y]
    shl al, 1
    cmp r8d, 0xF
    je .skip_shl_x
    mov byte [rbx + Chip8State.v + r8], al
.skip_shl_x:
    mov byte [rbx + Chip8State.v + 0xF], cl
    jmp cycle_done

; ------------------------------------------------------------------------------
; Category 0x9: 9XY0
; ------------------------------------------------------------------------------
op_9:
    test r10d, r10d                             ; N must be 0
    jnz cycle_done
    mov al, byte [rbx + Chip8State.v + r8]
    cmp al, byte [rbx + Chip8State.v + r9]
    je cycle_done
    add word [rbx + Chip8State.pc], 2
    jmp cycle_done

; ------------------------------------------------------------------------------
; Category 0xA: ANNN
; ------------------------------------------------------------------------------
op_a:
    and edx, 0x0FFF                             ; EDX = NNN
    mov word [rbx + Chip8State.i], dx
    jmp cycle_done

; ------------------------------------------------------------------------------
; Category 0xB: BNNN
; ------------------------------------------------------------------------------
op_b:
    and edx, 0x0FFF                             ; EDX = NNN
    movzx eax, byte [rbx + Chip8State.v]         ; V[0]
    add eax, edx
    mov word [rbx + Chip8State.pc], ax
    jmp cycle_done

; ------------------------------------------------------------------------------
; Category 0xC: CXNN
; ------------------------------------------------------------------------------
op_c:
    ; 32-bit Xorshift PRNG algorithm
    mov eax, [rbx + Chip8State.rng_seed]
    mov ecx, eax
    shl ecx, 13
    xor eax, ecx
    mov ecx, eax
    shr ecx, 17
    xor eax, ecx
    mov ecx, eax
    shl ecx, 5
    xor eax, ecx
    mov [rbx + Chip8State.rng_seed], eax         ; Save new PRNG state
    and al, r11b                                 ; AL = random_byte & NN
    mov byte [rbx + Chip8State.v + r8], al
    jmp cycle_done

; ------------------------------------------------------------------------------
; Category 0xD: DXYN
; ------------------------------------------------------------------------------
op_d:
    cmp byte [rbx + Chip8State.has_drawn_this_frame], 0
    je .draw_start
    sub word [rbx + Chip8State.pc], 2
    jmp cycle_done

.draw_start:
    mov byte [rbx + Chip8State.has_drawn_this_frame], 1
    mov byte [rbx + Chip8State.v + 0xF], 0      ; Reset collision flag

    movzx eax, byte [rbx + Chip8State.v + r8]
    and eax, 63
    mov r12d, eax                               ; R12D = x

    movzx ecx, byte [rbx + Chip8State.v + r9]
    and ecx, 31
    mov r13d, ecx                               ; R13D = y

    test r10d, r10d
    jz cycle_done

    xor esi, esi                                ; ESI = row (0 to N - 1)

.row_loop:
    cmp esi, r10d
    jge cycle_done

    lea edx, [r13 + rsi]                            ; EDX = y + row
    cmp edx, CHIP8_DISPLAY_HEIGHT
    jge cycle_done

    movzx eax, word [rbx + Chip8State.i]
    add eax, esi
    cmp eax, CHIP8_MEMORY_SIZE
    jae cycle_done
    movzx eax, byte [rbx + Chip8State.memory + rax] ; AL = spriteByte

    xor edi, edi                                    ; EDI = col (0 to 7)

.col_loop:
    cmp edi, 8
    jge .next_row

    lea ecx, [r12 + rdi]                        ; ECX = x + col
    cmp ecx, CHIP8_DISPLAY_WIDTH
    jge .next_row

    mov ecx, 7
    sub ecx, edi
    bt eax, ecx                                 ; Copy bit (7 - col) into Carry Flag (CF)
    jnc .skip_pixel

    mov ecx, edx
    shl ecx, 6
    add ecx, r12d
    add ecx, edi                                ; ECX = pixelIndex

    cmp byte [rbx + Chip8State.display + rcx], 0
    je .toggle_pixel
    mov byte [rbx + Chip8State.v + 0xF], 1

.toggle_pixel:
    xor byte [rbx + Chip8State.display + rcx], 0xFF ; display[pixelIndex] ^= 0xFF

.skip_pixel:
    inc edi
    jmp .col_loop

.next_row:
    inc esi
    jmp .row_loop

; ------------------------------------------------------------------------------
; Category 0xE: EX9E and EXA1
; ------------------------------------------------------------------------------
op_e:
    movzx eax, byte [rbx + Chip8State.v + r8]
    and eax, 0x0F                               ; Key index (0 to 15)
    mov al, byte [rbx + Chip8State.keypad + rax]

    cmp r11b, 0x9E
    je .skip_if_pressed
    cmp r11b, 0xA1
    je .skip_if_not_pressed
    jmp cycle_done

.skip_if_pressed:
    test al, al
    jz cycle_done
    add word [rbx + Chip8State.pc], 2
    jmp cycle_done

.skip_if_not_pressed:
    test al, al
    jnz cycle_done
    add word [rbx + Chip8State.pc], 2
    jmp cycle_done

; ------------------------------------------------------------------------------
; Category 0xF: Timers, Key Wait, BCD & Memory (FX07 to FX65)
; ------------------------------------------------------------------------------
op_f:
    cmp r11b, 0x07
    je .fx07
    cmp r11b, 0x0A
    je .fx0a
    cmp r11b, 0x15
    je .fx15
    cmp r11b, 0x18
    je .fx18
    cmp r11b, 0x1E
    je .fx1e
    cmp r11b, 0x29
    je .fx29
    cmp r11b, 0x33
    je .fx33
    cmp r11b, 0x55
    je .fx55
    cmp r11b, 0x65
    je .fx65
    jmp cycle_done

.fx07:
    ; Set V[F] to delay_timer
    mov al, byte [rbx + Chip8State.delay_timer]
    mov byte [rbx + Chip8State.v + r8], al
    jmp cycle_done

.fx0a:
    ; Wait for key press (blocking)
    cmp byte [rbx + Chip8State.key_pressed], -1
    jne .check_key_release

    ; Scan keypad for pressed key
    xor ecx, ecx
.scan_keys:
    cmp ecx, CHIP8_KEYPAD_SIZE
    jge .no_key_found
    cmp byte [rbx + Chip8State.keypad + rcx], 0
    jne .key_found
    inc ecx
    jmp .scan_keys

.key_found:
    mov byte [rbx + Chip8State.key_pressed], cl
.no_key_found:
    sub word [rbx + Chip8State.pc], 2           ; Keep PC on this instruction
    jmp cycle_done

.check_key_release:
    ; Check if previously pressed key is now released
    movzx ecx, byte [rbx + Chip8State.key_pressed]
    cmp byte [rbx + Chip8State.keypad + rcx], 0
    jne .key_still_held
    mov byte [rbx + Chip8State.v + r8], cl
    mov byte [rbx + Chip8State.key_pressed], -1
    jmp cycle_done

.key_still_held:
    sub word [rbx + Chip8State.pc], 2
    jmp cycle_done

.fx15:
    ; Set delay_timer to V[X]
    mov al, byte [rbx + Chip8State.v + r8]
    mov byte [rbx + Chip8State.delay_timer], al
    jmp cycle_done

.fx18:
    ; Set sound_timer to V[X]
    mov al, byte [rbx + Chip8State.v + r8]
    mov byte [rbx + Chip8State.sound_timer], al
    jmp cycle_done

.fx1e:
    ; Add V[X] to I
    movzx eax, byte [rbx + Chip8State.v + r8]
    add word [rbx + Chip8State.i], ax
    jmp cycle_done

.fx29:
    ; Set I to fontset start address + (V[X] & 0x0F) * 5
    movzx eax, byte [rbx + Chip8State.v + r8]
    and eax, 0x0F
    lea eax, [eax + eax * 4]                    ; EAX = EAX * 5
    add eax, CHIP8_FONTSET_START_ADDRESS
    mov word [rbx + Chip8State.i], ax
    jmp cycle_done

.fx33:
    ; Convert V[X] to Binary-Coded Decimal (BCD) and store in memory[I..I+2]
    movzx esi, word [rbx + Chip8State.i]
    cmp esi, (CHIP8_MEMORY_SIZE - 2)
    jae cycle_done

    movzx eax, byte [rbx + Chip8State.v + r8]    ; EAX = value (0 to 255)
    xor edx, edx
    mov ecx, 100
    div ecx                                     ; EAX = hundreds (quotient), EDX = remainder
    mov byte [rbx + Chip8State.memory + rsi], al

    mov eax, edx
    xor edx, edx
    mov ecx, 10
    div ecx                                     ; EAX = tens (quotient), EDX = ones (remainder)
    mov byte [rbx + Chip8State.memory + rsi + 1], al
    mov byte [rbx + Chip8State.memory + rsi + 2], dl
    jmp cycle_done

.fx55:
    ; Dump V[0..X] into memory starting at I
    movzx edx, word [rbx + Chip8State.i]
    xor ecx, ecx
.dump_loop:
    cmp ecx, r8d
    jg cycle_done
    cmp edx, CHIP8_MEMORY_SIZE
    jae cycle_done
    mov al, byte [rbx + Chip8State.v + rcx]
    mov byte [rbx + Chip8State.memory + rdx], al
    inc edx
    inc ecx
    mov word [rbx + Chip8State.i], dx
    jmp .dump_loop

.fx65:
    ; Load V[0..X] from memory starting at I
    movzx edx, word [rbx + Chip8State.i]
    xor ecx, ecx
.load_loop:
    cmp ecx, r8d
    jg cycle_done
    cmp edx, CHIP8_MEMORY_SIZE
    jae cycle_done
    mov al, byte [rbx + Chip8State.memory + rdx]
    mov byte [rbx + Chip8State.v + rcx], al
    inc edx
    inc ecx
    mov word [rbx + Chip8State.i], dx
    jmp .load_loop

; ------------------------------------------------------------------------------
; Cycle End
; ------------------------------------------------------------------------------
cycle_done:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
