; ==============================================================================
; SignGuiPatcher - Constants
; ==============================================================================

; ------------------------------------------------------------------------------
; TOKEN ACCESS RIGHTS
; ------------------------------------------------------------------------------
TOKEN_QUERY                 EQU 0008h
TOKEN_ADJUST_PRIVILEGES     EQU 0020h
TOKEN_DUPLICATE             EQU 0002h
TOKEN_QUERY_ADJUST          EQU 0028h
TOKEN_DUP_QUERY             EQU 000Ah
TOKEN_DUP_QUERY_ADJ         EQU 002Ah
MAXIMUM_ALLOWED             EQU 02000000h

; ------------------------------------------------------------------------------
; SECURITY / TOKEN
; ------------------------------------------------------------------------------
SE_PRIVILEGE_ENABLED        EQU 00000002h
SECURITY_IMPERSONATION_LVL  EQU 2
TOKEN_TYPE_IMPERSONATION    EQU 2

; ------------------------------------------------------------------------------
; PROCESS ACCESS RIGHTS
; ------------------------------------------------------------------------------
PROCESS_QUERY_INFORMATION   EQU 0400h
PROCESS_DUP_HANDLE          EQU 0040h
PROCESS_QUERY_DUP           EQU 0440h

; ------------------------------------------------------------------------------
; TOOLHELP32
; ------------------------------------------------------------------------------
TH32CS_SNAPPROCESS          EQU 00000002h
PROCESSENTRY32W_SIZE        EQU 568

; ------------------------------------------------------------------------------
; SERVICE CONTROL MANAGER
; ------------------------------------------------------------------------------
SERVICE_STATUS_PROCESS_SIZE EQU 36
SERVICE_RUNNING             EQU 4
SERVICE_STOPPED             EQU 1
SC_MANAGER_CONNECT          EQU 0001h
SERVICE_QUERY_STATUS        EQU 0004h
SERVICE_START               EQU 0010h
SERVICE_QS                  EQU 0014h
SC_STATUS_PROCESS_INFO      EQU 0

; ------------------------------------------------------------------------------
; WINDOW STYLES
; ------------------------------------------------------------------------------
WS_CAPTION                  EQU 00C00000h
WS_SYSMENU                  EQU 00080000h
WS_MINIMIZEBOX              EQU 00020000h
WS_CHILD                    EQU 40000000h
WS_VISIBLE                  EQU 10000000h
WS_TABSTOP                  EQU 00010000h
WS_BORDER                   EQU 00800000h

; fixed non-resizable overlapped window: CAPTION|SYSMENU|MINIMIZEBOX|VISIBLE
STY_MAINWIN                 EQU 10CA0000h
; child visible
WS_CHILD_VISIBLE            EQU 50000000h
; button
STY_BUTTON                  EQU 50010000h
STY_BUTTON_DEF              EQU 50010001h
; static
STY_STATIC                  EQU 50000000h

; ------------------------------------------------------------------------------
; WINDOW CLASS STYLES
; ------------------------------------------------------------------------------
CS_HREDRAW                  EQU 0002h
CS_VREDRAW                  EQU 0001h

; ------------------------------------------------------------------------------
; EXTENDED WINDOW STYLES
; ------------------------------------------------------------------------------
WS_EX_CLIENTEDGE            EQU 00000200h

; ------------------------------------------------------------------------------
; DWM - dark mode / Mica
; ------------------------------------------------------------------------------
DWMWA_USE_IMMERSIVE_DARK_MODE     EQU 20
DWMWA_USE_IMMERSIVE_DARK_MODE_OLD EQU 19
DWMWA_SYSTEMBACKDROP_TYPE         EQU 38
DWMSBT_MAINWINDOW                 EQU 2

; ------------------------------------------------------------------------------
; WINDOW MESSAGES
; ------------------------------------------------------------------------------
WM_CREATE                   EQU 0001h
WM_DESTROY                  EQU 0002h
WM_CLOSE                    EQU 0010h
WM_COMMAND                  EQU 0111h
WM_SETFONT                  EQU 0030h
WM_THEMECHANGED             EQU 031Ah
WM_CTLCOLORSTATIC           EQU 0138h

; ------------------------------------------------------------------------------
; CONTROL IDs
; ------------------------------------------------------------------------------
IDC_BTN_PATCH               EQU 101
IDC_STATIC_STATUS           EQU 102
IDC_BTN_UNPATCH             EQU 103
IDC_STATIC_VERSION          EQU 104
IDC_STATIC_AUTHOR           EQU 105

; ------------------------------------------------------------------------------
; MESSAGE BOX
; ------------------------------------------------------------------------------
MB_OK                       EQU 00000000h
MB_ICONERROR                EQU 00000010h
MB_ICONINFORMATION          EQU 00000040h

