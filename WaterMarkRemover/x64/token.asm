; ==============================================================================
; SignGuiPatcher - Token Manipulation and Privilege Management Module
;
; Author: Marek Wesołowski (wesmar)
; Purpose: Handles Windows security token operations including privilege
;          elevation, system impersonation, and TrustedInstaller token
;          acquisition. Core security module for the application.
; ==============================================================================

option casemap:none

include consts.inc
include globals.inc

; External function declarations - Windows API
EXTRN GetCurrentProcess:PROC
EXTRN OpenProcessToken:PROC
EXTRN LookupPrivilegeValueW:PROC
EXTRN AdjustTokenPrivileges:PROC
EXTRN GetLastError:PROC
EXTRN OpenProcess:PROC
EXTRN DuplicateTokenEx:PROC
EXTRN ImpersonateLoggedOnUser:PROC
EXTRN RevertToSelf:PROC
EXTRN CloseHandle:PROC
EXTRN GetTickCount:PROC
EXTRN Sleep:PROC
EXTRN OpenSCManagerW:PROC
EXTRN OpenServiceW:PROC
EXTRN QueryServiceStatusEx:PROC
EXTRN StartServiceW:PROC
EXTRN CloseServiceHandle:PROC
EXTRN CreateToolhelp32Snapshot:PROC
EXTRN Process32FirstW:PROC
EXTRN Process32NextW:PROC
EXTRN wcscpy_p:PROC
EXTRN wcscat_p:PROC
EXTRN wcscmp_ci:PROC

; External data - privilege name components
EXTRN privPrefix:WORD
EXTRN privSuffix:WORD

; External function for string decryption
EXTRN DecryptWideStr:PROC

; External buffer for decrypted strings
EXTRN g_decryptBuf:WORD

; ==============================================================================
; CONSTANT STRING DATA - OBFUSCATED
; ==============================================================================
.const
; Process name to impersonate (encrypted: "winlogon.exe")
str_winlogon_enc    db 0ddh,0aah,0c3h,0aah,0c4h,0aah,0c6h,0aah,0c5h,0aah,0cdh,0aah,0c5h,0aah,0c4h,0aah
                    db 084h,0aah,0cfh,0aah,0d2h,0aah,0cfh,0aah,0aah,0aah

; TrustedInstaller service name (encrypted)
str_tiSvcName_enc   db 0feh,0aah,0d8h,0aah,0dfh,0aah,0d9h,0aah,0deh,0aah,0cfh,0aah,0ceh,0aah,0e3h,0aah
                    db 0c4h,0aah,0d9h,0aah,0deh,0aah,0cbh,0aah,0c6h,0aah,0c6h,0aah,0cfh,0aah,0d8h,0aah
                    db 0aah,0aah

; ==============================================================================
; CODE SECTION
; ==============================================================================
.code

PUBLIC GetTIToken

; ==============================================================================
; BuildPrivilegeName - Construct Full Privilege Name String
;
; Purpose: Builds a complete Windows privilege name by combining:
;          "Se" + privilege_base_name + "Privilege"
;          Example: "Se" + "Debug" + "Privilege" = "SeDebugPrivilege"
;
; Parameters:
;   RCX = Pointer to privilege base name (e.g., "Debug")
;   RDX = Pointer to output buffer
;
; Returns:
;   RAX = Pointer to output buffer (same as RDX input)
;
; Example:
;   Input:  RCX -> "Debug", RDX -> buffer
;   Output: buffer contains "SeDebugPrivilege"
; ==============================================================================
BuildPrivilegeName proc frame
    push rbx
    .pushreg rbx
    push rsi
    .pushreg rsi
    push rdi
    .pushreg rdi
    sub rsp, 48
    .allocstack 48
    .endprolog

    mov rsi, rcx                ; RSI = privilege base name
    mov rdi, rdx                ; RDI = output buffer

    ; Copy "Se" prefix
    lea rdx, privPrefix
    mov rcx, rdi
    call wcscpy_p

    ; Append privilege base name
    mov rdx, rsi
    mov rcx, rdi
    call wcscat_p

    ; Append "Privilege" suffix
    lea rdx, privSuffix
    mov rcx, rdi
    call wcscat_p

    mov rax, rdi                ; Return output buffer pointer

    add rsp, 48
    pop rdi
    pop rsi
    pop rbx
    ret
BuildPrivilegeName endp

