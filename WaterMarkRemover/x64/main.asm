; ==============================================================================
; SignGuiPatcher - Entry Point and Global Data
;
; Author: Marek Wesołowski (wesmar)
; Purpose: Process entry, global variable definitions, privilege name table.
;          mainCRTStartup attaches console, checks argv[1] for CLI switches
;          (dispatched to CliDispatch), otherwise falls through to mode_gui.
; ==============================================================================

option casemap:none

include consts.inc

EXTRN GetModuleHandleW      :PROC
EXTRN GetMessageW           :PROC
EXTRN TranslateMessage      :PROC
EXTRN DispatchMessageW      :PROC
EXTRN ExitProcess           :PROC
EXTRN CreateMainWindow      :PROC
EXTRN AttachConsole         :PROC
EXTRN GetStdHandle          :PROC
EXTRN GetFileType           :PROC
EXTRN GetCommandLineW       :PROC
EXTRN CommandLineToArgvW    :PROC
EXTRN LocalFree             :PROC

EXTRN wcscpy_p              :PROC
EXTRN wcscat_p              :PROC
EXTRN wcscmp_ci             :PROC
EXTRN DecryptWideStr        :PROC

EXTRN CliDispatch           :PROC

; ==============================================================================
; CONSTANT STRINGS
; ==============================================================================
.const

; Privilege base name strings (combined with Se prefix + Privilege suffix)
privStr_0  dw 'A','s','s','i','g','n','P','r','i','m','a','r','y','T','o','k','e','n',0
privStr_1  dw 'B','a','c','k','u','p',0
privStr_2  dw 'R','e','s','t','o','r','e',0
privStr_3  dw 'D','e','b','u','g',0
privStr_4  dw 'I','m','p','e','r','s','o','n','a','t','e',0
privStr_5  dw 'T','a','k','e','O','w','n','e','r','s','h','i','p',0
privStr_6  dw 'L','o','a','d','D','r','i','v','e','r',0
privStr_7  dw 'S','y','s','t','e','m','E','n','v','i','r','o','n','m','e','n','t',0
privStr_8  dw 'M','a','n','a','g','e','V','o','l','u','m','e',0
privStr_9  dw 'S','e','c','u','r','i','t','y',0
privStr_10 dw 'S','h','u','t','d','o','w','n',0
privStr_11 dw 'S','y','s','t','e','m','t','i','m','e',0
privStr_12 dw 'T','c','b',0
privStr_13 dw 'I','n','c','r','e','a','s','e','Q','u','o','t','a',0
privStr_14 dw 'A','u','d','i','t',0
privStr_15 dw 'C','h','a','n','g','e','N','o','t','i','f','y',0
privStr_16 dw 'U','n','d','o','c','k',0
privStr_17 dw 'C','r','e','a','t','e','T','o','k','e','n',0
privStr_18 dw 'L','o','c','k','M','e','m','o','r','y',0
privStr_19 dw 'C','r','e','a','t','e','P','a','g','e','f','i','l','e',0
privStr_20 dw 'C','r','e','a','t','e','P','e','r','m','a','n','e','n','t',0
privStr_21 dw 'S','y','s','t','e','m','P','r','o','f','i','l','e',0
privStr_22 dw 'P','r','o','f','i','l','e','S','i','n','g','l','e','P','r','o','c','e','s','s',0
privStr_23 dw 'C','r','e','a','t','e','G','l','o','b','a','l',0
privStr_24 dw 'T','i','m','e','Z','o','n','e',0
privStr_25 dw 'C','r','e','a','t','e','S','y','m','b','o','l','i','c','L','i','n','k',0
privStr_26 dw 'I','n','c','r','e','a','s','e','B','a','s','e','P','r','i','o','r','i','t','y',0
privStr_27 dw 'R','e','m','o','t','e','S','h','u','t','d','o','w','n',0
privStr_28 dw 'I','n','c','r','e','a','s','e','W','o','r','k','i','n','g','S','e','t',0
privStr_29 dw 'R','e','l','a','b','e','l',0
privStr_30 dw 'D','e','l','e','g','a','t','e','S','e','s','s','i','o','n','U','s','e','r','I','m','p','e','r','s','o','n','a','t','e',0
privStr_31 dw 'T','r','u','s','t','e','d','C','r','e','d','M','a','n','A','c','c','e','s','s',0
privStr_32 dw 'E','n','a','b','l','e','D','e','l','e','g','a','t','i','o','n',0
privStr_33 dw 'S','y','n','c','A','g','e','n','t',0

PUBLIC privPrefix, privSuffix
privPrefix dw 'S','e',0
privSuffix dw 'P','r','i','v','i','l','e','g','e',0

; ==============================================================================
; INITIALIZED DATA
; ==============================================================================
.data
    align 8

PUBLIC g_privTable
g_privTable dq offset privStr_0,  offset privStr_1,  offset privStr_2,  offset privStr_3
            dq offset privStr_4,  offset privStr_5,  offset privStr_6,  offset privStr_7
            dq offset privStr_8,  offset privStr_9,  offset privStr_10, offset privStr_11
            dq offset privStr_12, offset privStr_13, offset privStr_14, offset privStr_15
            dq offset privStr_16, offset privStr_17, offset privStr_18, offset privStr_19
            dq offset privStr_20, offset privStr_21, offset privStr_22, offset privStr_23
            dq offset privStr_24, offset privStr_25, offset privStr_26, offset privStr_27
            dq offset privStr_28, offset privStr_29, offset privStr_30, offset privStr_31
            dq offset privStr_32, offset privStr_33

