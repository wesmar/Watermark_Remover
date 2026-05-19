; ==============================================================================
; SignGuiPatcher - Patch Module
;
; Author: Marek Wesołowski (wesmar)
; Purpose: Extract ExplorerFrame.dll from embedded CAB inside RCDATA resource,
;          deploy to System32 as ExpIorerFrame.dll (capital I, visually ≡ l),
;          update COM CLSID InProcServer32 registry key, restart Explorer.
; ==============================================================================

option casemap:none

include consts.inc
include globals.inc

EXTRN GetTIToken                :PROC
EXTRN CloseHandle               :PROC
EXTRN FDICreate                 :PROC
EXTRN FDICopy                   :PROC
EXTRN FDIDestroy                :PROC
EXTRN FindResourceW             :PROC
EXTRN LoadResource              :PROC
EXTRN SizeofResource            :PROC
EXTRN LockResource              :PROC
EXTRN GetProcessHeap            :PROC
EXTRN HeapAlloc                 :PROC
EXTRN HeapFree                  :PROC
EXTRN GetSystemDirectoryW       :PROC
EXTRN ImpersonateLoggedOnUser   :PROC
EXTRN RevertToSelf              :PROC
EXTRN CreateFileW               :PROC
EXTRN WriteFile                 :PROC
EXTRN RegOpenKeyExW             :PROC
EXTRN RegSetValueExW            :PROC
EXTRN RegCloseKey               :PROC
EXTRN CreateToolhelp32Snapshot  :PROC
EXTRN Process32FirstW           :PROC
EXTRN Process32NextW            :PROC
EXTRN OpenProcess               :PROC
EXTRN TerminateProcess          :PROC
EXTRN WaitForSingleObject       :PROC
EXTRN WaitForMultipleObjects    :PROC
EXTRN ShellExecuteExW           :PROC
EXTRN DeleteFileW               :PROC
EXTRN MoveFileExW               :PROC
EXTRN GetLastError              :PROC
EXTRN wcscpy_p                  :PROC
EXTRN wcscat_p                  :PROC
EXTRN wcscmp_ci                 :PROC
EXTRN SetStatusOrange           :PROC

; ==============================================================================
; CONSTANT STRINGS
; ==============================================================================
.const

; ANSI strings for FDI (char*, not WCHAR)
ansi_cab    db "memory.cab", 0
ansi_path   db 0

; Backslash + DLL name: \ExpIorerFrame.dll
; Note: 4th char is capital I (U+0049), NOT lowercase l (U+006C) — visually identical
str_dllname dw '\','E','x','p','I','o','r','e','r','F','r','a','m','e','.','d','l','l',0

