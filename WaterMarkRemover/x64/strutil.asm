; ==============================================================================
; SignGuiPatcher - String Utility Module
;
; Author: Marek Wesołowski (wesmar)
; Purpose: Self-contained wide-character string helpers shared across modules.
;          No external symbols required; functions are pure manipulations of
;          caller-provided buffers and produce no side effects on globals.
;
; Exported routines:
;   DecryptWideStr  - XOR-decrypt a wide string into a destination buffer
;   wcscpy_p        - Copy a null-terminated wide string
;   wcscat_p        - Concatenate a wide string onto an existing buffer
;   wcscmp_ci       - Case-insensitive wide-string comparison
;   wcscmp_token    - Like wcscmp_ci, but treats space as token terminator
;   skip_spaces     - Advance a wide-string pointer past leading spaces
;   wcslen_p        - Length of a null-terminated wide string, in characters
; ==============================================================================

option casemap:none

.code

; ==============================================================================
; DecryptWideStr - XOR Decrypt Wide String In-Place
;
; Purpose: Decrypts a XOR-encrypted wide character string into destination buffer
;          Uses simple XOR with single-byte key applied to each byte
;
; Parameters:
;   RCX = Pointer to encrypted source string
;   RDX = Pointer to destination buffer
;
; Returns:
;   RAX = Pointer to destination buffer (same as RDX input)
;
; Modifies: RAX, RSI, RDI
;
; Notes:
;   - XOR key is hardcoded as 0x0aah
;   - Decryption stops at null terminator (0x0000)
;   - Each byte of the wide string is XORed independently
; ==============================================================================
DecryptWideStr proc
    push rsi
    push rdi

    mov rsi, rcx                ; RSI = source (encrypted)
    mov rdi, rdx                ; RDI = destination

dws_loop:
    ; Decrypt first byte of wide char
    mov al, byte ptr [rsi]
    xor al, 0aah                ; XOR with key
    mov byte ptr [rdi], al

    ; Decrypt second byte of wide char
    mov al, byte ptr [rsi+1]
    xor al, 0aah                ; XOR with key
    mov byte ptr [rdi+1], al

    ; Check if we hit null terminator
    cmp word ptr [rdi], 0
    je dws_done

    ; Move to next character
    add rsi, 2
    add rdi, 2
    jmp dws_loop

dws_done:
    mov rax, rdx                ; Return destination pointer
    pop rdi
    pop rsi
    ret
DecryptWideStr endp

; ==============================================================================
; wcscpy_p - Wide Character String Copy (Private Implementation)
;
; Purpose: Copies a null-terminated wide character string from source to dest
;
; Parameters:
;   RCX = Destination buffer pointer
;   RDX = Source string pointer
;
; Returns: None
;
; Modifies: RAX, RDI, RSI (saved/restored), destination buffer
; ==============================================================================
wcscpy_p proc
    push rsi
    push rdi
    mov rdi, rcx                ; RDI = destination pointer
    mov rsi, rdx                ; RSI = source pointer
@@:
    mov ax, word ptr [rsi]      ; Read wide character from source
    mov word ptr [rdi], ax      ; Write to destination
    test ax, ax                 ; Check for null terminator
    jz @F                       ; Exit if null terminator found
    add rsi, 2                  ; Advance source pointer
    add rdi, 2                  ; Advance destination pointer
    jmp @B                      ; Continue copying
@@:
    pop rdi
    pop rsi
    ret
wcscpy_p endp

; ==============================================================================
; wcscat_p - Wide Character String Concatenate (Private Implementation)
;
; Purpose: Appends source string to the end of destination string
;
; Parameters:
;   RCX = Destination buffer pointer
;   RDX = Source string pointer
;
; Returns: None
;
; Modifies: RAX, RDI, RSI (saved/restored), destination buffer
; ==============================================================================
wcscat_p proc
    push rsi
    push rdi
    mov rdi, rcx                ; RDI = destination pointer
@@:
    cmp word ptr [rdi], 0       ; Check for null terminator
    je @F                       ; Found end of destination string
    add rdi, 2                  ; Move to next character
    jmp @B                      ; Continue searching
@@:
    mov rsi, rdx                ; RSI = source pointer
@@:
    mov ax, word ptr [rsi]      ; Read wide character from source
    mov word ptr [rdi], ax      ; Write to destination
    test ax, ax                 ; Check for null terminator
    jz @F                       ; Exit if null terminator found
    add rsi, 2                  ; Advance source pointer
    add rdi, 2                  ; Advance destination pointer
    jmp @B                      ; Continue copying
@@:
    pop rdi
    pop rsi
    ret
wcscat_p endp