; ==============================================================================
; EnablePrivilege - Enable a Specific Privilege in Current Process Token
;
; Purpose: Enables a Windows privilege in the current process's access token.
;          Used to grant the current process necessary permissions before
;          performing privileged operations.
;
; Parameters:
;   ECX = Privilege index (0-33, corresponding to g_privTable array)
;
; Returns:
;   RAX = 1 on success, 0 on failure
;
; Stack frame: 624 bytes for:
;   - Token handle
;   - LUID structure
;   - TOKEN_PRIVILEGES structure
;   - Privilege name buffer (expanded from base name)
;
; Privilege indices:
;   3 = SeDebugPrivilege (required for opening winlogon.exe)
;   4 = SeImpersonatePrivilege (required for impersonation)
; ==============================================================================
EnablePrivilege proc frame
    push rbx
    .pushreg rbx
    push rsi
    .pushreg rsi
    push rdi
    .pushreg rdi
    push r12
    .pushreg r12
    push r13
    .pushreg r13
    sub rsp, 624
    .allocstack 624
    .endprolog

    mov r12d, ecx               ; R12 = privilege index

    ; Validate privilege index (must be 0-33)
    cmp r12d, 34
    jae ep_fail                 ; Out of range

    ; Get pointer to privilege base name from g_privTable
    mov eax, r12d
    shl rax, 3                  ; Multiply by 8 (size of pointer)
    lea rbx, g_privTable
    add rax, rbx
    mov rbx, qword ptr [rax]    ; RBX = pointer to privilege base name

    ; Build full privilege name (e.g., "SeDebugPrivilege")
    lea rdx, [rsp+80]           ; Output buffer on stack
    mov rcx, rbx                ; Input: privilege base name
    call BuildPrivilegeName

    ; Get current process handle
    sub rsp, 32
    call GetCurrentProcess
    add rsp, 32
    mov r13, rax                ; R13 = current process pseudo-handle

    ; Open process token with query and adjust privileges access
    ; BOOL OpenProcessToken(
    ;   [in]  HANDLE  ProcessHandle,        -> r13
    ;   [in]  DWORD   DesiredAccess,        -> TOKEN_QUERY_ADJUST
    ;   [out] PHANDLE TokenHandle           -> [rsp+40]
    ; )
    lea r8, [rsp+40]            ; R8 = &token handle
    mov edx, TOKEN_QUERY_ADJUST ; EDX = desired access
    mov rcx, r13                ; RCX = process handle
    sub rsp, 32
    call OpenProcessToken
    add rsp, 32
    test eax, eax
    jz ep_fail                  ; Failed to open token

    ; Look up the LUID for the privilege
    ; BOOL LookupPrivilegeValueW(
    ;   [in, optional] LPCWSTR lpSystemName,    -> NULL
    ;   [in]           LPCWSTR lpName,          -> privilege name
    ;   [out]          PLUID   lpLuid           -> [rsp+48]
    ; )
    lea r8, [rsp+48]            ; R8 = &LUID output
    lea rdx, [rsp+80]           ; RDX = privilege name
    xor ecx, ecx                ; RCX = NULL (local system)
    sub rsp, 32
    call LookupPrivilegeValueW
    add rsp, 32
    test eax, eax
    jz ep_close_fail            ; Failed to lookup privilege

    ; Build TOKEN_PRIVILEGES structure
    ; Structure layout:
    ;   DWORD PrivilegeCount;                 [rsp+56]
    ;   LUID_AND_ATTRIBUTES Privileges[1];    [rsp+60]
    ;     LUID Luid;                          [rsp+60] (8 bytes)
    ;     DWORD Attributes;                   [rsp+68]
    
    mov dword ptr [rsp+56], 1   ; PrivilegeCount = 1
    mov rax, [rsp+48]           ; Get LUID
    mov [rsp+60], rax           ; Set Luid
    mov dword ptr [rsp+68], SE_PRIVILEGE_ENABLED ; Enable the privilege

    ; Adjust token privileges
    ; BOOL AdjustTokenPrivileges(
    ;   [in]            HANDLE            TokenHandle,
    ;   [in]            BOOL              DisableAllPrivileges,
    ;   [in, optional]  PTOKEN_PRIVILEGES NewState,
    ;   [in]            DWORD             BufferLength,
    ;   [out, optional] PTOKEN_PRIVILEGES PreviousState,
    ;   [out, optional] PDWORD            ReturnLength
    ; )
    sub rsp, 48                 ; Reserve stack space for extra params
    xor r9d, r9d
    mov [rsp+32], r9            ; PreviousState = NULL
    mov [rsp+40], r9            ; ReturnLength = NULL
    mov r9d, 16                 ; R9 = BufferLength (size of TOKEN_PRIVILEGES)
    lea r8, [rsp+56+48]         ; R8 = NewState
    xor edx, edx                ; EDX = DisableAllPrivileges = FALSE
    mov rcx, [rsp+40+48]        ; RCX = token handle
    call AdjustTokenPrivileges
    add rsp, 48
    test eax, eax
    jz ep_close_fail            ; API failed

    ; Check for errors even if API returned TRUE
    ; AdjustTokenPrivileges returns TRUE even if some privileges weren't set
    sub rsp, 32
    call GetLastError
    add rsp, 32
    test eax, eax
    jnz ep_close_fail           ; Error occurred

    ; Success - close token handle
    mov rcx, [rsp+40]
    sub rsp, 32
    call CloseHandle
    add rsp, 32

    mov eax, 1                  ; Return success
    jmp ep_done