; COM CLSID key: CLSID\{ab0b37ec-56f6-4a0e-a8fd-7a8bf7c2da96}\InProcServer32
str_clsidkey dw 'C','L','S','I','D','\','{','a','b','0','b','3','7','e','c','-'
             dw '5','6','f','6','-','4','a','0','e','-','a','8','f','d','-'
             dw '7','a','8','b','f','7','c','2','d','a','9','6','}','\','I','n'
             dw 'P','r','o','c','S','e','r','v','e','r','3','2',0

; Default value data: %SystemRoot%\system32\ExpIorerFrame.dll
str_regval  dw '%','S','y','s','t','e','m','R','o','o','t','%','\','s','y','s'
            dw 't','e','m','3','2','\','E','x','p','I','o','r','e','r','F','r'
            dw 'a','m','e','.','d','l','l',0
STR_REGVAL_BYTES EQU 80   ; (sizeof str_regval in bytes, including null)

; explorer.exe (wide)
str_explorerexe dw 'e','x','p','l','o','r','e','r','.','e','x','e',0

; ShellExecuteExW lpParameters: /e, (opens explorer without visible window)
str_expparams   dw '/','e',',',0

; Original InProcServer32 value: %SystemRoot%\system32\ExplorerFrame.dll (lowercase l)
str_regval_orig dw '%','S','y','s','t','e','m','R','o','o','t','%','\','s','y','s'
                dw 't','e','m','3','2','\','E','x','p','l','o','r','e','r','F','r'
                dw 'a','m','e','.','d','l','l',0
STR_REGVAL_ORIG_BYTES EQU 80

; Transactional status messages (orange)
str_st_extract      dw 'E','X','T','R','A','C','T','I','N','G',' ','R','E','S','O','U','R','C','E','S','.','.','.',0
str_st_kill_exp     dw 'S','T','O','P','P','I','N','G',' ','E','X','P','L','O','R','E','R','.','.','.',0
str_st_writing      dw 'W','R','I','T','I','N','G',' ','F','I','L','E','.','.','.',0
str_st_upd_reg      dw 'U','P','D','A','T','I','N','G',' ','R','E','G','I','S','T','R','Y','.','.','.',0
str_st_restore_reg  dw 'R','E','S','T','O','R','I','N','G',' ','R','E','G','I','S','T','R','Y','.','.','.',0
str_st_start_exp    dw 'S','T','A','R','T','I','N','G',' ','E','X','P','L','O','R','E','R','.','.','.',0
str_st_remove       dw 'R','E','M','O','V','I','N','G',' ','F','I','L','E','.','.','.',0
str_st_wait_exp     dw 'W','A','I','T','I','N','G',' ','F','O','R',' ','E','X','P','L','O','R','E','R','.','.','.',0

; ==============================================================================
; MODULE-LOCAL DATA (not exported)
; ==============================================================================
.data
    align 8

; FDI state globals
g_fdiCabPtr     dq 0        ; pointer to first byte of MSCF data
g_fdiCabOff     dq 0        ; current read offset within CAB
g_fdiCabEnd     dq 0        ; total CAB size (resource_size - ICON_SIZE)
g_fdiOutPtr     dq 0        ; HeapAlloc'd output buffer
g_fdiOutUsed    dq 0        ; bytes written to output so far

; ==============================================================================
; CODE
; ==============================================================================
.code

; ==============================================================================
; FDI CALLBACKS
; All follow x64 calling convention (DIAMONDAPI = standard on x64).
; ==============================================================================

; fdi_alloc(ULONG cb) → HeapAlloc(GetProcessHeap(),0,cb)
; 0 pushes; sub 28h → RSP%16=0 ✓
fdi_alloc proc
    sub     rsp, 28h
    mov     r10, rcx            ; save cb
    call    GetProcessHeap
    mov     r8, r10             ; cb
    xor     edx, edx            ; flags=0
    mov     rcx, rax
    call    HeapAlloc
    add     rsp, 28h
    ret
fdi_alloc endp

; fdi_free(void* pv) → HeapFree
; 0 pushes; sub 28h → RSP%16=0 ✓
fdi_free proc
    sub     rsp, 28h
    mov     r10, rcx            ; save pv
    call    GetProcessHeap
    mov     r8, r10             ; pv
    xor     edx, edx
    mov     rcx, rax
    call    HeapFree
    add     rsp, 28h
    ret
fdi_free endp

; fdi_open(char* pszFile, int oflag, int pmode) → return 1 (dummy handle)
fdi_open proc
    mov     eax, 1
    ret
fdi_open endp

; fdi_close(INT_PTR hf) → return 0
fdi_close proc
    xor     eax, eax
    ret
fdi_close endp

; fdi_seek(INT_PTR hf, LONG dist, int seektype) → new offset
; RCX=hf [ignored], EDX=dist, R8D=seektype
fdi_seek proc
    movsxd  rax, edx            ; rax = dist (sign-extended)
    cmp     r8d, SEEK_SET_VAL
    je      @fsk_set
    cmp     r8d, SEEK_CUR_VAL
    je      @fsk_cur
    ; SEEK_END: new offset = cabEnd + dist
    add     rax, g_fdiCabEnd
    jmp     @fsk_store
@fsk_set:
    ; rax already = dist
    jmp     @fsk_store
@fsk_cur:
    add     rax, g_fdiCabOff
@fsk_store:
    mov     g_fdiCabOff, rax
    ; return as LONG (EAX = low 32 bits)
    ret
fdi_seek endp

; fdi_read(INT_PTR hf, void* pv, UINT cb) → bytes copied
; RCX=hf [ignored], RDX=dst, R8D=count
; 3 pushes (odd) + sub 20h → RSP%16=0 ✓
fdi_read proc
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 20h

    mov     ebx, r8d            ; count requested (UINT)
    ; clamp to remaining bytes
    mov     rax, g_fdiCabEnd
    sub     rax, g_fdiCabOff    ; remaining
    cmp     rbx, rax
    jbe     @fr_count_ok
    mov     rbx, rax            ; cap at remaining
@fr_count_ok:
    test    rbx, rbx
    jz      @fr_done

    mov     rdi, rdx            ; dst
    mov     rsi, g_fdiCabPtr
    add     rsi, g_fdiCabOff    ; src = base + offset
    mov     rcx, rbx
    rep     movsb

    add     g_fdiCabOff, rbx

@fr_done:
    mov     eax, ebx            ; return bytes read
    add     rsp, 20h
    pop     rdi
    pop     rsi
    pop     rbx
    ret
fdi_read endp

; fdi_write(INT_PTR hf, void* pv, UINT cb) → bytes written
; RCX=hf [ignored], RDX=src, R8D=count
; 3 pushes (odd) + sub 20h → RSP%16=0 ✓
fdi_write proc
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 20h

    mov     ebx, r8d            ; count
    test    ebx, ebx
    jz      @fw_done

    mov     rdi, g_fdiOutPtr
    add     rdi, g_fdiOutUsed   ; dst = outBuf + used
    mov     rsi, rdx            ; src
    mov     rcx, rbx
    rep     movsb

    add     g_fdiOutUsed, rbx

@fw_done:
    mov     eax, ebx
    add     rsp, 20h
    pop     rdi
    pop     rsi
    pop     rbx
    ret
fdi_write endp

; fdi_notify(FDINOTIFICATIONTYPE fdint, PFDINOTIFICATION pfdin) → INT_PTR
; ECX=fdint, RDX=pfdin [ignored — globals used]
fdi_notify proc
    cmp     ecx, fdintCOPY_FILE
    je      @fn_copy
    cmp     ecx, fdintCLOSE_FILE_INFO
    je      @fn_close
    xor     eax, eax
    ret
@fn_copy:
    mov     eax, 1              ; non-zero = extract this file
    ret
@fn_close:
    mov     eax, 1              ; TRUE
    ret
fdi_notify endp

; ==============================================================================
; DoDecompress - load RCDATA 102, skip ICON_SIZE bytes, run FDI
;
; RCX = hInstance
; Returns EAX = 1 on success (g_fdiOutPtr/g_fdiOutUsed filled), 0 on failure
;
; Non-volatile: rbx rsi rdi (3 pushes, odd → RSP%16=0 after)
; sub 70h (112≡0): RSP%16=0-0=0 ✓ before CALL
; Stack layout:
;   [00..1F] shadow
;   [20..47] FDICreate/FDICopy extra params
;   [48..5F] spare
;   [60..6B] ERF struct (12 bytes)
;   [6C..6F] pad
; ==============================================================================
DoDecompress proc
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 70h

    mov     rbx, rcx            ; rbx = hInstance

    ; --- FindResourceW(hInstance, IDI_RES_CAB, RT_RCDATA) ---
    mov     r8d, RT_RCDATA
    mov     edx, IDI_RES_CAB
    mov     rcx, rbx
    call    FindResourceW
    test    rax, rax
    jz      @dd_fail
    mov     rsi, rax            ; rsi = hRes

    ; --- SizeofResource ---
    mov     rdx, rsi
    mov     rcx, rbx
    call    SizeofResource
    cmp     eax, ICON_SIZE + 4  ; must be > ICON_SIZE
    jbe     @dd_fail
    mov     rdi, rax            ; rdi = resSize (as QWORD, top bits zero)

    ; --- LoadResource ---
    mov     rdx, rsi
    mov     rcx, rbx
    call    LoadResource
    test    rax, rax
    jz      @dd_fail
    mov     rsi, rax            ; rsi = hGlobal

    ; --- LockResource ---
    mov     rcx, rsi
    call    LockResource
    test    rax, rax
    jz      @dd_fail

    ; Set FDI globals: CAB starts at resData + ICON_SIZE
    lea     r10, [rax + ICON_SIZE]
    mov     g_fdiCabPtr, r10
    mov     g_fdiCabOff, 0
    mov     r10, rdi
    sub     r10, ICON_SIZE
    mov     g_fdiCabEnd, r10    ; CAB size = resSize - ICON_SIZE

    ; --- HeapAlloc output buffer (4 MB) ---
    call    GetProcessHeap
    mov     r8, FDI_DLL_BUFSIZE
    xor     edx, edx
    mov     rcx, rax
    call    HeapAlloc
    test    rax, rax
    jz      @dd_fail
    mov     g_fdiOutPtr, rax
    mov     g_fdiOutUsed, 0

    ; --- Zero ERF at [rsp+60h] ---
    xor     eax, eax
    mov     qword ptr [rsp+60h], rax
    mov     dword ptr [rsp+68h], eax

    ; --- FDICreate ---
    ; RCX=pfnalloc, RDX=pfnfree, R8=pfnopen, R9=pfnread
    ; [rsp+20]=pfnwrite, [rsp+28]=pfnclose, [rsp+30]=pfnseek
    ; [rsp+38]=cpuUNKNOWN, [rsp+40]=&erf
    lea     r10, fdi_write
    mov     qword ptr [rsp+20h], r10
    lea     r10, fdi_close
    mov     qword ptr [rsp+28h], r10
    lea     r10, fdi_seek
    mov     qword ptr [rsp+30h], r10
    xor     eax, eax
    mov     qword ptr [rsp+38h], rax     ; cpuUNKNOWN=0
    lea     rax, [rsp+60h]
    mov     qword ptr [rsp+40h], rax     ; &erf
    lea     r9, fdi_read
    lea     r8, fdi_open
    lea     rdx, fdi_free
    lea     rcx, fdi_alloc
    call    FDICreate
    test    rax, rax
    jz      @dd_failbuf
    mov     rbx, rax            ; rbx = hfdi

    ; --- FDICopy ---
    ; RCX=hfdi, RDX=pszCab(ANSI), R8=pszPath(ANSI), R9=flags
    ; [rsp+20]=pfnNotify, [rsp+28]=pfnProgress, [rsp+30]=pvUser
    lea     r10, fdi_notify
    mov     qword ptr [rsp+20h], r10
    xor     eax, eax
    mov     qword ptr [rsp+28h], rax    ; progress=NULL
    mov     qword ptr [rsp+30h], rax    ; pvUser=NULL
    xor     r9d, r9d                    ; flags=0
    lea     r8, ansi_path
    lea     rdx, ansi_cab
    mov     rcx, rbx
    call    FDICopy

    ; --- FDIDestroy ---
    mov     rcx, rbx
    call    FDIDestroy

    ; success if output bytes written > 0
    cmp     g_fdiOutUsed, 0
    je      @dd_failbuf
    mov     eax, 1
    jmp     @dd_ret

@dd_failbuf:
    ; free output buffer on failure
    call    GetProcessHeap
    mov     r8, g_fdiOutPtr
    xor     edx, edx
    mov     rcx, rax
    call    HeapFree
    mov     g_fdiOutPtr, 0

@dd_fail:
    xor     eax, eax

@dd_ret:
    add     rsp, 70h
    pop     rdi
    pop     rsi
    pop     rbx
    ret
DoDecompress endp

; ==============================================================================
; WriteDll - write g_fdiOutPtr/g_fdiOutUsed to System32\ExpIorerFrame.dll
;
; RCX = TI token
; Returns EAX = 1 on success, 0 on failure
;
; 1 push rbx (odd→RSP%16=0) + sub 50h (80≡0 → RSP%16=0) ✓
; Stack:
;   [00..1F] shadow
;   [20..27] CreateFileW param5 (CREATE_ALWAYS)
;   [28..2F] CreateFileW param6 (FILE_ATTRIBUTE_NORMAL)
;   [30..37] CreateFileW param7 (NULL hTemplate)
;   [38..3F] local: bytesWritten DWORD + WriteFile param5 (NULL lpOverlapped)
;   [40..4F] spare (WriteFile param5 NULL at [rsp+20h])
; ==============================================================================
WriteDll proc
    push    rbx
    sub     rsp, 50h

    mov     rbx, rcx            ; rbx = tiToken

    ; Build path in g_tempBuf: GetSystemDirectoryW(g_tempBuf, 260)
    mov     edx, 260
    lea     rcx, g_tempBuf
    call    GetSystemDirectoryW

    ; Append \ExpIorerFrame.dll
    lea     rdx, str_dllname
    lea     rcx, g_tempBuf
    call    wcscat_p

    ; ImpersonateLoggedOnUser(tiToken)
    mov     rcx, rbx
    call    ImpersonateLoggedOnUser
    test    eax, eax
    jz      @wd_fail

    ; CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL)
    mov     qword ptr [rsp+20h], CREATE_ALWAYS
    mov     qword ptr [rsp+28h], FILE_ATTRIBUTE_NORMAL
    mov     qword ptr [rsp+30h], 0          ; hTemplate=NULL
    xor     r9d, r9d                        ; lpSecurityAttributes=NULL
    xor     r8d, r8d                        ; dwShareMode=0
    mov     edx, GENERIC_WRITE
    lea     rcx, g_tempBuf
    call    CreateFileW
    cmp     rax, INVALID_HANDLE_VALUE
    je      @wd_revert_fail

    ; hFile → save in stack local
    mov     qword ptr [rsp+40h], rax

    ; WriteFile(hFile, g_fdiOutPtr, g_fdiOutUsed, &bytesWritten, NULL)
    mov     qword ptr [rsp+20h], 0           ; lpOverlapped=NULL
    lea     r9, [rsp+38h]                    ; &bytesWritten
    mov     r8, g_fdiOutUsed                 ; cbToWrite
    mov     rdx, g_fdiOutPtr
    mov     rcx, qword ptr [rsp+40h]         ; hFile
    call    WriteFile

    ; CloseHandle(hFile)
    mov     rcx, qword ptr [rsp+40h]
    call    CloseHandle

    ; RevertToSelf
    call    RevertToSelf

    mov     eax, 1
    jmp     @wd_ret

