; ==============================================================================
; SignGuiPatcher - Window and GUI (Modern Mica Edition)
;
; Author: Marek Wesołowski (wesmar)
; Purpose: Window class registration, creation, message handling.
;          Implements Windows 11 Mica effect and modern typography.
; ==============================================================================

option casemap:none

include consts.inc
include globals.inc

; External function declarations - Windows API
EXTRN RegisterClassExW      :PROC
EXTRN CreateWindowExW       :PROC
EXTRN DefWindowProcW        :PROC
EXTRN ShowWindow            :PROC
EXTRN UpdateWindow          :PROC
EXTRN DestroyWindow         :PROC
EXTRN PostQuitMessage       :PROC
EXTRN SetWindowTextW        :PROC
EXTRN SetWindowPos          :PROC
EXTRN LoadCursorW           :PROC
EXTRN LoadIconW             :PROC
EXTRN InvalidateRect        :PROC
EXTRN DwmSetWindowAttribute :PROC
EXTRN SetTextColor          :PROC
EXTRN SetBkColor            :PROC
EXTRN SetBkMode             :PROC
EXTRN GetSysColor           :PROC
EXTRN GetSysColorBrush      :PROC
EXTRN RegOpenKeyExW         :PROC
EXTRN RegQueryValueExW      :PROC
EXTRN RegCloseKey           :PROC
EXTRN CreateFontW           :PROC
EXTRN SendMessageW          :PROC
EXTRN DeleteObject          :PROC
EXTRN GetStockObject        :PROC
EXTRN RunPatch              :PROC
EXTRN RunUnpatch            :PROC
EXTRN wcscpy_p              :PROC
EXTRN wcscat_p              :PROC
EXTRN wcscmp_ci             :PROC

; ==============================================================================
; CONSTANT STRINGS
; ==============================================================================
.const

str_wndclass    dw 'S','P','a','t','c','h','W','n','d',0
str_title       dw 'W','a','t','e','r','m','a','r','k',' ','R','e','m','o','v','e','r',0
str_buttoncls   dw 'B','U','T','T','O','N',0
str_staticcls   dw 'S','T','A','T','I','C',0

str_btnpatch    dw 'A','P','P','L','Y',' ','P','A','T','C','H',0
str_btnrestore  dw 'R','E','S','T','O','R','E',0
str_working     dw 'W','O','R','K','I','N','G','.','.','.',0

str_patched     dw 'W','A','T','E','R','M','A','R','K',' ','R','E','M','O','V','E','D',' ',2713h,0
str_unpatched   dw 'W','A','T','E','R','M','A','R','K',' ','A','C','T','I','V','E',' ',2713h,0
str_unknown     dw 'U','N','K','N','O','W','N',' ','S','T','A','T','E',0

; Font name
str_fontname    dw 'S','e','g','o','e',' ','U','I',0

; Version text building blocks
str_mswin       dw 'M','i','c','r','o','s','o','f','t',' ','W','i','n','d','o','w','s',0Ah
                dw 'V','e','r','s','i','o','n',' ',0
str_osbuild     dw ' ','(','O','S',' ','B','u','i','l','d',' ',0
str_closeparen  dw ')',0

; Author text
str_author      dw 'A','u','t','h','o','r',':',' ','M','a','r','e','k',' ','W','e','s','o','l','o','w','s','k','i',' ','(','W','E','S','M','A','R',')',0Ah
                dw 'h','t','t','p','s',':','/','/','k','v','c','.','p','l',' ','|',' '
                dw 'm','a','r','e','k','@','w','e','s','o','l','o','w','s','k','i','.','e','u','.','o','r','g',0

; Registry strings for version query
str_winkey      dw 'S','O','F','T','W','A','R','E','\','M','i','c','r','o','s','o','f','t','\','W','i','n','d','o','w','s',' ','N','T','\','C','u','r','r','e','n','t','V','e','r','s','i','o','n',0
str_dispver     dw 'D','i','s','p','l','a','y','V','e','r','s','i','o','n',0
str_buildnum    dw 'C','u','r','r','e','n','t','B','u','i','l','d','N','u','m','b','e','r',0