ep_close_fail:
    ; Failure - close token handle before returning
    mov rcx, [rsp+40]
    sub rsp, 32
    call CloseHandle
    add rsp, 32

ep_fail:
    xor eax, eax                ; Return failure

ep_done:
    add rsp, 624
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
EnablePrivilege endp

; ==============================================================================
; GetProcessIdByName - Find Process ID by Executable Name
;
; Purpose: Searches for a running process by its executable name and returns
;          its process ID. Uses toolhelp32 API to enumerate processes.
;
; Parameters:
;   RCX = Pointer to process name string (e.g., "winlogon.exe")
;
; Returns:
;   RAX = Process ID if found, 0 if not found
;
; Stack frame: 632 bytes for PROCESSENTRY32W structure (568 bytes) + overhead
;
; Note: This function performs case-sensitive comparison of the process name.
; ==============================================================================
GetProcessIdByName proc frame
    push rbx
    .pushreg rbx
    push rsi
    .pushreg rsi
    push rdi
    .pushreg rdi
    push r12
    .pushreg r12
    sub rsp, 632
    .allocstack 632
    .endprolog

    mov r12, rcx                ; R12 = target process name

    ; Create a snapshot of all processes
    ; HANDLE CreateToolhelp32Snapshot(
    ;   [in] DWORD dwFlags,           -> TH32CS_SNAPPROCESS
    ;   [in] DWORD th32ProcessID      -> 0 (all processes)
    ; )
    xor edx, edx
    mov ecx, TH32CS_SNAPPROCESS
    sub rsp, 32
    call CreateToolhelp32Snapshot
    add rsp, 32
    cmp rax, INVALID_HANDLE_VALUE
    je gp_fail                  ; Snapshot creation failed
    mov rbx, rax                ; RBX = snapshot handle

    ; Initialize PROCESSENTRY32W structure size
    mov dword ptr [rsp+40], PROCESSENTRY32W_SIZE

    ; Get first process entry
    ; BOOL Process32FirstW(
    ;   [in]      HANDLE           hSnapshot,      -> rbx
    ;   [in, out] LPPROCESSENTRY32W lppe           -> [rsp+40]
    ; )
    lea rdx, [rsp+40]
    mov rcx, rbx
    sub rsp, 32
    call Process32FirstW
    add rsp, 32
    test eax, eax
    jz gp_close_fail            ; No processes found

gp_loop:
    ; Compare process name (szExeFile is at offset 44 in PROCESSENTRY32W)
    lea rcx, [rsp+40+44]        ; RCX = current process name
    mov rdx, r12                ; RDX = target process name
    sub rsp, 32
    call wcscmp_ci
    add rsp, 32
    test eax, eax
    jnz gp_match                ; Match found

gp_next:
    ; Get next process entry
    ; BOOL Process32NextW(
    ;   [in]  HANDLE           hSnapshot,
    ;   [out] LPPROCESSENTRY32W lppe
    ; )
    lea rdx, [rsp+40]
    mov rcx, rbx
    sub rsp, 32
    call Process32NextW
    add rsp, 32
    test eax, eax
    jnz gp_loop                 ; More processes to check
    jmp gp_close_fail           ; No more processes, not found

gp_match:
    ; Process found - extract and return process ID
    ; th32ProcessID is at offset 8 in PROCESSENTRY32W
    mov eax, dword ptr [rsp+40+8]
    mov [rsp+32], eax           ; Save PID
    
    ; Close snapshot handle
    mov rcx, rbx
    sub rsp, 32
    call CloseHandle
    add rsp, 32
    
    mov eax, [rsp+32]           ; Return PID
    jmp gp_done

gp_close_fail:
    ; Close snapshot handle before failing
    mov rcx, rbx
    sub rsp, 32
    call CloseHandle
    add rsp, 32