@wd_revert_fail:
    call    RevertToSelf
@wd_fail:
    xor     eax, eax
@wd_ret:
    add     rsp, 50h
    pop     rbx
    ret
WriteDll endp

; ==============================================================================
; UpdateRegistry - set HKCR\CLSID\{...}\InProcServer32 to ExpIorerFrame.dll
;
; RCX = TI token
; Returns EAX = 1 on success, 0 on failure
;
; 1 push rbx (odd→RSP%16=0) + sub 40h (64≡0 → RSP%16=0) ✓
; Stack:
;   [00..1F] shadow
;   [20..27] RegOpenKeyExW param5 (&hKey) / RegSetValueExW param5 (data ptr)
;   [28..2F] RegSetValueExW param6 (cbData)
;   [30..37] opened hKey storage
;   [38..3F] spare
; ==============================================================================
UpdateRegistry proc
    push    rbx
    sub     rsp, 40h

    mov     rbx, rcx            ; rbx = tiToken

    ; ImpersonateLoggedOnUser
    mov     rcx, rbx
    call    ImpersonateLoggedOnUser
    test    eax, eax
    jz      @ur_fail

    ; RegOpenKeyExW(HKCR, str_clsidkey, 0, KEY_WRITE_64, &hKey)
    ; KEY_WRITE_64 = KEY_WRITE | KEY_WOW64_64KEY — forces machine-wide 64-bit view
    lea     r10, [rsp+30h]
    mov     qword ptr [rsp+20h], r10        ; &hKey (5th param on stack)
    mov     r9d, KEY_WRITE_64
    xor     r8d, r8d                        ; ulOptions=0
    lea     rdx, str_clsidkey
    xor     ecx, ecx
    mov     ecx, HKCR_VALUE
    call    RegOpenKeyExW
    test    eax, eax
    jnz     @ur_revert_fail

    ; RegSetValueExW(hKey, L"", 0, REG_EXPAND_SZ, str_regval, STR_REGVAL_BYTES)
    mov     qword ptr [rsp+28h], STR_REGVAL_BYTES
    lea     r10, str_regval
    mov     qword ptr [rsp+20h], r10        ; lpData
    mov     r9d, REG_EXPAND_SZ              ; dwType
    xor     r8d, r8d                        ; Reserved=0
    xor     edx, edx                        ; lpValueName=NULL (default value)
    mov     rcx, qword ptr [rsp+30h]        ; hKey
    call    RegSetValueExW
    ; save result
    mov     rbx, rax                        ; rbx = error code (0=ok)

    ; RegCloseKey
    mov     rcx, qword ptr [rsp+30h]
    call    RegCloseKey

    call    RevertToSelf

    test    rbx, rbx
    jnz     @ur_fail
    mov     eax, 1
    jmp     @ur_ret

