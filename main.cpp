#include <windows.h>
#include <string>
#include <vector>
#include <tlhelp32.h>
#include "ResourceExtractor.h"
#include "TrustedInstallerExecutor.h"

// Global variables
HINSTANCE hInst;
HWND hPatchButton;
HWND hUnpatchButton;
HWND hStatusText;
HWND hVersionText;
HWND hAuthorText;
const int BUTTON_WIDTH = 140;
const int BUTTON_HEIGHT = 35;

// Get System32 path
std::wstring GetSystem32Path() {
    wchar_t systemDir[MAX_PATH];
    if (GetSystemDirectoryW(systemDir, MAX_PATH) == 0) {
        return L"";
    }
    return std::wstring(systemDir);
}

// Get Windows version information
std::wstring GetWindowsVersion() {
    HKEY hKey;
    DWORD dwType, dwSize;
    wchar_t version[256] = {0};
    wchar_t build[256] = {0};
    wchar_t displayVersion[256] = {0};
    std::wstring result;

    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion", 
                      0, KEY_READ, &hKey) == ERROR_SUCCESS) {
        
        // Get display version (like 25H2)
        dwSize = sizeof(displayVersion);
        if (RegQueryValueExW(hKey, L"DisplayVersion", NULL, &dwType, (LPBYTE)displayVersion, &dwSize) == ERROR_SUCCESS) {
            result = displayVersion;
        } else {
            // Fallback to ReleaseId
            dwSize = sizeof(version);
            if (RegQueryValueExW(hKey, L"ReleaseId", NULL, &dwType, (LPBYTE)version, &dwSize) == ERROR_SUCCESS) {
                result = version;
            }
        }

        // Get build number
        dwSize = sizeof(build);
        if (RegQueryValueExW(hKey, L"CurrentBuildNumber", NULL, &dwType, (LPBYTE)build, &dwSize) == ERROR_SUCCESS) {
            result += L" (OS Build " + std::wstring(build) + L")";
        }

        RegCloseKey(hKey);
    }

    return result;
}

// Read registry value
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

// Check patch status
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

// Check if patch is already applied
bool IsPatchApplied() {
    return GetPatchStatus() == L"WATERMARK REMOVED \u2713";
}

// Check if original state is restored
bool IsOriginalState() {
    return GetPatchStatus() == L"WATERMARK ACTIVE \u2713";
}

// Restart Explorer
void RestartExplorer() {
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
    
    std::vector<HANDLE> processHandles;
    for (DWORD pid : explorerPids) {
        HANDLE hProcess = OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE, FALSE, pid);
        if (hProcess) {
            TerminateProcess(hProcess, 0);
            processHandles.push_back(hProcess);
        }
    }
    
    if (!processHandles.empty()) {
        WaitForMultipleObjects(
            static_cast<DWORD>(processHandles.size()),
            processHandles.data(),
            TRUE,
            5000
        );
        
        for (HANDLE h : processHandles) {
            CloseHandle(h);
        }
    }
     
    SHELLEXECUTEINFOW sei = { sizeof(sei) };
    sei.fMask = SEE_MASK_FLAG_NO_UI;
    sei.lpFile = L"explorer.exe";
    sei.lpParameters = L"/e,";
    sei.nShow = SW_HIDE;
    
    ShellExecuteExW(&sei);
}