gp_fail:
    xor eax, eax                ; Return 0 (not found)

gp_done:
    add rsp, 632
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
GetProcessIdByName endp

; ==============================================================================
; ImpersonateSystem - Impersonate SYSTEM Account via winlogon.exe
;
; Purpose: Impersonates the SYSTEM account by duplicating the token from
;          winlogon.exe process. This is a critical step to gain sufficient
;          privileges to access the TrustedInstaller service.
;
; Process:
;   1. Enable SeDebugPrivilege to open system processes
;   2. Find winlogon.exe process ID
;   3. Open winlogon.exe process
;   4. Open process token
;   5. Duplicate token as impersonation token
;   6. Impersonate using duplicated token
;
; Parameters: None
;
; Returns:
;   RAX = 1 on success, 0 on failure
;
; Stack frame: 96 bytes for handles and temporary data
;
; Notes:
;   - winlogon.exe always runs as SYSTEM
;   - Requires SeDebugPrivilege (index 3)
;   - Creates an impersonation token (not primary token)
;   - Caller must call RevertToSelf() to end impersonation
; ==============================================================================
ImpersonateSystem proc frame
    push rbx
    .pushreg rbx
    push rsi
    .pushreg rsi
    push rdi
    .pushreg rdi
    sub rsp, 96
    .allocstack 96
    .endprolog

    ; Enable SeDebugPrivilege (required to open winlogon.exe)
    mov ecx, 3                  ; Privilege index 3 = SeDebugPrivilege
    call EnablePrivilege
    ; Continue even if this fails (might already be enabled)

    ; Decrypt winlogon.exe process name
    lea rcx, str_winlogon_enc
    lea rdx, g_decryptBuf
    call DecryptWideStr

    ; Find winlogon.exe process
    lea rcx, g_decryptBuf
    call GetProcessIdByName
    test eax, eax
    jz is_fail                  ; winlogon.exe not found
    mov edi, eax                ; EDI = winlogon process ID

    ; Open winlogon.exe process
    ; HANDLE OpenProcess(
    ;   [in] DWORD dwDesiredAccess,     -> PROCESS_QUERY_DUP
    ;   [in] BOOL  bInheritHandle,      -> FALSE
    ;   [in] DWORD dwProcessId          -> edi
    ; )
    mov r8d, edi                ; R8 = process ID
    xor edx, edx                ; EDX = don't inherit handle
    mov ecx, PROCESS_QUERY_DUP  ; ECX = query + dup handle access
    sub rsp, 32
    call OpenProcess
    add rsp, 32
    test rax, rax
    jz is_fail                  ; Failed to open process
    mov rbx, rax                ; RBX = process handle

    ; Open process token
    ; BOOL OpenProcessToken(
    ;   [in]  HANDLE  ProcessHandle,
    ;   [in]  DWORD   DesiredAccess,    -> TOKEN_DUP_QUERY
    ;   [out] PHANDLE TokenHandle       -> [rsp+40]
    ; )
    lea r8, [rsp+40]
    mov edx, TOKEN_DUP_QUERY
    mov rcx, rbx
    sub rsp, 32
    call OpenProcessToken
    add rsp, 32
    test eax, eax
    jz is_close_proc            ; Failed to open token

    ; Duplicate token as impersonation token
    ; BOOL DuplicateTokenEx(
    ;   [in]           HANDLE                       ExistingTokenHandle,
    ;   [in]           DWORD                        dwDesiredAccess,
    ;   [in, optional] LPSECURITY_ATTRIBUTES        lpTokenAttributes,
    ;   [in]           SECURITY_IMPERSONATION_LEVEL ImpersonationLevel,
    ;   [in]           TOKEN_TYPE                   TokenType,
    ;   [out]          PHANDLE                      phNewToken
    ; )
    sub rsp, 48
    lea rax, [rsp+48+48]
    mov [rsp+40], rax           ; phNewToken = [rsp+48]
    mov qword ptr [rsp+32], TOKEN_TYPE_IMPERSONATION ; TokenType
    mov r9d, SECURITY_IMPERSONATION_LVL ; ImpersonationLevel
    xor r8d, r8d                ; lpTokenAttributes = NULL
    mov edx, MAXIMUM_ALLOWED    ; dwDesiredAccess
    mov rcx, [rsp+40+48]        ; ExistingTokenHandle = [rsp+40]
    call DuplicateTokenEx
    add rsp, 48
    test eax, eax
    jz is_close_sys             ; Duplication failed

    ; Impersonate using the duplicated token
    ; BOOL ImpersonateLoggedOnUser(
    ;   [in] HANDLE hToken                -> [rsp+48]
    ; )
    mov rcx, [rsp+48]
    sub rsp, 32
    call ImpersonateLoggedOnUser
    add rsp, 32
    test eax, eax
    jz is_close_dup             ; Impersonation failed

    ; Success - clean up handles and return
    mov rcx, [rsp+48]           ; Close duplicated token
    sub rsp, 32
    call CloseHandle
    add rsp, 32
    
    mov rcx, [rsp+40]           ; Close original token
    sub rsp, 32
    call CloseHandle
    add rsp, 32
    
    mov rcx, rbx                ; Close process handle
    sub rsp, 32
    call CloseHandle
    add rsp, 32

    mov eax, 1                  ; Return success
    jmp is_done