; ==============================================================================
; wcscmp_ci - Wide Character String Compare (Case-Insensitive)
;
; Purpose: Compares two wide character strings ignoring case differences
;
; Parameters:
;   RCX = First string pointer
;   RDX = Second string pointer
;
; Returns:
;   RAX = 1 if strings are equal (case-insensitive), 0 otherwise
;
; Modifies: RAX, RDX, RSI, RDI (saved/restored)
; ==============================================================================
wcscmp_ci proc
    push rsi
    push rdi
    mov rsi, rcx                ; RSI = first string
    mov rdi, rdx                ; RDI = second string
wci_loop:
    movzx eax, word ptr [rsi]   ; Load character from first string
    movzx edx, word ptr [rdi]   ; Load character from second string

    ; Convert first character to lowercase if uppercase
    cmp eax, 'A'
    jb wci_skip1
    cmp eax, 'Z'
    ja wci_skip1
    add eax, 32                  ; Convert A-Z to a-z
wci_skip1:

    ; Convert second character to lowercase if uppercase
    cmp edx, 'A'
    jb wci_skip2
    cmp edx, 'Z'
    ja wci_skip2
    add edx, 32                  ; Convert A-Z to a-z
wci_skip2:

    cmp eax, edx                  ; Compare normalized characters
    jne wci_not_eq              ; Characters differ
    test eax, eax                 ; Check if end of strings
    jz wci_equal                ; Both null terminators reached
    add rsi, 2                  ; Advance first string pointer
    add rdi, 2                  ; Advance second string pointer
    jmp wci_loop                ; Continue comparison
wci_equal:
    pop rdi
    pop rsi
    mov rax, 1                  ; Return 1 (strings equal)
    ret
wci_not_eq:
    pop rdi
    pop rsi
    xor rax, rax                ; Return 0 (strings differ)
    ret
wcscmp_ci endp

; ==============================================================================
; wcscmp_token - Compare command-line token against a null-terminated literal
;
; Purpose: Like wcscmp_ci but treats a space character in the first argument
;          as an end-of-string marker. Used to recognize switches inside a
;          raw command-line buffer without temporarily mutating the buffer.
;
; Parameters:
;   RCX = command-line pointer (a token followed by space or null)
;   RDX = null-terminated literal to match (e.g. str_outfileFlag)
;
; Returns:
;   RAX = 1 if the literal matches the token (case-insensitive), 0 otherwise
;
; Modifies: RAX, RDX, RSI, RDI (saved/restored)
; ==============================================================================
wcscmp_token proc
    push rsi
    push rdi
    mov rsi, rcx                ; RSI = cmdline cursor
    mov rdi, rdx                ; RDI = literal
wctk_loop:
    movzx eax, word ptr [rdi]
    test eax, eax
    jz wctk_lit_end             ; Literal exhausted
    movzx edx, word ptr [rsi]
    test edx, edx
    jz wctk_no                  ; Token ended early
    cmp edx, ' '
    je wctk_no                  ; Token ended early
    
    ; Normalize eax
    cmp eax, 'A'
    jb @F
    cmp eax, 'Z'
    ja @F
    add eax, 32
@@:
    ; Normalize edx
    cmp edx, 'A'
    jb @F
    cmp edx, 'Z'
    ja @F
    add edx, 32
@@:
    cmp eax, edx
    jne wctk_no
    add rsi, 2
    add rdi, 2
    jmp wctk_loop

wctk_lit_end:
    ; Literal finished. Check if token also finished (space or null).
    movzx edx, word ptr [rsi]
    test edx, edx
    jz wctk_yes
    cmp edx, ' '
    je wctk_yes
wctk_no:
    xor rax, rax
    jmp wctk_done
wctk_yes:
    mov rax, 1
wctk_done:
    pop rdi
    pop rsi
    ret
wcscmp_token endp

; ==============================================================================
; skip_spaces - Skip Leading Whitespace in Wide String
;
; Purpose: Advances a string pointer past any leading space characters
;
; Parameters:
;   RCX = String pointer
;
; Returns:
;   RAX = Pointer to first non-space character
;
; Modifies: RAX
; ==============================================================================
skip_spaces proc
    mov rax, rcx                ; RAX = input pointer
@@:
    cmp word ptr [rax], ' '     ; Check if current character is space
    jne @F                      ; Exit if non-space found
    add rax, 2                  ; Skip this space
    jmp @B                      ; Continue checking
@@:
    ret
skip_spaces endp

; ==============================================================================
; wcslen_p - Wide Character String Length (Private Implementation)
;
; Purpose: Calculates the length of a null-terminated wide character string
;
; Parameters:
;   RCX = String pointer
;
; Returns:
;   RAX = Number of characters (excluding null terminator)
;
; Modifies: RAX
; ==============================================================================
wcslen_p proc
    xor rax, rax                ; RAX = length counter
@@:
    cmp word ptr [rcx + rax*2], 0 ; Check for null terminator
    je @F
    inc rax                     ; Increment length
    jmp @B                      ; Continue searching
@@:
    ret
wcslen_p endp

end