@ur_revert_fail:
    call    RevertToSelf
@ur_fail:
    xor     eax, eax
@ur_ret:
    add     rsp, 40h
    pop     rbx
    ret
UpdateRegistry endp

; ==============================================================================
; KillExplorer - terminate ALL explorer.exe in PARALLEL
;
; No params, no return.
; Algorithm matches C++ RestartExplorer:
;   snapshot → for each explorer.exe: OpenProcess + TerminateProcess (no wait)
;              store handle in array
;   WaitForMultipleObjects(handles, TRUE, 500)
;   CloseHandle all
;
; Up to 32 handles per pass.
;
; 3 pushes (odd→RSP%16=0); sub 140h (320≡0→RSP%16=0) ✓
; Stack:
;   [00..1F]   shadow
;   [20..23]   n_handles DWORD
;   [24..27]   spare
;   [28..2F]   hSnap QWORD
;   [30..12F]  handles[32] (256 bytes)
;   [130..13F] spare
; ==============================================================================
KillExplorer proc
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 140h

    ; HeapAlloc pEntry (reused across passes)
    call    GetProcessHeap
    mov     r8, PROCESSENTRY32W_SIZE
    xor     edx, edx
    mov     rcx, rax
    call    HeapAlloc
    test    rax, rax
    jz      @ke_ret
    mov     rdi, rax                            ; rdi = pEntry

    mov     dword ptr [rsp+20h], 0              ; n_handles = 0
    mov     dword ptr [rdi], PROCESSENTRY32W_SIZE

    xor     edx, edx
    mov     ecx, TH32CS_SNAPPROCESS
    call    CreateToolhelp32Snapshot
    cmp     rax, INVALID_HANDLE_VALUE
    je      @ke_free
    mov     qword ptr [rsp+28h], rax            ; hSnap

    mov     rdx, rdi
    mov     rcx, rax
    call    Process32FirstW
    test    eax, eax
    jz      @ke_snap_close