is_close_dup:
    ; Cleanup: close duplicated token
    mov rcx, [rsp+48]
    sub rsp, 32
    call CloseHandle
    add rsp, 32

is_close_sys:
    ; Cleanup: close original token
    mov rcx, [rsp+40]
    sub rsp, 32
    call CloseHandle
    add rsp, 32

is_close_proc:
    ; Cleanup: close process handle
    mov rcx, rbx
    sub rsp, 32
    call CloseHandle
    add rsp, 32

is_fail:
    xor eax, eax                ; Return failure

is_done:
    add rsp, 96
    pop rdi
    pop rsi
    pop rbx
    ret
ImpersonateSystem endp

; ==============================================================================
; StartTIService - Start the TrustedInstaller Service
;
; Purpose: Ensures the TrustedInstaller service is running. Opens the service,
;          checks its status, and starts it if necessary. Waits for the service
;          to reach running state before returning.
;
; Process:
;   1. Open Service Control Manager
;   2. Open TrustedInstaller service
;   3. Query service status
;   4. If stopped, start the service
;   5. Wait up to 2 seconds for service to start
;   6. Return process ID of running service
;
; Parameters: None
;
; Returns:
;   RAX = Process ID of TrustedInstaller service if running, 0 on failure
;
; Stack frame: 136 bytes for SERVICE_STATUS_PROCESS structure and handles
;
; Retry logic:
;   - Maximum 10 attempts
;   - 200ms delay between attempts
;   - Total maximum wait time: ~2 seconds
; ==============================================================================
StartTIService proc frame
    push rbx
    .pushreg rbx
    push rsi
    .pushreg rsi
    push rdi
    .pushreg rdi
    push r12
    .pushreg r12
    sub rsp, 136
    .allocstack 136
    .endprolog

    ; Open Service Control Manager
    ; SC_HANDLE OpenSCManagerW(
    ;   [in, optional] LPCWSTR lpMachineName,      -> NULL (local)
    ;   [in, optional] LPCWSTR lpDatabaseName,     -> NULL (default)
    ;   [in]           DWORD   dwDesiredAccess     -> SC_MANAGER_CONNECT
    ; )
    mov r8d, SC_MANAGER_CONNECT ; R8 = desired access
    xor edx, edx                ; EDX = database name (NULL)
    xor ecx, ecx                ; ECX = machine name (NULL)
    sub rsp, 32
    call OpenSCManagerW
    add rsp, 32
    test rax, rax
    jz ss_fail                  ; Failed to open SCM
    mov rbx, rax                ; RBX = SCM handle

    ; Decrypt TrustedInstaller service name
    lea rcx, str_tiSvcName_enc
    lea rdx, g_decryptBuf
    call DecryptWideStr

    ; Open TrustedInstaller service
    ; SC_HANDLE OpenServiceW(
    ;   [in] SC_HANDLE hSCManager,           -> rbx
    ;   [in] LPCWSTR   lpServiceName,        -> g_decryptBuf
    ;   [in] DWORD     dwDesiredAccess       -> SERVICE_QS (query + start)
    ; )
    mov r8d, SERVICE_QS         ; R8 = query status + start access
    lea rdx, g_decryptBuf
    mov rcx, rbx
    sub rsp, 32
    call OpenServiceW
    add rsp, 32
    test rax, rax
    jz ss_close_scm             ; Failed to open service
    mov rsi, rax                ; RSI = service handle

    ; Query service status
    ; BOOL QueryServiceStatusEx(
    ;   [in]            SC_HANDLE      hService,
    ;   [in]            SC_STATUS_TYPE InfoLevel,
    ;   [out, optional] LPBYTE         lpBuffer,
    ;   [in]            DWORD          cbBufSize,
    ;   [out]           LPDWORD        pcbBytesNeeded
    ; )
    sub rsp, 48
    lea rax, [rsp+88+48]
    mov [rsp+32], rax           ; pcbBytesNeeded
    mov r9d, SERVICE_STATUS_PROCESS_SIZE ; cbBufSize
    lea r8, [rsp+40+48]         ; lpBuffer = [rsp+40]
    mov edx, SC_STATUS_PROCESS_INFO ; InfoLevel
    mov rcx, rsi                ; hService
    call QueryServiceStatusEx
    add rsp, 48
    test eax, eax
    jz ss_close_svc             ; Query failed

    ; Check current service state (dwCurrentState at offset 4)
    mov eax, dword ptr [rsp+40+4]
    cmp eax, SERVICE_RUNNING
    je ss_running               ; Already running

    cmp eax, SERVICE_STOPPED
    jne ss_close_svc            ; Service in unexpected state

    ; Service is stopped - start it
    ; BOOL StartServiceW(
    ;   [in]           SC_HANDLE hService,
    ;   [in]           DWORD      dwNumServiceArgs,    -> 0
    ;   [in, optional] LPCWSTR    *lpServiceArgVectors -> NULL
    ; )
    xor r8d, r8d                ; No service arguments
    xor edx, edx
    mov rcx, rsi
    sub rsp, 32
    call StartServiceW
    add rsp, 32
    ; Continue even if start fails (might already be starting)

    ; Retry loop: Wait for service to reach running state
    ; Maximum 10 attempts with 200ms delay = ~2 seconds total
    mov edi, 10                 ; EDI = retry counter