PUBLIC g_cachedToken, g_tokenTime
PUBLIC g_hInstance, g_hwndMain, g_hwndBtn, g_hwndBtnUnpatch
PUBLIC g_hwndStatus, g_hwndVersion, g_hwndAuthor
PUBLIC g_isPatchApplied
PUBLIC g_cliMode, g_queryResult

g_cachedToken       dq 0
g_tokenTime         dd 0
                    dd 0        ; padding
g_hInstance         dq 0
g_hwndMain          dq 0
g_hwndBtn           dq 0
g_hwndBtnUnpatch    dq 0
g_hwndStatus        dq 0
g_hwndVersion       dq 0
g_hwndAuthor        dq 0
g_isPatchApplied    dd 0
                    dd 0        ; padding
g_cliMode           dd 0        ; 0 = GUI mode, 1 = CLI mode
                    dd 0        ; padding
g_queryResult       dd 0        ; 0 = unpatched, 1 = patched, 2 = unknown
                    dd 0        ; padding

; ==============================================================================
; UNINITIALIZED DATA
; ==============================================================================
.data?

PUBLIC g_decryptBuf, g_tempBuf, g_statusBuf

g_decryptBuf    dw 520 dup(?)
g_tempBuf       dw 520 dup(?)
g_statusBuf     dw 520 dup(?)

; ==============================================================================
; CODE
; ==============================================================================
.code

; ==============================================================================
; mainCRTStartup - Process Entry Point
;
; Attaches to parent console, checks argv[1] for CLI switches, dispatches to
; CliDispatch. If no CLI switch matched (or argc < 2), falls through to mode_gui.
;
; Stack: entry rsp%16=8 (EXE entry); 3 pushes → 0; sub 30h (48%16=0) → 0 ✓
; [rsp+20h]: argc (DWORD, written by CommandLineToArgvW)
; [rsp+30h]: saved r13
; [rsp+38h]: saved r12
; [rsp+40h]: saved rbx
; ==============================================================================
PUBLIC mainCRTStartup
mainCRTStartup proc
    push    rbx
    push    r12
    push    r13
    sub     rsp, 30h

    ; Attach console only when stdout is absent (NULL/invalid) or already
    ; a real console handle (FILE_TYPE_CHAR). Leave FILE/PIPE intact so
    ; redirected/piped output keeps the inherited handle.
    mov     ecx, STD_OUTPUT_HANDLE
    call    GetStdHandle
    test    rax, rax
    jz      @mcs_attach
    cmp     rax, -1
    je      @mcs_attach
    mov     rcx, rax
    call    GetFileType
    cmp     eax, FILE_TYPE_CHAR
    jne     @mcs_no_attach

@mcs_attach:
    mov     ecx, ATTACH_PARENT_PROCESS
    call    AttachConsole

@mcs_no_attach:
    call    GetCommandLineW
    lea     rdx, [rsp+20h]          ; &argc
    mov     rcx, rax
    call    CommandLineToArgvW
    test    rax, rax
    jz      @mcs_gui                ; parse failed → GUI
    mov     r12, rax                ; r12 = argv

    cmp     dword ptr [rsp+20h], 2
    jl      @mcs_free_gui           ; argc < 2 → GUI

    mov     rcx, [r12+8]            ; argv[1]
    call    CliDispatch             ; returns 0 only for unrecognized switch
    ; CliDispatch returned → not a CLI switch

@mcs_free_gui:
    mov     rcx, r12
    call    LocalFree

@mcs_gui:
    add     rsp, 30h
    pop     r13
    pop     r12
    pop     rbx
    jmp     mode_gui                ; tail-jump to GUI mode

mainCRTStartup endp

; ==============================================================================
; mode_gui - GUI Mode
;
; Gets hInstance, creates window, runs message loop until WM_QUIT.
; Reached via tail-jump from mainCRTStartup (RSP%16=8 at entry).
;
; Stack: entry rsp%16=8; sub 58h (88%16=8) → rsp%16=0 ✓
; MSG at [rsp+20h] (48 bytes)
; ==============================================================================
PUBLIC mode_gui
mode_gui proc
    sub     rsp, 58h

    xor     ecx, ecx
    call    GetModuleHandleW
    mov     g_hInstance, rax

    call    CreateMainWindow
    test    rax, rax
    jz      @mg_exit

@mg_loop:
    lea     rcx, [rsp+20h]
    xor     edx, edx
    xor     r8d, r8d
    xor     r9d, r9d
    call    GetMessageW
    test    eax, eax
    jz      @mg_exit
    js      @mg_exit

    lea     rcx, [rsp+20h]
    call    TranslateMessage

    lea     rcx, [rsp+20h]
    call    DispatchMessageW

    jmp     @mg_loop

@mg_exit:
    xor     ecx, ecx
    call    ExitProcess
mode_gui endp

end
