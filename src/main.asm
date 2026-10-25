default rel

section .text
global WinMain

WinMain:
    xor eax, eax        ; Return 0 (success)
    ret                 ; Return back to the CRT startup code