ss_retry:
    ; Sleep for 200 milliseconds
    mov ecx, 200
    sub rsp, 32
    call Sleep
    add rsp, 32

    ; Query service status again
    sub rsp, 48
    lea rax, [rsp+88+48]
    mov [rsp+32], rax           ; pcbBytesNeeded
    mov r9d, SERVICE_STATUS_PROCESS_SIZE
    lea r8, [rsp+40+48]         ; lpBuffer
    mov edx, SC_STATUS_PROCESS_INFO
    mov rcx, rsi
    call QueryServiceStatusEx
    add rsp, 48
    test eax, eax
    jz ss_close_svc             ; Query failed

    ; Check if service is now running
    cmp dword ptr [rsp+40+4], SERVICE_RUNNING
    je ss_running               ; Service started successfully

    ; Decrement retry counter and try again if not exhausted
    dec edi
    jnz ss_retry                ; More retries remaining
    jmp ss_close_svc            ; Timeout - service didn't start

ss_running:
    ; Service is running - extract process ID (dwProcessId at offset 28)
    mov eax, dword ptr [rsp+40+28]
    mov r12d, eax               ; R12 = service process ID

    ; Close service handle
    mov rcx, rsi
    sub rsp, 32
    call CloseServiceHandle
    add rsp, 32
    
    ; Close SCM handle
    mov rcx, rbx
    sub rsp, 32
    call CloseServiceHandle
    add rsp, 32

    mov eax, r12d               ; Return process ID
    jmp ss_done

ss_close_svc:
    ; Cleanup: close service handle
    mov rcx, rsi
    sub rsp, 32
    call CloseServiceHandle
    add rsp, 32

ss_close_scm:
    ; Cleanup: close SCM handle
    mov rcx, rbx
    sub rsp, 32
    call CloseServiceHandle
    add rsp, 32

ss_fail:
    xor eax, eax                ; Return 0 (failure)

ss_done:
    add rsp, 136
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
StartTIService endp

