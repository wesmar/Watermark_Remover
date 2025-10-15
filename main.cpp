#include <windows.h>
#include <string>
#include <vector>
#include <tlhelp32.h>
#include <fdi.h>
#include "ResourceExtractor.h"
#include "TrustedInstallerExecutor.h"

#pragma comment(lib, "cabinet.lib")

// Global variables
HINSTANCE hInst;
HWND hPatchButton;
HWND hUnpatchButton;
HWND hStatusText;
HWND hVersionText;
HWND hAuthorText;
const int BUTTON_WIDTH = 140;
const int BUTTON_HEIGHT = 35;

// =============================================================================
// FDI Callbacks for memory-based CAB extraction
// =============================================================================

struct MemoryReadContext {
    const BYTE* data;
    size_t size;
    size_t offset;
};

static MemoryReadContext* g_cabContext = nullptr;
static std::vector<BYTE>* g_currentFileData = nullptr;

static void* DIAMONDAPI fdi_alloc(ULONG cb) {
    return malloc(cb);
}

static void DIAMONDAPI fdi_free(void* pv) {
    free(pv);
}

static INT_PTR DIAMONDAPI fdi_open(char* pszFile, int oflag, int pmode) {
    return g_cabContext ? (INT_PTR)g_cabContext : -1;
}

static UINT DIAMONDAPI fdi_read(INT_PTR hf, void* pv, UINT cb) {
    MemoryReadContext* ctx = (MemoryReadContext*)hf;
    if (!ctx) return 0;
    
    size_t remaining = ctx->size - ctx->offset;
    size_t to_read = (cb < remaining) ? cb : remaining;
    
    if (to_read > 0) {
        memcpy(pv, ctx->data + ctx->offset, to_read);
        ctx->offset += to_read;
    }
    
    return static_cast<UINT>(to_read);
}

static UINT DIAMONDAPI fdi_write(INT_PTR hf, void* pv, UINT cb) {
    if (g_currentFileData && cb > 0) {
        BYTE* data = static_cast<BYTE*>(pv);
        g_currentFileData->insert(g_currentFileData->end(), data, data + cb);
    }
    return cb;
}

static int DIAMONDAPI fdi_close(INT_PTR hf) {
    g_currentFileData = nullptr;
    return 0;
}

static LONG DIAMONDAPI fdi_seek(INT_PTR hf, LONG dist, int seektype) {
    MemoryReadContext* ctx = (MemoryReadContext*)hf;
    if (!ctx) return -1;
    
    switch (seektype) {
        case SEEK_SET: ctx->offset = dist; break;
        case SEEK_CUR: ctx->offset += dist; break;
        case SEEK_END: ctx->offset = ctx->size + dist; break;
    }
    
    return static_cast<LONG>(ctx->offset);
}

static INT_PTR DIAMONDAPI fdi_notify(FDINOTIFICATIONTYPE fdint, PFDINOTIFICATION pfdin) {
    std::vector<BYTE>* extractedData = static_cast<std::vector<BYTE>*>(pfdin->pv);
    
    switch (fdint) {
        case fdintCOPY_FILE:
            g_currentFileData = extractedData;
            return (INT_PTR)g_cabContext;
            
        case fdintCLOSE_FILE_INFO:
            g_currentFileData = nullptr;
            return TRUE;
            
        default:
            break;
    }
    return 0;
}

// Decompress CAB from memory and extract first file
std::vector<BYTE> DecompressCABFromMemory(const BYTE* cabData, size_t cabSize) {
    std::vector<BYTE> extractedFile;
    
    MemoryReadContext ctx = { cabData, cabSize, 0 };
    g_cabContext = &ctx;
    
    ERF erf{};
    HFDI hfdi = FDICreate(fdi_alloc, fdi_free, fdi_open, fdi_read, 
                          fdi_write, fdi_close, fdi_seek, cpuUNKNOWN, &erf);
    
    if (!hfdi) {
        g_cabContext = nullptr;
        return extractedFile;
    }
    
    char cabName[] = "memory.cab";
    char cabPath[] = "";
    
    FDICopy(hfdi, cabName, cabPath, 0, fdi_notify, nullptr, &extractedFile);
    
    FDIDestroy(hfdi);
    g_cabContext = nullptr;
    
    return extractedFile;
}