; ------------------------------------------------------------------------------
; MISC
; ------------------------------------------------------------------------------
SW_SHOWNORMAL               EQU 1
IDC_ARROW_ATOM              EQU 32512
WHITE_BRUSH                 EQU 0
INVALID_HANDLE_VALUE        EQU -1

; WNDCLASSEXW struct size
WNDCLASSEXW_SIZE            EQU 80

; GDI colors (COLORREF = 0x00BBGGRR)
COLORREF_GREEN              EQU 00008000h   ; RGB(0,128,0)
COLORREF_RED                EQU 000000FFh   ; RGB(255,0,0)
COLORREF_ORANGE             EQU 0000A5FFh   ; RGB(255,165,0) — transition state
COLOR_WINDOW_VAL            EQU 5

; MoveFileExW
MOVEFILE_DELAY_UNTIL_REBOOT EQU 4
MOVEFILE_REPLACE_EXISTING   EQU 1

; Registry
KEY_READ                    EQU 20019h
HKLM_VALUE                  EQU 80000002h   ; HKEY_LOCAL_MACHINE

; ShellExecuteExW
SEE_MASK_FLAG_NO_UI         EQU 0400h
SEE_MASK_NOCLOSEPROCESS     EQU 0040h       ; return hProcess in struct for waiting
SEE_MASK_NO_UI_NOCLOSE      EQU 0440h       ; combined
SHELLEXECUTEINFOW_SIZE      EQU 112         ; sizeof SHELLEXECUTEINFOW x64
SHELLEXECUTEINFOW_HPROCESS  EQU 68h         ; struct offset of hProcess field (x64)
SW_HIDE                     EQU 0

; Win32 error codes for retry loops
ERROR_FILE_NOT_FOUND        EQU 2
ERROR_ACCESS_DENIED         EQU 5
ERROR_SHARING_VIOLATION     EQU 32
ERROR_LOCK_VIOLATION        EQU 33

; WaitForInputIdle timeout
WAIT_MS_10000               EQU 10000

; ------------------------------------------------------------------------------
; ICON / RESOURCE
; ------------------------------------------------------------------------------
IDI_ICON1                   EQU 101
IDI_RES_CAB                 EQU 102
ICON_SIZE                   EQU 1662        ; ICO header size; CAB starts after
RT_RCDATA                   EQU 10

; ------------------------------------------------------------------------------
; FILE / REGISTRY
; ------------------------------------------------------------------------------
GENERIC_WRITE               EQU 40000000h
CREATE_ALWAYS               EQU 2
FILE_ATTRIBUTE_NORMAL       EQU 80h
KEY_SET_VALUE               EQU 2
KEY_WOW64_64KEY             EQU 100h
KEY_WRITE_64                EQU 20106h      ; KEY_WRITE (20006h) | KEY_WOW64_64KEY (100h) — match C++
REG_EXPAND_SZ               EQU 2
HKCR_VALUE                  EQU 80000000h   ; HKEY_CLASSES_ROOT

; ------------------------------------------------------------------------------
; PROCESS
; ------------------------------------------------------------------------------
PROCESS_TERMINATE           EQU 00000001h
SYNCHRONIZE_FLAG            EQU 00100000h
PROCESS_TERM_SYNC           EQU 00100001h
WAIT_MS_2000                EQU 2000

; ------------------------------------------------------------------------------
; FDI
; ------------------------------------------------------------------------------
FDI_DLL_BUFSIZE             EQU 400000h     ; 4 MB output buffer
SEEK_SET_VAL                EQU 0
SEEK_CUR_VAL                EQU 1
SEEK_END_VAL                EQU 2
fdintCOPY_FILE              EQU 2
fdintCLOSE_FILE_INFO        EQU 3
cpuUNKNOWN                  EQU 0
ERF_SIZE                    EQU 12

; ------------------------------------------------------------------------------
; CONSOLE / PROCESS
; ------------------------------------------------------------------------------
ATTACH_PARENT_PROCESS   equ 0FFFFFFFFh  ; -1 as DWORD
STD_INPUT_HANDLE        equ 0FFFFFFF6h  ; -10
STD_OUTPUT_HANDLE       equ 0FFFFFFF5h  ; -11
FILE_TYPE_CHAR          equ 2

; MSG struct (48 bytes)
MSG STRUCT
    hwnd    QWORD ?
    message DWORD ?
    pad1    DWORD ?
    wParam  QWORD ?
    lParam  QWORD ?
    time    DWORD ?
    pt_x    DWORD ?
    pt_y    DWORD ?
    pad2    DWORD ?
MSG ENDS