@ke_inner:
    ; szExeFile (at [rdi+2Ch]) == "explorer.exe" ? (case-insensitive)
    lea     rcx, [rdi + 2Ch]
    lea     rdx, str_explorerexe
    call    wcscmp_ci                           ; returns 1 if equal, 0 otherwise
    test    eax, eax
    jz      @ke_iter

@ke_open:
    ; Array full (32)?
    mov     eax, dword ptr [rsp+20h]
    cmp     eax, 32
    jae     @ke_iter

    ; OpenProcess(PROCESS_TERM_SYNC, FALSE, th32ProcessID)
    mov     r8d, dword ptr [rdi + 8h]
    xor     edx, edx
    mov     ecx, PROCESS_TERM_SYNC
    call    OpenProcess
    test    rax, rax
    jz      @ke_iter
    mov     rbx, rax                            ; rbx = hProc

    ; handles[n_handles++] = hProc
    mov     ecx, dword ptr [rsp+20h]
    lea     r10, [rsp+30h]
    mov     qword ptr [r10 + rcx*8], rbx
    inc     dword ptr [rsp+20h]

    ; TerminateProcess (returns immediately, no wait)
    xor     edx, edx
    mov     rcx, rbx
    call    TerminateProcess

@ke_iter:
    mov     dword ptr [rdi], PROCESSENTRY32W_SIZE
    mov     rdx, rdi
    mov     rcx, qword ptr [rsp+28h]
    call    Process32NextW
    test    eax, eax
    jnz     @ke_inner