// =============================================================================
// Utility functions
// =============================================================================

std::wstring GetSystem32Path() {
    wchar_t systemDir[MAX_PATH];
    if (GetSystemDirectoryW(systemDir, MAX_PATH) == 0) {
        return L"";
    }
    return std::wstring(systemDir);
}

std::wstring GetWindowsVersion() {
    HKEY hKey;
    DWORD dwType, dwSize;
    wchar_t version[256] = {0};
    wchar_t build[256] = {0};
    wchar_t displayVersion[256] = {0};
    std::wstring result;

    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion", 
                      0, KEY_READ, &hKey) == ERROR_SUCCESS) {
        
        dwSize = sizeof(displayVersion);
        if (RegQueryValueExW(hKey, L"DisplayVersion", NULL, &dwType, (LPBYTE)displayVersion, &dwSize) == ERROR_SUCCESS) {
            result = displayVersion;
        } else {
            dwSize = sizeof(version);
            if (RegQueryValueExW(hKey, L"ReleaseId", NULL, &dwType, (LPBYTE)version, &dwSize) == ERROR_SUCCESS) {
                result = version;
            }
        }

        dwSize = sizeof(build);
        if (RegQueryValueExW(hKey, L"CurrentBuildNumber", NULL, &dwType, (LPBYTE)build, &dwSize) == ERROR_SUCCESS) {
            result += L" (OS Build " + std::wstring(build) + L")";
        }

        RegCloseKey(hKey);
    }

    return result;
}

std::wstring ReadRegistryValue(HKEY hKey, const std::wstring& subKey, const std::wstring& valueName) {
    HKEY hOpenKey;
    if (RegOpenKeyExW(hKey, subKey.c_str(), 0, KEY_READ, &hOpenKey) == ERROR_SUCCESS) {
        wchar_t value[1024];
        DWORD dataSize = sizeof(value);
        DWORD type;
        if (RegQueryValueExW(hOpenKey, valueName.empty() ? nullptr : valueName.c_str(), NULL, &type, (LPBYTE)value, &dataSize) == ERROR_SUCCESS) {
            RegCloseKey(hOpenKey);
            if (type == REG_SZ || type == REG_EXPAND_SZ) {
                return std::wstring(value);
            }
        }
        RegCloseKey(hOpenKey);
    }
    return L"";
}

std::wstring GetPatchStatus() {
    std::wstring currentValue = ReadRegistryValue(HKEY_CLASSES_ROOT, 
        L"CLSID\\{ab0b37ec-56f6-4a0e-a8fd-7a8bf7c2da96}\\InProcServer32", L"");
    
    if (currentValue == L"%SystemRoot%\\system32\\ExpIorerFrame.dll") {
        return L"WATERMARK REMOVED \u2713";
    } else if (currentValue == L"%SystemRoot%\\system32\\ExplorerFrame.dll") {
        return L"WATERMARK ACTIVE \u2713";
    }
    return L"UNKNOWN STATE";
}

bool IsPatchApplied() {
    return GetPatchStatus() == L"WATERMARK REMOVED \u2713";
}

bool IsOriginalState() {
    return GetPatchStatus() == L"WATERMARK ACTIVE \u2713";
}