; Registry CLSID key for status check
str_clsidkey    dw 'C','L','S','I','D','\','{','a','b','0','b','3','7','e','c','-'
                dw '5','6','f','6','-','4','a','0','e','-','a','8','f','d','-'
                dw '7','a','8','b','f','7','c','2','d','a','9','6','}','\','I','n'
                dw 'P','r','o','c','S','e','r','v','e','r','3','2',0

; Expected patched value: %SystemRoot%\system32\ExpIorerFrame.dll (capital I)
str_regval_patched dw '%','S','y','s','t','e','m','R','o','o','t','%','\','s','y','s'
                   dw 't','e','m','3','2','\','E','x','p','I','o','r','e','r','F','r'
                   dw 'a','m','e','.','d','l','l',0

; ==============================================================================
; DATA
; ==============================================================================
.data
    g_hFontMain     dq 0
    g_hFontSmall    dq 0

; ==============================================================================
; CODE
; ==============================================================================
.code

; ==============================================================================
; ApplyDarkMode - enable DWM immersive dark mode and Mica on hwnd
; ==============================================================================
ApplyDarkMode proc
    sub     rsp, 28h
    mov     r10, rcx
    
    ; Dark Mode
    mov     dword ptr [rsp+20h], 1
    mov     r9d, 4
    lea     r8, [rsp+20h]
    mov     edx, DWMWA_USE_IMMERSIVE_DARK_MODE
    mov     rcx, r10
    call    DwmSetWindowAttribute
    
    mov     dword ptr [rsp+20h], 1
    mov     r9d, 4
    lea     r8, [rsp+20h]
    mov     edx, DWMWA_USE_IMMERSIVE_DARK_MODE_OLD
    mov     rcx, r10
    call    DwmSetWindowAttribute

    ; Mica Effect (Windows 11+)
    mov     dword ptr [rsp+20h], DWMSBT_MAINWINDOW
    mov     r9d, 4
    lea     r8, [rsp+20h]
    mov     edx, DWMWA_SYSTEMBACKDROP_TYPE
    mov     rcx, r10
    call    DwmSetWindowAttribute

    add     rsp, 28h
    ret
ApplyDarkMode endp

; ==============================================================================
; CreateModernFonts - Create Segoe UI fonts
; ==============================================================================
CreateModernFonts proc
    sub     rsp, 78h
    
    ; Create main font (size 20)
    lea     rax, str_fontname
    mov     qword ptr [rsp+68h], rax        ; 14: pszFaceName
    mov     dword ptr [rsp+60h], 0          ; 13: iPitchAndFamily (DEFAULT_PITCH)
    mov     dword ptr [rsp+58h], 5          ; 12: iQuality (CLEARTYPE_QUALITY)
    mov     dword ptr [rsp+50h], 0          ; 11: iClipPrecision
    mov     dword ptr [rsp+48h], 0          ; 10: iOutPrecision
    mov     dword ptr [rsp+40h], 1          ; 9: iCharSet (DEFAULT_CHARSET)
    mov     dword ptr [rsp+38h], 0          ; 8: bStrikeOut
    mov     dword ptr [rsp+30h], 0          ; 7: bUnderline
    mov     dword ptr [rsp+28h], 0          ; 6: bItalic
    mov     dword ptr [rsp+20h], 400        ; 5: cWeight (FW_NORMAL)
    xor     r9d, r9d                        ; 4: cOrientation
    xor     r8d, r8d                        ; 3: cEscapement
    xor     edx, edx                        ; 2: cWidth
    mov     ecx, -20                        ; 1: cHeight
    call    CreateFontW
    mov     g_hFontMain, rax

    ; Create smaller font (size 16)
    lea     rax, str_fontname
    mov     qword ptr [rsp+68h], rax
    mov     dword ptr [rsp+60h], 0
    mov     dword ptr [rsp+58h], 5
    mov     dword ptr [rsp+50h], 0
    mov     dword ptr [rsp+48h], 0
    mov     dword ptr [rsp+40h], 1
    mov     dword ptr [rsp+38h], 0
    mov     dword ptr [rsp+30h], 0
    mov     dword ptr [rsp+28h], 0
    mov     dword ptr [rsp+20h], 400
    xor     r9d, r9d
    xor     r8d, r8d
    xor     edx, edx
    mov     ecx, -16
    call    CreateFontW
    mov     g_hFontSmall, rax

    add     rsp, 78h
    ret
CreateModernFonts endp

; ==============================================================================
; QueryWinVersion - build version string in g_decryptBuf
; ==============================================================================
QueryWinVersion proc
    push    rbx
    sub     rsp, 50h

    lea     r10, [rsp+30h]
    mov     qword ptr [rsp+20h], r10
    mov     r9d, KEY_READ
    xor     r8d, r8d
    lea     rdx, str_winkey
    mov     ecx, HKLM_VALUE
    call    RegOpenKeyExW
    test    eax, eax
    jnz     @qwv_fail

    lea     rdx, str_mswin
    lea     rcx, g_decryptBuf
    call    wcscpy_p

    mov     dword ptr [rsp+3Ch], 520 * 2
    lea     r10, [rsp+3Ch]
    mov     qword ptr [rsp+28h], r10
    lea     r10, g_tempBuf
    mov     qword ptr [rsp+20h], r10
    lea     r10, [rsp+38h]
    mov     r9, r10
    xor     r8d, r8d
    lea     rdx, str_dispver
    mov     rcx, qword ptr [rsp+30h]
    call    RegQueryValueExW
    test    eax, eax
    jnz     @qwv_nodisp

    lea     rdx, g_tempBuf
    lea     rcx, g_decryptBuf
    call    wcscat_p

@qwv_nodisp:
    lea     rdx, str_osbuild
    lea     rcx, g_decryptBuf
    call    wcscat_p

    mov     dword ptr [rsp+3Ch], 520 * 2
    lea     r10, [rsp+3Ch]
    mov     qword ptr [rsp+28h], r10
    lea     r10, g_tempBuf
    mov     qword ptr [rsp+20h], r10
    lea     r10, [rsp+38h]
    mov     r9, r10
    xor     r8d, r8d
    lea     rdx, str_buildnum
    mov     rcx, qword ptr [rsp+30h]
    call    RegQueryValueExW
    test    eax, eax
    jnz     @qwv_nobuild

    lea     rdx, g_tempBuf
    lea     rcx, g_decryptBuf
    call    wcscat_p

@qwv_nobuild:
    lea     rdx, str_closeparen
    lea     rcx, g_decryptBuf
    call    wcscat_p

    mov     rcx, qword ptr [rsp+30h]
    call    RegCloseKey
    jmp     @qwv_ret

@qwv_fail:
    lea     rdx, str_mswin
    lea     rcx, g_decryptBuf
    call    wcscpy_p

@qwv_ret:
    add     rsp, 50h
    pop     rbx
    ret
QueryWinVersion endp

; ==============================================================================
; QueryPatchStatus - case-insensitive check of registry status
; ==============================================================================
QueryPatchStatus proc
    push    rbx
    sub     rsp, 50h

    lea     r10, [rsp+30h]
    mov     qword ptr [rsp+20h], r10
    mov     r9d, KEY_READ
    xor     r8d, r8d
    lea     rdx, str_clsidkey
    mov     ecx, HKCR_VALUE
    call    RegOpenKeyExW
    test    eax, eax
    jnz     @qps_unknown

    mov     dword ptr [rsp+3Ch], 520 * 2
    lea     r10, [rsp+3Ch]
    mov     qword ptr [rsp+28h], r10
    lea     r10, g_statusBuf
    mov     qword ptr [rsp+20h], r10
    lea     r10, [rsp+38h]
    mov     r9, r10
    xor     r8d, r8d
    xor     edx, edx
    mov     rcx, qword ptr [rsp+30h]
    call    RegQueryValueExW
    mov     rbx, rax
    mov     rcx, qword ptr [rsp+30h]
    call    RegCloseKey

    test    rbx, rbx
    jnz     @qps_unknown

    ; Compare g_statusBuf with str_regval_patched (case-insensitive)
    lea     rdx, str_regval_patched
    lea     rcx, g_statusBuf
    call    wcscmp_ci
    test    rax, rax
    jnz     @qps_matched

    mov     g_isPatchApplied, 0
    mov     g_queryResult, 0        ; unpatched
    lea     rax, str_unpatched
    jmp     @qps_ret

@qps_matched:
    mov     g_isPatchApplied, 1
    mov     g_queryResult, 1        ; patched
    lea     rax, str_patched
    jmp     @qps_ret

@qps_unknown:
    mov     g_isPatchApplied, 0
    mov     g_queryResult, 2        ; unknown (registry error)
    lea     rax, str_unknown

@qps_ret:
    add     rsp, 50h
    pop     rbx
    ret
QueryPatchStatus endp

; ==============================================================================
; RefreshStatusArea - force parent window to erase background behind status
; ==============================================================================
RefreshStatusArea proc
    sub     rsp, 28h
    cmp     dword ptr g_cliMode, 0
    jnz     @rfsa_ret               ; CLI mode: no windows to repaint
    ; InvalidateRect(hwnd, NULL, TRUE): RCX=hwnd, RDX=lpRect(NULL), R8=bErase(TRUE)
    ; 1. Invalidate parent area with erase (clears background under static)
    mov     r8d, 1          ; bErase = TRUE
    xor     edx, edx        ; lpRect = NULL (full window)
    mov     rcx, g_hwndMain
    call    InvalidateRect

    ; 2. Force immediate repaint of parent
    mov     rcx, g_hwndMain
    call    UpdateWindow

    ; 3. Invalidate status control with erase
    mov     r8d, 1          ; bErase = TRUE
    xor     edx, edx        ; lpRect = NULL
    mov     rcx, g_hwndStatus
    call    InvalidateRect

    ; 4. Force immediate repaint of child
    mov     rcx, g_hwndStatus
    call    UpdateWindow

@rfsa_ret:
    add     rsp, 28h
    ret
RefreshStatusArea endp

; ==============================================================================
; SetStatusOrange - set transition status (orange) text + redraw
;
; RCX = string pointer (wide, null-terminated)
; PUBLIC — callable from patch.asm during multi-phase operations
;
; Marks g_isPatchApplied=2 so WM_CTLCOLORSTATIC paints text orange.
; ==============================================================================
PUBLIC SetStatusOrange
SetStatusOrange proc
    sub     rsp, 28h
    cmp     dword ptr g_cliMode, 0
    jnz     @sos_ret                            ; CLI mode: skip window operations
    mov     rdx, rcx                            ; rdx = string
    mov     dword ptr g_isPatchApplied, 2       ; transition state → orange
    mov     rcx, g_hwndStatus
    call    SetWindowTextW
    call    RefreshStatusArea
@sos_ret:
    add     rsp, 28h
    ret
SetStatusOrange endp

; ==============================================================================
; UpdateStatus - refresh status text and repaint
; ==============================================================================
UpdateStatus proc
    sub     rsp, 28h
    call    QueryPatchStatus
    mov     rdx, rax
    mov     rcx, g_hwndStatus
    call    SetWindowTextW
    call    RefreshStatusArea
    add     rsp, 28h
    ret
UpdateStatus endp

; ==============================================================================
; WndProc
; ==============================================================================
PUBLIC WndProc
WndProc proc frame
    push    rbx
    .pushreg rbx
    push    rsi
    .pushreg rsi
    push    rdi
    .pushreg rdi
    push    r12
    .pushreg r12
    push    r13
    .pushreg r13
    sub     rsp, 20h
    .allocstack 20h
    .endprolog

    mov     r12, rcx
    mov     r13d, edx
    mov     rsi, r8
    mov     rdi, r9

    ; ------------------------------------------------------------------
    ; WM_CREATE
    ; ------------------------------------------------------------------
    cmp     r13d, WM_CREATE
    jne     @wp_ctlcolor

    sub     rsp, 60h

    ; Create Fonts
    call    CreateModernFonts

    ; Version STATIC (Centered)
    xor     rax, rax
    mov     qword ptr [rsp+58h], rax
    mov     rax, g_hInstance
    mov     qword ptr [rsp+50h], rax
    mov     rax, IDC_STATIC_VERSION
    mov     qword ptr [rsp+48h], rax
    mov     qword ptr [rsp+40h], r12
    mov     dword ptr [rsp+38h], 60
    mov     dword ptr [rsp+30h], 380
    mov     dword ptr [rsp+28h], 20
    mov     dword ptr [rsp+20h], 0
    mov     r9d, STY_STATIC or 1    ; SS_CENTER
    lea     r8, str_mswin
    lea     rdx, str_staticcls
    xor     ecx, ecx
    call    CreateWindowExW
    mov     g_hwndVersion, rax
    ; Set Font
    mov     r9d, 1
    mov     r8, g_hFontMain
    mov     edx, WM_SETFONT
    mov     rcx, rax
    call    SendMessageW

    ; Author STATIC (Centered)
    xor     rax, rax
    mov     qword ptr [rsp+58h], rax
    mov     rax, g_hInstance
    mov     qword ptr [rsp+50h], rax
    mov     rax, IDC_STATIC_AUTHOR
    mov     qword ptr [rsp+48h], rax
    mov     qword ptr [rsp+40h], r12
    mov     dword ptr [rsp+38h], 45
    mov     dword ptr [rsp+30h], 380
    mov     dword ptr [rsp+28h], 82
    mov     dword ptr [rsp+20h], 0
    mov     r9d, STY_STATIC or 1    ; SS_CENTER
    lea     r8, str_author
    lea     rdx, str_staticcls
    xor     ecx, ecx
    call    CreateWindowExW
    mov     g_hwndAuthor, rax
    ; Set Font
    mov     r9d, 1
    mov     r8, g_hFontSmall
    mov     edx, WM_SETFONT
    mov     rcx, rax
    call    SendMessageW

    ; APPLY PATCH button
    xor     rax, rax
    mov     qword ptr [rsp+58h], rax
    mov     rax, g_hInstance
    mov     qword ptr [rsp+50h], rax
    mov     rax, IDC_BTN_PATCH
    mov     qword ptr [rsp+48h], rax
    mov     qword ptr [rsp+40h], r12
    mov     dword ptr [rsp+38h], 35
    mov     dword ptr [rsp+30h], 140
    mov     dword ptr [rsp+28h], 135
    mov     dword ptr [rsp+20h], 45
    mov     r9d, STY_BUTTON_DEF
    lea     r8, str_btnpatch
    lea     rdx, str_buttoncls
    xor     ecx, ecx
    call    CreateWindowExW
    mov     g_hwndBtn, rax
    ; Set Font
    mov     r9d, 1
    mov     r8, g_hFontSmall
    mov     edx, WM_SETFONT
    mov     rcx, rax
    call    SendMessageW

    ; RESTORE button
    xor     rax, rax
    mov     qword ptr [rsp+58h], rax
    mov     rax, g_hInstance
    mov     qword ptr [rsp+50h], rax
    mov     rax, IDC_BTN_UNPATCH
    mov     qword ptr [rsp+48h], rax
    mov     qword ptr [rsp+40h], r12
    mov     dword ptr [rsp+38h], 35
    mov     dword ptr [rsp+30h], 140
    mov     dword ptr [rsp+28h], 135
    mov     dword ptr [rsp+20h], 195
    mov     r9d, STY_BUTTON
    lea     r8, str_btnrestore
    lea     rdx, str_buttoncls
    xor     ecx, ecx
    call    CreateWindowExW
    mov     g_hwndBtnUnpatch, rax
    ; Set Font
    mov     r9d, 1
    mov     r8, g_hFontSmall
    mov     edx, WM_SETFONT
    mov     rcx, rax
    call    SendMessageW

    ; Status STATIC (Centered)
    xor     rax, rax
    mov     qword ptr [rsp+58h], rax
    mov     rax, g_hInstance
    mov     qword ptr [rsp+50h], rax
    mov     rax, IDC_STATIC_STATUS
    mov     qword ptr [rsp+48h], rax
    mov     qword ptr [rsp+40h], r12
    mov     dword ptr [rsp+38h], 30
    mov     dword ptr [rsp+30h], 380
    mov     dword ptr [rsp+28h], 180
    mov     dword ptr [rsp+20h], 0
    mov     r9d, STY_STATIC or 1    ; SS_CENTER
    lea     r8, str_unknown
    lea     rdx, str_staticcls
    xor     ecx, ecx
    call    CreateWindowExW
    mov     g_hwndStatus, rax
    ; Set Font
    mov     r9d, 1
    mov     r8, g_hFontSmall
    mov     edx, WM_SETFONT
    mov     rcx, rax
    call    SendMessageW

    add     rsp, 60h

    ; Dark mode + Mica
    mov     rcx, r12
    call    ApplyDarkMode

    ; Init version text
    call    QueryWinVersion
    mov     rdx, offset g_decryptBuf
    mov     rcx, g_hwndVersion
    call    SetWindowTextW

    ; Init status text
    call    UpdateStatus

    xor     eax, eax
    jmp     @wp_ret

    ; ------------------------------------------------------------------
    ; WM_CTLCOLORSTATIC
    ; ------------------------------------------------------------------
@wp_ctlcolor:
    cmp     r13d, WM_CTLCOLORSTATIC
    jne     @wp_close

    ; Set transparency
    mov     edx, 1          ; TRANSPARENT
    mov     rcx, rsi        ; HDC
    call    SetBkMode

    ; Determine text color
    cmp     rdi, g_hwndVersion
    je      @wpc_white
    cmp     rdi, g_hwndAuthor
    je      @wpc_gray
    cmp     rdi, g_hwndStatus
    jne     @wpc_white
    
    cmp     g_isPatchApplied, 1
    je      @wpc_green
    cmp     g_isPatchApplied, 2
    je      @wpc_orange
    ; else red
    mov     edx, 005555FFh  ; Vibrant Red
    mov     rcx, rsi
    call    SetTextColor
    jmp     @wpc_null_brush

@wpc_orange:
    mov     edx, 0000A5FFh  ; Orange RGB(255,165,0) — transition
    mov     rcx, rsi
    call    SetTextColor
    jmp     @wpc_null_brush

@wpc_green:
    mov     edx, 0055FF55h  ; Vibrant Green
    mov     rcx, rsi
    call    SetTextColor
    jmp     @wpc_null_brush

@wpc_white:
    mov     edx, 00FFFFFFh  ; White
    mov     rcx, rsi
    call    SetTextColor
    jmp     @wpc_null_brush

@wpc_gray:
    mov     edx, 00AAAAAAh  ; Light Gray
    mov     rcx, rsi
    call    SetTextColor

@wpc_null_brush:
    ; Return NULL_BRUSH to let Mica show through
    mov     ecx, 5          ; HOLLOW_BRUSH
    call    GetStockObject
    jmp     @wp_ret

    ; ------------------------------------------------------------------
    ; WM_CLOSE
    ; ------------------------------------------------------------------
@wp_close:
    cmp     r13d, WM_CLOSE
    jne     @wp_destroy
    mov     rcx, r12
    call    DestroyWindow
    xor     eax, eax
    jmp     @wp_ret

    ; ------------------------------------------------------------------
    ; WM_DESTROY
    ; ------------------------------------------------------------------
@wp_destroy:
    cmp     r13d, WM_DESTROY
    jne     @wp_command
    
    ; Cleanup fonts
    mov     rcx, g_hFontMain
    call    DeleteObject
    mov     rcx, g_hFontSmall
    call    DeleteObject
    
    xor     ecx, ecx
    call    PostQuitMessage
    xor     eax, eax
    jmp     @wp_ret

    ; ------------------------------------------------------------------
    ; WM_COMMAND
    ; ------------------------------------------------------------------
@wp_command:
    cmp     r13d, WM_COMMAND
    jne     @wp_default

    movzx   eax, si

    cmp     eax, IDC_BTN_PATCH
    jne     @wp_try_unpatch

    mov     rcx, g_hwndStatus
    lea     rdx, str_working
    call    SetWindowTextW
    call    RefreshStatusArea   ; Prevent smearing of "WORKING..."
    call    RunPatch
    call    UpdateStatus
    xor     eax, eax
    jmp     @wp_ret

@wp_try_unpatch:
    cmp     eax, IDC_BTN_UNPATCH
    jne     @wp_default

    mov     rcx, g_hwndStatus
    lea     rdx, str_working
    call    SetWindowTextW
    call    RefreshStatusArea   ; Prevent smearing of "WORKING..."
    call    RunUnpatch
    call    UpdateStatus
    xor     eax, eax
    jmp     @wp_ret

    ; ------------------------------------------------------------------
    ; WM_DPICHANGED - resize window to suggested rect from lParam
    ; ------------------------------------------------------------------
@wp_dpichanged:
    cmp     r13d, WM_DPICHANGED
    jne     @wp_default

    ; rdi = lParam = RECT* {left, top, right, bottom}
    sub     rsp, 18h                                    ; room for args 5,6,7

    mov     eax, dword ptr [rdi+8]                      ; right
    sub     eax, dword ptr [rdi+0]                      ; - left = width
    mov     dword ptr [rsp+20h], eax                    ; arg5: cx

    mov     eax, dword ptr [rdi+12]                     ; bottom
    sub     eax, dword ptr [rdi+4]                      ; - top = height
    mov     dword ptr [rsp+28h], eax                    ; arg6: cy

    mov     dword ptr [rsp+30h], SWP_NOZORDER or SWP_NOACTIVATE  ; arg7: flags

    mov     r9d,  dword ptr [rdi+4]                     ; arg4: Y
    mov     r8d,  dword ptr [rdi+0]                     ; arg3: X
    xor     edx,  edx                                   ; arg2: hWndInsertAfter = NULL
    mov     rcx,  r12                                   ; arg1: hwnd
    call    SetWindowPos

    add     rsp, 18h
    xor     eax, eax
    jmp     @wp_ret

    ; ------------------------------------------------------------------
    ; Default
    ; ------------------------------------------------------------------
@wp_default:
    mov     r9,  rdi
    mov     r8,  rsi
    mov     edx, r13d
    mov     rcx, r12
    call    DefWindowProcW

@wp_ret:
    add     rsp, 20h
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
WndProc endp

; ==============================================================================
; CreateMainWindow
; ==============================================================================
PUBLIC CreateMainWindow
CreateMainWindow proc
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 0D0h

    lea     rdi, [rsp+70h]
    xor     eax, eax
    mov     ecx, 80/8
    rep     stosq

    mov     dword ptr [rsp+70h], WNDCLASSEXW_SIZE
    mov     dword ptr [rsp+74h], CS_HREDRAW or CS_VREDRAW
    lea     rax, WndProc
    mov     qword ptr [rsp+78h], rax

    mov     edx, IDI_ICON1
    mov     rcx, g_hInstance
    call    LoadIconW
    mov     qword ptr [rsp+90h], rax
    mov     qword ptr [rsp+0B8h], rax

    mov     edx, IDC_ARROW_ATOM
    xor     ecx, ecx
    call    LoadCursorW
    mov     qword ptr [rsp+98h], rax

    mov     rax, g_hInstance
    mov     qword ptr [rsp+88h], rax

    ; Black background brush
    mov     ecx, 4          ; BLACK_BRUSH
    call    GetStockObject
    mov     qword ptr [rsp+0A0h], rax

    lea     rax, str_wndclass
    mov     qword ptr [rsp+0B0h], rax

    lea     rcx, [rsp+70h]
    call    RegisterClassExW
    test    eax, eax
    jz      @cmw_fail

    ; Window (380x290) — extra height absorbs DPI-scaled title bar at 150%+
    xor     rax, rax
    mov     qword ptr [rsp+58h], rax
    mov     rbx, g_hInstance
    mov     qword ptr [rsp+50h], rbx
    mov     qword ptr [rsp+48h], rax
    mov     qword ptr [rsp+40h], rax
    mov     dword ptr [rsp+38h], 290
    mov     dword ptr [rsp+30h], 380
    mov     dword ptr [rsp+28h], 80000000h
    mov     dword ptr [rsp+20h], 80000000h
    mov     r9d, STY_MAINWIN
    lea     r8, str_title
    lea     rdx, str_wndclass
    xor     ecx, ecx
    call    CreateWindowExW
    test    rax, rax
    jz      @cmw_fail

    mov     g_hwndMain, rax
    mov     rbx, rax

    mov     edx, SW_SHOWNORMAL
    mov     rcx, rbx
    call    ShowWindow

    mov     rcx, rbx
    call    UpdateWindow

    mov     rax, rbx
    add     rsp, 0D0h
    pop     rdi
    pop     rsi
    pop     rbx
    ret

@cmw_fail:
    xor     eax, eax
    add     rsp, 0D0h
    pop     rdi
    pop     rsi
    pop     rbx
    ret
CreateMainWindow endp

end