@ke_snap_close:
    mov     rcx, qword ptr [rsp+28h]
    call    CloseHandle

    ; Anything to wait for?
    mov     ecx, dword ptr [rsp+20h]
    test    ecx, ecx
    jz      @ke_free                            ; n_handles == 0 → clean

    lea     rcx, str_st_wait_exp
    call    SetStatusOrange

    ; WaitForMultipleObjects(nCount, &handles, bWaitAll=TRUE, dwMilliseconds=500)
    mov     ecx, dword ptr [rsp+20h]
    lea     rdx, [rsp+30h]
    mov     r8d, 1
    mov     r9d, 500
    call    WaitForMultipleObjects

    ; CloseHandle all
    xor     ebx, ebx
@ke_close:
    cmp     ebx, dword ptr [rsp+20h]
    jae     @ke_close_done
    lea     r10, [rsp+30h]
    mov     rcx, qword ptr [r10 + rbx*8]
    call    CloseHandle
    inc     ebx
    jmp     @ke_close
@ke_close_done:

@ke_free:
    call    GetProcessHeap
    mov     r8, rdi
    xor     edx, edx
    mov     rcx, rax
    call    HeapFree

@ke_ret:
    add     rsp, 140h
    pop     rdi
    pop     rsi
    pop     rbx
    ret
