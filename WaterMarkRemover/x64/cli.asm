; ==============================================================================
; SignGuiPatcher - CLI Dispatch and Console I/O
;
; Author: Marek Wesołowski (wesmar)
; Purpose: CliDispatch checks argv[1] for -apply/-restore/-status and runs
;          the corresponding operation with ANSI console output.
;          NudgeConsolePrompt restores cmd.exe prompt after GUI-subsystem output.
; ==============================================================================

option casemap:none

include consts.inc
include globals.inc

EXTRN ExitProcess           :PROC
EXTRN GetStdHandle          :PROC
EXTRN GetFileType           :PROC
EXTRN WriteFile             :PROC
EXTRN WriteConsoleInputW    :PROC
EXTRN RunPatch              :PROC
EXTRN RunUnpatch            :PROC
EXTRN QueryPatchStatus      :PROC
EXTRN wcscmp_ci             :PROC

; mode_gui is in main.asm, jumped to when no CLI switch matched
EXTRN mode_gui              :PROC

; ==============================================================================
; CONSTANT STRINGS
; ==============================================================================
.const

str_sw_apply    dw '-','a','p','p','l','y',0
str_sw_restore  dw '-','r','e','s','t','o','r','e',0
str_sw_status   dw '-','s','t','a','t','u','s',0
str_sw_help1    dw '/',  '?', 0
str_sw_help2    dw '-',  'h', 0
str_sw_help3    dw '-',  'h','e','l','p',0
str_sw_help4    dw '-',  '-','h','e','l','p',0

msg_apply_ok        db "APPLY OK",13,10
APPLY_OK_LEN        equ $ - msg_apply_ok
msg_apply_fail      db "APPLY FAILED",13,10
APPLY_FAIL_LEN      equ $ - msg_apply_fail
msg_restore_ok      db "RESTORE OK",13,10
RESTORE_OK_LEN      equ $ - msg_restore_ok
msg_restore_fail    db "RESTORE FAILED",13,10
RESTORE_FAIL_LEN    equ $ - msg_restore_fail
msg_st_patched      db "STATUS: PATCHED",13,10
ST_PATCHED_LEN      equ $ - msg_st_patched
msg_st_unpatched    db "STATUS: UNPATCHED",13,10
ST_UNPATCHED_LEN    equ $ - msg_st_unpatched
msg_st_unknown      db "STATUS: UNKNOWN",13,10
ST_UNKNOWN_LEN      equ $ - msg_st_unknown

msg_help        db "SignGuiPatcher [switch]",13,10
                db 13,10
                db "  (no switch)   GUI mode",13,10
                db "  -apply        Apply watermark patch",13,10
                db "  -restore      Remove watermark patch",13,10
                db "  -status       Query patch status",13,10
                db "  /? -h -help   This help",13,10
MSG_HELP_LEN    equ $ - msg_help

; ==============================================================================
; CODE
; ==============================================================================
.code

; ==============================================================================
; WriteOut - write ANSI bytes to stdout
;
; RCX = buffer (LPCSTR), EDX = byte count
;
; 3 pushes (entry rsp%16=8 → 0) + sub 30h (48%16=0) → 0 ✓
; [rsp+20h] = WriteFile param5 (lpOverlapped=NULL)
; [rsp+28h] = scratch for &bytesWritten
; ==============================================================================
WriteOut proc
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 30h

    mov     rsi, rcx
    mov     edi, edx

    mov     ecx, STD_OUTPUT_HANDLE
    call    GetStdHandle
    test    rax, rax
    jz      @wo_done
    cmp     rax, -1
    je      @wo_done
    mov     rbx, rax

    xor     eax, eax
    mov     qword ptr [rsp+20h], rax    ; lpOverlapped = NULL
    lea     r9, [rsp+28h]               ; &bytesWritten (scratch DWORD)
    mov     r8d, edi
    mov     rdx, rsi
    mov     rcx, rbx
    call    WriteFile

@wo_done:
    add     rsp, 30h
    pop     rdi
    pop     rsi
    pop     rbx
    ret
WriteOut endp

; ==============================================================================
; NudgeConsolePrompt - post Enter to console input to redraw cmd.exe prompt
;
; GUI-subsystem exes don't block cmd.exe; after output the prompt needs a nudge.
; No-op when stdout is redirected (not FILE_TYPE_CHAR).
;
; 1 push (entry rsp%16=8 → 0) + sub 50h (80%16=0) → 0 ✓
; [rsp+00..1f]: shadow
; [rsp+20h..33h]: INPUT_RECORD (KEY_EVENT, 20 bytes)
; [rsp+40h]: &eventsWritten scratch
; [rsp+50h]: saved rdi
; ==============================================================================
PUBLIC NudgeConsolePrompt
NudgeConsolePrompt proc
    push    rdi
    sub     rsp, 50h

    mov     ecx, STD_OUTPUT_HANDLE
    call    GetStdHandle
    test    rax, rax
    jz      @ncp_done
    cmp     rax, -1
    je      @ncp_done
    mov     rcx, rax
    call    GetFileType
    cmp     eax, FILE_TYPE_CHAR     ; real console only
    jne     @ncp_done

    mov     ecx, STD_INPUT_HANDLE
    call    GetStdHandle
    test    rax, rax
    jz      @ncp_done
    cmp     rax, -1
    je      @ncp_done
    mov     rdi, rax                ; rdi = hStdIn

    ; Build KEY_EVENT INPUT_RECORD at [rsp+20h] (20 bytes)
    xor     eax, eax
    mov     qword ptr [rsp+20h], rax
    mov     qword ptr [rsp+28h], rax
    mov     dword ptr [rsp+30h], eax
    mov     word ptr  [rsp+20h], 1      ; EventType = KEY_EVENT
    mov     dword ptr [rsp+24h], 1      ; bKeyDown = TRUE
    mov     word ptr  [rsp+28h], 1      ; wRepeatCount
    mov     word ptr  [rsp+2ah], 0Dh   ; wVirtualKeyCode = VK_RETURN
    mov     word ptr  [rsp+2ch], 1Ch   ; wVirtualScanCode
    mov     word ptr  [rsp+2eh], 0Dh   ; uChar.UnicodeChar = CR
    mov     dword ptr [rsp+30h], 0     ; dwControlKeyState

    lea     r9, [rsp+40h]               ; &eventsWritten
    mov     r8d, 1
    lea     rdx, [rsp+20h]
    mov     rcx, rdi
    call    WriteConsoleInputW