; ==============================================================================
; GetTIToken - Obtain TrustedInstaller Access Token
;
; Purpose: Core function that obtains a TrustedInstaller token with all
;          privileges enabled. Implements token caching for performance.
;
; Process overview:
;   1. Check cache (token valid for 30 seconds)
;   2. If expired or missing:
;      a. Enable SeDebugPrivilege and SeImpersonatePrivilege
;      b. Impersonate SYSTEM account
;      c. Start TrustedInstaller service
;      d. Open TrustedInstaller process
;      e. Duplicate its token
;      f. Enable all 34 privileges on the duplicated token
;      g. Revert impersonation
;      h. Cache the token
;
; Parameters: None
;
; Returns:
;   RAX = TrustedInstaller token handle on success, 0 on failure
;
; Stack frame: 688 bytes for:
;   - Token handles
;   - LUID structures
;   - TOKEN_PRIVILEGES structures
;   - Privilege name buffers
;
; Cache behavior:
;   - Cached token is valid for 30 seconds (30000 milliseconds)
;   - Old token is closed when cache expires
;   - Cache timestamp stored in g_tokenTime
;   - Cached handle stored in g_cachedToken
;
; Privilege enabling:
;   - Loops through all 34 privileges in g_privTable
;   - Attempts to enable each privilege
;   - Continues even if some privileges fail (not all may be available)
; ==============================================================================
GetTIToken proc frame
    push rbx
    .pushreg rbx
    push rsi
    .pushreg rsi
    push rdi
    .pushreg rdi
    push r12
    .pushreg r12
    push r13
    .pushreg r13
    push r14
    .pushreg r14
    push r15
    .pushreg r15
    sub rsp, 688
    .allocstack 688
    .endprolog

    ; Get current time in milliseconds
    sub rsp, 32
    call GetTickCount
    add rsp, 32
    mov r12d, eax               ; R12 = current time

    ; Check if cached token is still valid (< 30 seconds old)
    mov ecx, g_tokenTime        ; ECX = cached token timestamp
    mov eax, r12d
    sub eax, ecx                ; EAX = time difference
    cmp eax, 30000              ; Compare with 30 seconds
    ja gt_expired               ; Token expired

    ; Check if we have a cached token
    mov rax, g_cachedToken
    test rax, rax
    jz gt_expired               ; No cached token
    
    ; Return cached token
    mov rax, g_cachedToken
    jmp gt_done

gt_expired:
    ; Token expired or doesn't exist - close old token if present
    mov rax, g_cachedToken
    test rax, rax
    jz gt_no_old                ; No old token to close
    mov rcx, rax
    sub rsp, 32
    call CloseHandle
    add rsp, 32
    mov qword ptr g_cachedToken, 0 ; Clear cached token

gt_no_old:
    ; Enable required privileges for the operation
    mov ecx, 3                  ; SeDebugPrivilege
    call EnablePrivilege
    
    mov ecx, 4                  ; SeImpersonatePrivilege
    call EnablePrivilege

    ; Impersonate SYSTEM to access TrustedInstaller service
    call ImpersonateSystem
    test eax, eax
    jz gt_fail                  ; Impersonation failed

    ; Start TrustedInstaller service and get its process ID
    call StartTIService
    test eax, eax
    jz gt_revert                ; Service start failed
    mov r13d, eax               ; R13 = TrustedInstaller process ID

    ; Open TrustedInstaller process
    ; HANDLE OpenProcess(
    ;   [in] DWORD dwDesiredAccess,     -> PROCESS_QUERY_INFORMATION
    ;   [in] BOOL  bInheritHandle,      -> FALSE
    ;   [in] DWORD dwProcessId          -> r13d
    ; )
    mov r8d, r13d               ; R8 = process ID
    xor edx, edx                ; EDX = don't inherit
    mov ecx, PROCESS_QUERY_INFORMATION
    sub rsp, 32
    call OpenProcess
    add rsp, 32
    test rax, rax
    jz gt_revert                ; Failed to open process
    mov r14, rax                ; R14 = TrustedInstaller process handle

    ; Open TrustedInstaller process token
    ; BOOL OpenProcessToken(
    ;   [in]  HANDLE  ProcessHandle,
    ;   [in]  DWORD   DesiredAccess,    -> TOKEN_DUP_QUERY_ADJ
    ;   [out] PHANDLE TokenHandle       -> [rsp+40]
    ; )
    lea r8, [rsp+40]
    mov edx, TOKEN_DUP_QUERY_ADJ ; Query + Duplicate + Adjust
    mov rcx, r14
    sub rsp, 32
    call OpenProcessToken
    add rsp, 32
    test eax, eax
    jz gt_close_proc            ; Failed to open token

    ; Duplicate the TrustedInstaller token as a primary token
    ; BOOL DuplicateTokenEx(
    ;   [in]           HANDLE                       ExistingTokenHandle,
    ;   [in]           DWORD                        dwDesiredAccess,
    ;   [in, optional] LPSECURITY_ATTRIBUTES        lpTokenAttributes,
    ;   [in]           SECURITY_IMPERSONATION_LEVEL ImpersonationLevel,
    ;   [in]           TOKEN_TYPE                   TokenType,
    ;   [out]          PHANDLE                      phNewToken
    ; )
    sub rsp, 48
    lea rax, [rsp+48+48]
    mov [rsp+40], rax           ; phNewToken = [rsp+48]
    mov qword ptr [rsp+32], 1   ; TokenType = TokenPrimary
    mov r9d, SECURITY_IMPERSONATION_LVL ; ImpersonationLevel
    xor r8d, r8d                ; lpTokenAttributes = NULL
    mov edx, MAXIMUM_ALLOWED    ; dwDesiredAccess
    mov rcx, [rsp+40+48]        ; ExistingTokenHandle
    call DuplicateTokenEx
    add rsp, 48
    test eax, eax
    jz gt_close_titoken         ; Duplication failed

    ; Initialize privilege loop counter
    mov dword ptr [rsp+56], 0