KillExplorer endp

; ==============================================================================
; StartExplorer - relaunch explorer invisibly, matching the working C++ path
; ==============================================================================
; 1 push rdi (odd→RSP%16=0); sub 90h (144≡0→RSP%16=0) ✓ before CALL
; Stack: [00..1F]=shadow, [20..8F]=SHELLEXECUTEINFOW (112 bytes)
StartExplorer proc
    push    rdi
    sub     rsp, 90h

    ; Zero SHELLEXECUTEINFOW at [rsp+20h] (112 bytes = 14 qwords)
    lea     rdi, [rsp+20h]
    xor     eax, eax
    mov     ecx, 112/8
    rep     stosq

    ; cbSize = sizeof(SHELLEXECUTEINFOW)
    mov     dword ptr [rsp+20h], SHELLEXECUTEINFOW_SIZE
    ; fMask = SEE_MASK_FLAG_NO_UI
    mov     dword ptr [rsp+24h], SEE_MASK_FLAG_NO_UI
    ; lpFile = L"explorer.exe"
    lea     rax, str_explorerexe
    mov     qword ptr [rsp+38h], rax
    ; lpParameters = L"/e,"
    lea     rax, str_expparams
    mov     qword ptr [rsp+40h], rax
    ; nShow = SW_HIDE = 0, already zeroed

    lea     rcx, [rsp+20h]
    call    ShellExecuteExW

    add     rsp, 90h
    pop     rdi
    ret
StartExplorer endp

; ==============================================================================
; DeleteFileRetry - DeleteFileW with short poll loop for handle release
;
; RCX = path
; Returns EAX = 1 on success (deleted or file-not-found), 0 on timeout/fail.
;
; Uses direct DeleteFileW. By the time this runs, old Explorer instances have
; been waited out and the new Explorer has started from the restored registry.
; Caller must hold TI impersonation before calling.
;
; 2 pushes rbx+rdi (even→RSP%16=8); sub 28h (40≡8→RSP%16=0) ✓
DeleteFileRetry proc
    push    rbx
    push    rdi
    sub     rsp, 28h

    mov     rdi, rcx                            ; rdi = path

    mov     rcx, rdi
    call    DeleteFileW
    test    eax, eax
    jnz     @dfr_success

    call    GetLastError
    cmp     eax, ERROR_FILE_NOT_FOUND
    je      @dfr_success
    jmp     @dfr_movefile

@dfr_movefile:
    ; Schedule for delete at next reboot only as a last-resort cleanup hint.
    mov     r8d, MOVEFILE_DELAY_UNTIL_REBOOT
    xor     edx, edx
    mov     rcx, rdi
    call    MoveFileExW
    xor     eax, eax
    jmp     @dfr_ret

@dfr_success:
    mov     eax, 1

@dfr_ret:
    add     rsp, 28h
    pop     rdi
    pop     rbx
    ret
DeleteFileRetry endp