// Restart Explorer process with improved logic
bool RestartExplorer() {
    // Find all explorer.exe processes
    std::vector<DWORD> explorerPids;
    HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnapshot != INVALID_HANDLE_VALUE) {
        PROCESSENTRY32W pe;
        pe.dwSize = sizeof(pe);
        
        if (Process32FirstW(hSnapshot, &pe)) {
            do {
                if (wcscmp(pe.szExeFile, L"explorer.exe") == 0) {
                    explorerPids.push_back(pe.th32ProcessID);
                }
            } while (Process32NextW(hSnapshot, &pe));
        }
        CloseHandle(hSnapshot);
    }
    
    // Terminate all Explorer instances
    std::vector<HANDLE> processHandles;
    for (DWORD pid : explorerPids) {
        HANDLE hProcess = OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE, FALSE, pid);
        if (hProcess) {
            TerminateProcess(hProcess, 0);
            processHandles.push_back(hProcess);
        }
    }
    
    // Wait for termination
    if (!processHandles.empty()) {
        WaitForMultipleObjects(
            static_cast<DWORD>(processHandles.size()),
            processHandles.data(),
            TRUE,
            500
        );
        
        for (HANDLE h : processHandles) {
            CloseHandle(h);
        }
    }
    
    // Start new Explorer instance
    SHELLEXECUTEINFOW sei = { sizeof(sei) };
    sei.fMask = SEE_MASK_FLAG_NO_UI;
    sei.lpFile = L"explorer.exe";
    sei.lpParameters = L"/e,";  // Prevents opening folder window
    sei.nShow = SW_HIDE;        // Hide the window
    
    if (!ShellExecuteExW(&sei)) {
        return false;
    }
    
    Sleep(1000);  // Give Explorer time to start
    return true;
}

void UpdateStatusText(const std::wstring& text, COLORREF color) {
    SetWindowTextW(hStatusText, text.c_str());
    InvalidateRect(hStatusText, NULL, TRUE);
    UpdateWindow(hStatusText);
}

// =============================================================================
// Main patch operations - Improved with better error handling
// =============================================================================

void PerformPatch(HWND hwnd) {
    if (!TrustedInstallerExecutor::IsCurrentProcessElevated()) {
        UpdateStatusText(L"ERROR: RUN AS ADMIN!", RGB(255, 0, 0));
        return;
    }

    if (IsPatchApplied()) {
        UpdateStatusText(GetPatchStatus(), RGB(0, 128, 0));
        return;
    }

    UpdateStatusText(L"EXTRACTING RESOURCES...", RGB(255, 165, 0));
    std::vector<BYTE> encryptedCab = ResourceExtractor::ExtractDllFromResource(GetModuleHandleW(nullptr), 102);
    if (encryptedCab.empty()) {
        UpdateStatusText(L"ERROR: EXTRACTION FAILED!", RGB(255, 0, 0));
        return;
    }

    UpdateStatusText(L"DECOMPRESSING...", RGB(255, 165, 0));
    std::vector<BYTE> dllData = DecompressCABFromMemory(encryptedCab.data(), encryptedCab.size());
    if (dllData.empty()) {
        UpdateStatusText(L"ERROR: DECOMPRESSION FAILED!", RGB(255, 0, 0));
        return;
    }

    std::wstring system32Path = GetSystem32Path();
    if (system32Path.empty()) {
        UpdateStatusText(L"ERROR: SYSTEM32 NOT FOUND!", RGB(255, 0, 0));
        return;
    }

    std::wstring dllTargetPath = system32Path + L"\\ExpIorerFrame.dll";

    UpdateStatusText(L"WRITING FILE...", RGB(255, 165, 0));
    bool fileSuccess = TrustedInstallerExecutor::WriteFileAsTrustedInstaller(dllTargetPath, dllData);

    if (!fileSuccess) {
        UpdateStatusText(L"ERROR: FILE WRITE FAILED!", RGB(255, 0, 0));
        return;
    }

    UpdateStatusText(L"UPDATING REGISTRY...", RGB(255, 165, 0));
    bool registrySuccess = TrustedInstallerExecutor::WriteRegistryValueAsTrustedInstaller(
        HKEY_CLASSES_ROOT,
        L"CLSID\\{ab0b37ec-56f6-4a0e-a8fd-7a8bf7c2da96}\\InProcServer32",
        L"",
        L"%SystemRoot%\\system32\\ExpIorerFrame.dll"
    );

    if (registrySuccess) {
        UpdateStatusText(L"RESTARTING EXPLORER...", RGB(255, 165, 0));
        if (RestartExplorer()) {
            UpdateStatusText(GetPatchStatus(), RGB(0, 128, 0));
        } else {
            UpdateStatusText(L"RESTART EXPLORER MANUALLY!", RGB(255, 165, 0));
        }
    } else {
        UpdateStatusText(L"ERROR: REGISTRY FAILED!", RGB(255, 0, 0));
    }
}