@ncp_done:
    add     rsp, 50h
    pop     rdi
    ret
NudgeConsolePrompt endp

; ==============================================================================
; CliDispatch - check argv[1] and execute CLI command
;
; RCX = argv[1] (LPCWSTR)
; Returns EAX = 0 if not a recognized switch (caller should run GUI mode).
; Recognized switches end in ExitProcess; this function never returns for them.
;
; 3 pushes (entry rsp%16=8 → 0) + sub 20h (32%16=0) → 0 ✓
; ==============================================================================
PUBLIC CliDispatch
CliDispatch proc
    push    rbx
    push    rsi
    push    r12
    sub     rsp, 20h

    mov     rbx, rcx        ; rbx = argv[1]

    lea     rdx, str_sw_help1
    mov     rcx, rbx
    call    wcscmp_ci
    test    eax, eax
    jnz     @cd_help

    lea     rdx, str_sw_help2
    mov     rcx, rbx
    call    wcscmp_ci
    test    eax, eax
    jnz     @cd_help

    lea     rdx, str_sw_help3
    mov     rcx, rbx
    call    wcscmp_ci
    test    eax, eax
    jnz     @cd_help

    lea     rdx, str_sw_help4
    mov     rcx, rbx
    call    wcscmp_ci
    test    eax, eax
    jnz     @cd_help

    lea     rdx, str_sw_apply
    mov     rcx, rbx
    call    wcscmp_ci
    test    eax, eax
    jnz     @cd_apply

    lea     rdx, str_sw_restore
    mov     rcx, rbx
    call    wcscmp_ci
    test    eax, eax
    jnz     @cd_restore

    lea     rdx, str_sw_status
    mov     rcx, rbx
    call    wcscmp_ci
    test    eax, eax
    jnz     @cd_status

    ; Not a recognized switch
    xor     eax, eax
    add     rsp, 20h
    pop     r12
    pop     rsi
    pop     rbx
    ret

@cd_apply:
    mov     dword ptr g_cliMode, 1
    call    RunPatch
    test    eax, eax
    jz      @cd_apply_fail
    lea     rcx, msg_apply_ok
    mov     edx, APPLY_OK_LEN
    call    WriteOut
    call    NudgeConsolePrompt
    xor     ecx, ecx
    call    ExitProcess

@cd_apply_fail:
    lea     rcx, msg_apply_fail
    mov     edx, APPLY_FAIL_LEN
    call    WriteOut
    call    NudgeConsolePrompt
    mov     ecx, 1
    call    ExitProcess

@cd_restore:
    mov     dword ptr g_cliMode, 1
    call    RunUnpatch
    test    eax, eax
    jz      @cd_restore_fail
    lea     rcx, msg_restore_ok
    mov     edx, RESTORE_OK_LEN
    call    WriteOut
    call    NudgeConsolePrompt
    xor     ecx, ecx
    call    ExitProcess

@cd_restore_fail:
    lea     rcx, msg_restore_fail
    mov     edx, RESTORE_FAIL_LEN
    call    WriteOut
    call    NudgeConsolePrompt
    mov     ecx, 1
    call    ExitProcess

@cd_status:
    mov     dword ptr g_cliMode, 1
    call    QueryPatchStatus
    ; g_queryResult: 0=unpatched, 1=patched, 2=unknown
    cmp     dword ptr g_queryResult, 1
    je      @cd_st_patched
    cmp     dword ptr g_queryResult, 2
    je      @cd_st_unknown
    lea     rcx, msg_st_unpatched
    mov     edx, ST_UNPATCHED_LEN
    jmp     @cd_st_write

@cd_st_patched:
    lea     rcx, msg_st_patched
    mov     edx, ST_PATCHED_LEN
    jmp     @cd_st_write

@cd_st_unknown:
    lea     rcx, msg_st_unknown
    mov     edx, ST_UNKNOWN_LEN

@cd_st_write:
    call    WriteOut
    call    NudgeConsolePrompt
    xor     ecx, ecx
    call    ExitProcess

@cd_help:
    lea     rcx, msg_help
    mov     edx, MSG_HELP_LEN
    call    WriteOut
    call    NudgeConsolePrompt
    xor     ecx, ecx
    call    ExitProcess

CliDispatch endp

end