; ==============================================================================
; RunPatch - Execute the full patch operation
; ==============================================================================
PUBLIC RunPatch
RunPatch proc
    push    rbx
    push    rsi
    sub     rsp, 28h

    call    GetTIToken
    test    rax, rax
    jz      @rp_fail
    mov     rbx, rax

    lea     rcx, str_st_extract
    call    SetStatusOrange
    mov     rcx, g_hInstance
    call    DoDecompress
    test    eax, eax
    jz      @rp_fail

    lea     rcx, str_st_writing
    call    SetStatusOrange
    mov     rcx, rbx
    call    WriteDll
    test    eax, eax
    jz      @rp_cleanup_fail

    lea     rcx, str_st_upd_reg
    call    SetStatusOrange
    mov     rcx, rbx
    call    UpdateRegistry
    test    eax, eax
    jz      @rp_cleanup_fail

    lea     rcx, str_st_kill_exp
    call    SetStatusOrange
    call    KillExplorer

    lea     rcx, str_st_start_exp
    call    SetStatusOrange
    call    StartExplorer

    mov     esi, 1
    jmp     @rp_cleanup

@rp_cleanup_fail:
    xor     esi, esi

@rp_cleanup:
    call    GetProcessHeap
    mov     r8, g_fdiOutPtr
    xor     edx, edx
    mov     rcx, rax
    call    HeapFree
    mov     g_fdiOutPtr, 0
    mov     g_fdiOutUsed, 0

    mov     eax, esi
    jmp     @rp_ret

@rp_fail:
    xor     eax, eax
@rp_ret:
    add     rsp, 28h
    pop     rsi
    pop     rbx
    ret
RunPatch endp

; ==============================================================================
; RunUnpatch - Restore original ExplorerFrame.dll, restart Explorer, delete fake
; ==============================================================================
PUBLIC RunUnpatch
RunUnpatch proc
    push    rbx
    push    rsi
    sub     rsp, 48h

    call    GetTIToken
    test    rax, rax
    jz      @ru_fail
    mov     rbx, rax

    ; ─── STEP 1: Restore registry first. If Explorer auto-respawns while we work,
    ; it must see the original DLL path, not the fake one we are about to delete.
    lea     rcx, str_st_restore_reg
    call    SetStatusOrange

    mov     rcx, rbx
    call    ImpersonateLoggedOnUser
    test    eax, eax
    jz      @ru_fail

    lea     r10, [rsp+30h]
    mov     qword ptr [rsp+20h], r10
    mov     r9d, KEY_WRITE_64
    xor     r8d, r8d
    lea     rdx, str_clsidkey
    mov     ecx, HKCR_VALUE
    call    RegOpenKeyExW
    test    eax, eax
    jnz     @ru_rev_fail

    mov     qword ptr [rsp+28h], STR_REGVAL_ORIG_BYTES
    lea     r10, str_regval_orig
    mov     qword ptr [rsp+20h], r10
    mov     r9d, REG_EXPAND_SZ
    xor     r8d, r8d
    xor     edx, edx
    mov     rcx, qword ptr [rsp+30h]
    call    RegSetValueExW
    mov     rsi, rax

    mov     rcx, qword ptr [rsp+30h]
    call    RegCloseKey
    call    RevertToSelf

    test    rsi, rsi
    jnz     @ru_fail

    ; ─── STEP 2: Kill old Explorer instances after registry restore.
    lea     rcx, str_st_kill_exp
    call    SetStatusOrange
    call    KillExplorer

    ; ─── STEP 3: Start a fresh Explorer. It reads the original ExplorerFrame path.
    lea     rcx, str_st_start_exp
    call    SetStatusOrange
    call    StartExplorer

    ; ─── STEP 4: Delete file (TI rights). The new Explorer should not map it.
    lea     rcx, str_st_remove
    call    SetStatusOrange

    xor     esi, esi                            ; delete result, default failure
    mov     rcx, rbx
    call    ImpersonateLoggedOnUser
    test    eax, eax
    jz      @ru_fail

    mov     edx, 260
    lea     rcx, g_tempBuf
    call    GetSystemDirectoryW
    lea     rdx, str_dllname
    lea     rcx, g_tempBuf
    call    wcscat_p

    lea     rcx, g_tempBuf
    call    DeleteFileRetry
    mov     esi, eax
    call    RevertToSelf
    test    esi, esi
    jz      @ru_fail

    mov     eax, esi
    jmp     @ru_ret

@ru_rev_fail:
    call    RevertToSelf
@ru_fail:
    xor     eax, eax
@ru_ret:
    add     rsp, 48h
    pop     rsi
    pop     rbx
    ret
RunUnpatch endp

end