void PerformUnpatch(HWND hwnd) {
    if (!TrustedInstallerExecutor::IsCurrentProcessElevated()) {
        UpdateStatusText(L"ERROR: RUN AS ADMIN!", RGB(255, 0, 0));
        return;
    }

    if (IsOriginalState()) {
        UpdateStatusText(GetPatchStatus(), RGB(255, 0, 0));
        return;
    }

    UpdateStatusText(L"RESTORING REGISTRY...", RGB(255, 165, 0));
    bool registrySuccess = TrustedInstallerExecutor::WriteRegistryValueAsTrustedInstaller(
        HKEY_CLASSES_ROOT,
        L"CLSID\\{ab0b37ec-56f6-4a0e-a8fd-7a8bf7c2da96}\\InProcServer32",
        L"",
        L"%SystemRoot%\\system32\\ExplorerFrame.dll"
    );

    if (!registrySuccess) {
        UpdateStatusText(L"ERROR: REGISTRY FAILED!", RGB(255, 0, 0));
        return;
    }

    UpdateStatusText(L"RESTARTING EXPLORER...", RGB(255, 165, 0));
    
    if (!RestartExplorer()) {
        UpdateStatusText(L"RESTART EXPLORER MANUALLY!", RGB(255, 165, 0));
        return;
    }

    Sleep(1000);
    
    std::wstring system32Path = GetSystem32Path();
    if (!system32Path.empty()) {
        std::wstring dllPath = system32Path + L"\\ExpIorerFrame.dll";
        
        UpdateStatusText(L"REMOVING FILE...", RGB(255, 165, 0));
        if (!TrustedInstallerExecutor::DeleteFileAsTrustedInstaller(dllPath)) {
            UpdateStatusText(L"FILE REMOVED ON RESTART", RGB(255, 165, 0));
        } else {
            UpdateStatusText(GetPatchStatus(), RGB(255, 0, 0));
        }
    } else {
        UpdateStatusText(GetPatchStatus(), RGB(255, 0, 0));
    }
}