// Apply patch
void PerformPatch(HWND hwnd) {
    if (!TrustedInstallerExecutor::IsCurrentProcessElevated()) {
        MessageBoxW(hwnd, 
            L"Program must be run as Administrator!",
            L"Permission Error", MB_OK | MB_ICONERROR);
        return;
    }

    if (IsPatchApplied()) {
        MessageBoxW(hwnd, 
            L"The patch is already applied!",
            L"Info", MB_OK | MB_ICONINFORMATION);
        SetWindowTextW(hStatusText, GetPatchStatus().c_str());
        return;
    }

    std::vector<BYTE> dllData = ResourceExtractor::ExtractDllFromResource(GetModuleHandleW(nullptr), 102);
    if (dllData.empty()) {
        MessageBoxW(hwnd, L"Could not extract DLL from resources!", L"Error", MB_OK | MB_ICONERROR);
        return;
    }

    std::wstring system32Path = GetSystem32Path();
    if (system32Path.empty()) {
        MessageBoxW(hwnd, L"Could not find System32 folder!", L"Error", MB_OK | MB_ICONERROR);
        return;
    }

    std::wstring dllTargetPath = system32Path + L"\\ExpIorerFrame.dll";
    std::wstring cabTempPath = system32Path + L"\\ExpIorerFrame.cab";

    bool cabSuccess = TrustedInstallerExecutor::WriteFileAsTrustedInstaller(cabTempPath, dllData);
    bool fileSuccess = false;

    if (cabSuccess) {
        std::wstring expandCmd = std::wstring(L"expand \"") + cabTempPath + L"\" \"" + dllTargetPath + L"\"";
        
        STARTUPINFOW si = { sizeof(si) };
        PROCESS_INFORMATION pi;
        
        if (CreateProcessW(NULL, &expandCmd[0], NULL, NULL, FALSE, 
                          CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
            WaitForSingleObject(pi.hProcess, 5000);
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
            
            DWORD attribs = GetFileAttributesW(dllTargetPath.c_str());
            fileSuccess = (attribs != INVALID_FILE_ATTRIBUTES && !(attribs & FILE_ATTRIBUTE_DIRECTORY));
        }
        
        TrustedInstallerExecutor::DeleteFileAsTrustedInstaller(cabTempPath);
    }

    if (!fileSuccess) {
        MessageBoxW(hwnd, L"Failed to save DLL to System32!", L"Error", MB_OK | MB_ICONERROR);
        return;
    }

    bool registrySuccess = TrustedInstallerExecutor::WriteRegistryValueAsTrustedInstaller(
        HKEY_CLASSES_ROOT,
        L"CLSID\\{ab0b37ec-56f6-4a0e-a8fd-7a8bf7c2da96}\\InProcServer32",
        L"",
        L"%SystemRoot%\\system32\\ExpIorerFrame.dll"
    );

    SetWindowTextW(hStatusText, GetPatchStatus().c_str());

    if (registrySuccess) {
        RestartExplorer();
        MessageBoxW(hwnd, 
            L"Watermark removed successfully!\n\nExplorer has been restarted automatically.",
            L"Success", MB_OK | MB_ICONINFORMATION);
    } else {
        MessageBoxW(hwnd, 
            L"Patch partially applied!\n\nFile was saved but registry update failed.",
            L"Warning", MB_OK | MB_ICONWARNING);
    }
}

// Restore original
void PerformUnpatch(HWND hwnd) {
    if (!TrustedInstallerExecutor::IsCurrentProcessElevated()) {
        MessageBoxW(hwnd, 
            L"Program must be run as Administrator!",
            L"Permission Error", MB_OK | MB_ICONERROR);
        return;
    }

    if (IsOriginalState()) {
        MessageBoxW(hwnd, 
            L"The original state is already restored!",
            L"Info", MB_OK | MB_ICONINFORMATION);
        SetWindowTextW(hStatusText, GetPatchStatus().c_str());
        return;
    }

    bool registrySuccess = TrustedInstallerExecutor::WriteRegistryValueAsTrustedInstaller(
        HKEY_CLASSES_ROOT,
        L"CLSID\\{ab0b37ec-56f6-4a0e-a8fd-7a8bf7c2da96}\\InProcServer32",
        L"",
        L"%SystemRoot%\\system32\\ExplorerFrame.dll"
    );

    SetWindowTextW(hStatusText, GetPatchStatus().c_str());

    if (registrySuccess) {
        std::wstring system32Path = GetSystem32Path();
        if (!system32Path.empty()) {
            std::wstring dllPath = system32Path + L"\\ExpIorerFrame.dll";
            TrustedInstallerExecutor::DeleteFileAsTrustedInstaller(dllPath);
        }

        RestartExplorer();
        MessageBoxW(hwnd, 
            L"Original settings restored successfully!\n\nExplorer has been restarted automatically.",
            L"Success", MB_OK | MB_ICONINFORMATION);
    } else {
        MessageBoxW(hwnd, 
            L"Failed to restore original settings!",
            L"Error", MB_OK | MB_ICONERROR);
    }
}

// Window message handler
LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_CREATE: {
            int windowWidth = 380;
            int windowHeight = 220;
            
            // Windows version text
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
            
            // Author text
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
            
            // Buttons position at bottom
            int buttonSpacing = 10;
            int totalButtonsWidth = (BUTTON_WIDTH * 2) + buttonSpacing;
            int startX = (windowWidth - totalButtonsWidth) / 2;
            int buttonY = 100;
            
            // Patch button
            hPatchButton = CreateWindowW(
                L"BUTTON", L"APPLY PATCH",
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                startX, buttonY, BUTTON_WIDTH, BUTTON_HEIGHT,
                hwnd, (HMENU)1, hInst, NULL
            );
            
            // Unpatch button
            hUnpatchButton = CreateWindowW(
                L"BUTTON", L"RESTORE", 
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                startX + BUTTON_WIDTH + buttonSpacing, buttonY, BUTTON_WIDTH, BUTTON_HEIGHT,
                hwnd, (HMENU)2, hInst, NULL
            );
            
            // Buttons font
            HFONT hFont = CreateFontW(14, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                DEFAULT_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
            SendMessage(hPatchButton, WM_SETFONT, (WPARAM)hFont, TRUE);
            SendMessage(hUnpatchButton, WM_SETFONT, (WPARAM)hFont, TRUE);
            
            // Status text
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
            
            // Set initial texts
            std::wstring winVersion = GetWindowsVersion();
            if (!winVersion.empty()) {
                SetWindowTextW(hVersionText, (L"Microsoft Windows\nVersion " + winVersion).c_str());
            }
            
            SetWindowTextW(hAuthorText, L"Author: Marek Wesolowski (WESMAR)\nhttps://kvc.pl | marek@wesolowski.eu.org");
            SetWindowTextW(hStatusText, GetPatchStatus().c_str());
            
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