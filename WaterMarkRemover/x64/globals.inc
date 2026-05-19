; ==============================================================================
; SignGuiPatcher - Global External Declarations
; Defined in main.asm; referenced by all other modules.
; ==============================================================================

    EXTRN   g_privTable     :QWORD
    EXTRN   g_cachedToken   :QWORD
    EXTRN   g_tokenTime     :DWORD
    EXTRN   g_hInstance     :QWORD
    EXTRN   g_hwndMain      :QWORD
    EXTRN   g_hwndBtn       :QWORD
    EXTRN   g_hwndBtnUnpatch :QWORD
    EXTRN   g_hwndStatus    :QWORD
    EXTRN   g_hwndVersion   :QWORD
    EXTRN   g_hwndAuthor    :QWORD
    EXTRN   g_isPatchApplied :DWORD
    EXTRN   g_cliMode       :DWORD
    EXTRN   g_queryResult   :DWORD
    EXTRN   g_decryptBuf    :WORD
    EXTRN   g_tempBuf       :WORD
    EXTRN   g_statusBuf     :WORD
    EXTRN   privPrefix      :WORD
    EXTRN   privSuffix      :WORD