gt_priv_loop:
    ; Check if all privileges have been processed (0-33 = 34 total)
    cmp dword ptr [rsp+56], 34
    jge gt_priv_done            ; All privileges processed

    ; Get pointer to current privilege base name
    mov eax, [rsp+56]           ; Current privilege index
    shl rax, 3                  ; Multiply by 8
    lea rbx, g_privTable
    add rax, rbx
    mov rbx, qword ptr [rax]    ; RBX = privilege base name

    ; Build full privilege name
    lea rdx, [rsp+120]          ; Output buffer
    mov rcx, rbx                ; Input: base name
    call BuildPrivilegeName

    ; Look up privilege LUID
    ; BOOL LookupPrivilegeValueW(
    ;   [in, optional] LPCWSTR lpSystemName,    -> NULL
    ;   [in]           LPCWSTR lpName,          -> privilege name
    ;   [out]          PLUID   lpLuid           -> [rsp+64]
    ; )
    lea r8, [rsp+64]            ; LUID output
    lea rdx, [rsp+120]          ; Privilege name
    xor ecx, ecx                ; NULL = local system
    sub rsp, 32
    call LookupPrivilegeValueW
    add rsp, 32
    test eax, eax
    jz gt_priv_next             ; Privilege not found, skip

    ; Build TOKEN_PRIVILEGES structure for this privilege
    mov dword ptr [rsp+80], 1   ; PrivilegeCount = 1
    mov rax, [rsp+64]           ; Get LUID
    mov [rsp+84], rax           ; Set Luid
    mov dword ptr [rsp+92], SE_PRIVILEGE_ENABLED ; Enable it

    ; Adjust token privileges to enable this privilege
    ; BOOL AdjustTokenPrivileges(
    ;   [in]            HANDLE            TokenHandle,
    ;   [in]            BOOL              DisableAllPrivileges,
    ;   [in, optional]  PTOKEN_PRIVILEGES NewState,
    ;   [in]            DWORD             BufferLength,
    ;   [out, optional] PTOKEN_PRIVILEGES PreviousState,
    ;   [out, optional] PDWORD            ReturnLength
    ; )
    sub rsp, 48
    xor r9d, r9d
    mov [rsp+32], r9            ; PreviousState = NULL
    mov [rsp+40], r9            ; ReturnLength = NULL
    mov r9d, 16                 ; BufferLength
    lea r8, [rsp+80+48]         ; NewState
    xor edx, edx                ; DisableAllPrivileges = FALSE
    mov rcx, [rsp+48+48]        ; TokenHandle = [rsp+48]
    call AdjustTokenPrivileges
    add rsp, 48
    ; Continue even if this fails - some privileges might not be available

gt_priv_next:
    ; Move to next privilege
    inc dword ptr [rsp+56]
    jmp gt_priv_loop

gt_priv_done:
    ; All privileges processed - revert impersonation
    sub rsp, 32
    call RevertToSelf
    add rsp, 32

    ; Close TrustedInstaller process token (we have our duplicate)
    mov rcx, [rsp+40]
    sub rsp, 32
    call CloseHandle
    add rsp, 32

    ; Close TrustedInstaller process handle
    mov rcx, r14
    sub rsp, 32
    call CloseHandle
    add rsp, 32

    ; Cache the new token
    mov rax, [rsp+48]           ; Get duplicated token
    mov g_cachedToken, rax      ; Store in cache

    ; Update cache timestamp
    sub rsp, 32
    call GetTickCount
    add rsp, 32
    mov g_tokenTime, eax

    ; Return cached token
    mov rax, g_cachedToken
    jmp gt_done

gt_close_titoken:
    ; Cleanup: close TrustedInstaller token
    mov rcx, [rsp+40]
    sub rsp, 32
    call CloseHandle
    add rsp, 32

gt_close_proc:
    ; Cleanup: close TrustedInstaller process
    mov rcx, r14
    sub rsp, 32
    call CloseHandle
    add rsp, 32

gt_revert:
    ; Cleanup: revert impersonation
    sub rsp, 32
    call RevertToSelf
    add rsp, 32

gt_fail:
    xor rax, rax                ; Return NULL (failure)

gt_done:
    add rsp, 688
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
GetTIToken endp

end