// =============================================================================
// Window procedures
// =============================================================================

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_CREATE: {
            int windowWidth = 380;
            int windowHeight = 220;
            
            hVersionText = CreateWindowW(
                L"STATIC", L"",
                WS_CHILD | WS_VISIBLE | SS_CENTER,
                0, 25, windowWidth, 40,
                hwnd, NULL, hInst, NULL
            );
            
            HFONT hVersionFont = CreateFontW(14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                DEFAULT_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
            SendMessage(hVersionText, WM_SETFONT, (WPARAM)hVersionFont, TRUE);
            
            hAuthorText = CreateWindowW(
                L"STATIC", L"",
                WS_CHILD | WS_VISIBLE | SS_CENTER,
                0, 65, windowWidth, 30,
                hwnd, NULL, hInst, NULL
            );
            
            HFONT hAuthorFont = CreateFontW(14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                DEFAULT_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
            SendMessage(hAuthorText, WM_SETFONT, (WPARAM)hAuthorFont, TRUE);
            
            int buttonSpacing = 10;
            int totalButtonsWidth = (BUTTON_WIDTH * 2) + buttonSpacing;
            int startX = (windowWidth - totalButtonsWidth) / 2;
            int buttonY = 100;
            
            hPatchButton = CreateWindowW(
                L"BUTTON", L"APPLY PATCH",
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                startX, buttonY, BUTTON_WIDTH, BUTTON_HEIGHT,
                hwnd, (HMENU)1, hInst, NULL
            );
            
            hUnpatchButton = CreateWindowW(
                L"BUTTON", L"RESTORE", 
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                startX + BUTTON_WIDTH + buttonSpacing, buttonY, BUTTON_WIDTH, BUTTON_HEIGHT,
                hwnd, (HMENU)2, hInst, NULL
            );
            
            HFONT hFont = CreateFontW(14, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                DEFAULT_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
            SendMessage(hPatchButton, WM_SETFONT, (WPARAM)hFont, TRUE);
            SendMessage(hUnpatchButton, WM_SETFONT, (WPARAM)hFont, TRUE);
            
            hStatusText = CreateWindowW(
                L"STATIC", L"",
                WS_CHILD | WS_VISIBLE | SS_CENTER,
                startX, 150, totalButtonsWidth, 20,
                hwnd, NULL, hInst, NULL
            );
            
            HFONT hStatusFont = CreateFontW(24, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                DEFAULT_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
            SendMessage(hStatusText, WM_SETFONT, (WPARAM)hStatusFont, TRUE);
            
            std::wstring winVersion = GetWindowsVersion();
            if (!winVersion.empty()) {
                SetWindowTextW(hVersionText, (L"Microsoft Windows\nVersion " + winVersion).c_str());
            }
            
            SetWindowTextW(hAuthorText, L"Author: Marek Wesolowski (WESMAR)\nhttps://kvc.pl | marek@wesolowski.eu.org");
            
            std::wstring status = GetPatchStatus();
            UpdateStatusText(status, (status == L"WATERMARK REMOVED \u2713") ? RGB(0, 128, 0) : RGB(255, 0, 0));
            
            break;
        }
        
        case WM_COMMAND: {
            if (LOWORD(wParam) == 1) {
                PerformPatch(hwnd);
            } else if (LOWORD(wParam) == 2) {
                PerformUnpatch(hwnd);
            }
            break;
        }
        
        case WM_CTLCOLORSTATIC: {
            HDC hdcStatic = (HDC)wParam;
            HWND hwndStatic = (HWND)lParam;
            
            if (hwndStatic == hVersionText) {
                SetTextColor(hdcStatic, RGB(0, 128, 0));
            }
            else if (hwndStatic == hStatusText) {
                std::wstring status = GetPatchStatus();
                if (status == L"WATERMARK REMOVED \u2713") {
                    SetTextColor(hdcStatic, RGB(0, 128, 0));
                } else if (status == L"RESTARTING EXPLORER...") {
                    SetTextColor(hdcStatic, RGB(255, 165, 0));
                } else {
                    SetTextColor(hdcStatic, RGB(255, 0, 0));
                }
            }
            SetBkColor(hdcStatic, GetSysColor(COLOR_WINDOW));
            return (LRESULT)GetSysColorBrush(COLOR_WINDOW);
        }
        
        case WM_DESTROY:
            PostQuitMessage(0);
            break;
            
        default:
            return DefWindowProc(hwnd, msg, wParam, lParam);
    }
    return 0;
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, 
                   LPSTR lpCmdLine, int nCmdShow) {
    hInst = hInstance;
    
    WNDCLASSW wc = { 0 };
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = L"WatermarkRemover";
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    
    if (!RegisterClassW(&wc)) {
        MessageBoxW(NULL, L"Window class registration failed!", L"Error", MB_ICONERROR);
        return 0;
    }
    
    int windowWidth = 380;
    int windowHeight = 220;
    int screenWidth = GetSystemMetrics(SM_CXSCREEN);
    int screenHeight = GetSystemMetrics(SM_CYSCREEN);
    
    HWND hwnd = CreateWindowW(
        L"WatermarkRemover",
        L"Watermark Remover",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        (screenWidth - windowWidth) / 2, (screenHeight - windowHeight) / 2,
        windowWidth, windowHeight,
        NULL, NULL, hInstance, NULL
    );
    
    if (!hwnd) {
        MessageBoxW(NULL, L"Window creation failed!", L"Error", MB_ICONERROR);
        return 0;
    }
    
    ShowWindow(hwnd, nCmdShow);
    UpdateWindow(hwnd);
    
    MSG msg = { 0 };
    while (GetMessage(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }
    
    return (int)msg.wParam;
}