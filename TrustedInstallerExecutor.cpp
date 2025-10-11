#include "TrustedInstallerExecutor.h"
#include <iostream>
#include <tlhelp32.h>

#pragma comment(lib, "advapi32.lib")

TrustedInstallerExecutor::TrustedInstallerExecutor() {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    comInitialized_ = SUCCEEDED(hr);
}

TrustedInstallerExecutor::~TrustedInstallerExecutor() {
    if (comInitialized_) {
        CoUninitialize();
    }
}

// TokenHandle implementation
TrustedInstallerExecutor::TokenHandle& 
TrustedInstallerExecutor::TokenHandle::operator=(TokenHandle&& other) noexcept {
    if (this != &other) {
        reset(other.release());
    }
    return *this;
}

void TrustedInstallerExecutor::TokenHandle::reset(HANDLE newHandle) noexcept {
    if (handle_ && handle_ != INVALID_HANDLE_VALUE) {
        CloseHandle(handle_);
    }
    handle_ = newHandle;
}

HANDLE TrustedInstallerExecutor::TokenHandle::release() noexcept {
    HANDLE result = handle_;
    handle_ = nullptr;
    return result;
}

// Core TI functionality
bool TrustedInstallerExecutor::EnablePrivilege(std::wstring_view privilegeName) noexcept {
    HANDLE processToken;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &processToken)) {
        return false;
    }

    TOKEN_PRIVILEGES tp{};
    LUID luid;

    if (!LookupPrivilegeValueW(nullptr, std::wstring(privilegeName).c_str(), &luid)) {
        CloseHandle(processToken);
        return false;
    }

    tp.PrivilegeCount = 1;
    tp.Privileges[0].Luid = luid;
    tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;

    bool result = AdjustTokenPrivileges(processToken, FALSE, &tp, sizeof(tp), nullptr, nullptr);
    CloseHandle(processToken);
    
    return result && GetLastError() == ERROR_SUCCESS;
}

std::optional<DWORD> TrustedInstallerExecutor::GetProcessIdByName(std::wstring_view processName) noexcept {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return std::nullopt;

    PROCESSENTRY32W pe{};
    pe.dwSize = sizeof(pe);

    if (Process32FirstW(snapshot, &pe)) {
        do {
            if (std::wstring_view(pe.szExeFile) == processName) {
                CloseHandle(snapshot);
                return pe.th32ProcessID;
            }
        } while (Process32NextW(snapshot, &pe));
    }

    CloseHandle(snapshot);
    return std::nullopt;
}

TrustedInstallerExecutor::TokenHandle TrustedInstallerExecutor::GetSystemToken() noexcept {
    auto winlogonPid = GetProcessIdByName(L"winlogon.exe");
    if (!winlogonPid) return TokenHandle{};

    HANDLE process = OpenProcess(PROCESS_QUERY_INFORMATION, FALSE, *winlogonPid);
    if (!process) return TokenHandle{};

    HANDLE token;
    if (!OpenProcessToken(process, TOKEN_DUPLICATE | TOKEN_QUERY, &token)) {
        CloseHandle(process);
        return TokenHandle{};
    }

    HANDLE duplicatedToken;
    if (!DuplicateTokenEx(token, MAXIMUM_ALLOWED, nullptr, SecurityImpersonation,
                         TokenImpersonation, &duplicatedToken)) {
        CloseHandle(token);
        CloseHandle(process);
        return TokenHandle{};
    }

    CloseHandle(token);
    CloseHandle(process);
    return TokenHandle(duplicatedToken);
}

std::optional<DWORD> TrustedInstallerExecutor::StartTrustedInstallerService() noexcept {
    SC_HANDLE scManager = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
    if (!scManager) return std::nullopt;

    SC_HANDLE service = OpenServiceW(scManager, L"TrustedInstaller", SERVICE_QUERY_STATUS | SERVICE_START);
    if (!service) {
        CloseServiceHandle(scManager);
        return std::nullopt;
    }

    SERVICE_STATUS_PROCESS status{};
    DWORD bytesNeeded = 0;
    
    if (QueryServiceStatusEx(service, SC_STATUS_PROCESS_INFO, reinterpret_cast<BYTE*>(&status), 
                           sizeof(status), &bytesNeeded)) {
        if (status.dwCurrentState == SERVICE_RUNNING) {
            CloseServiceHandle(service);
            CloseServiceHandle(scManager);
            return status.dwProcessId;
        }
    }

    if (StartServiceW(service, 0, nullptr)) {
        Sleep(1000);
        if (QueryServiceStatusEx(service, SC_STATUS_PROCESS_INFO, reinterpret_cast<BYTE*>(&status),
                               sizeof(status), &bytesNeeded) && status.dwCurrentState == SERVICE_RUNNING) {
            CloseServiceHandle(service);
            CloseServiceHandle(scManager);
            return status.dwProcessId;
        }
    }

    CloseServiceHandle(service);
    CloseServiceHandle(scManager);
    return std::nullopt;
}

TrustedInstallerExecutor::TokenHandle TrustedInstallerExecutor::GetTrustedInstallerToken(DWORD trustedInstallerPid) noexcept {
    HANDLE process = OpenProcess(PROCESS_QUERY_INFORMATION, FALSE, trustedInstallerPid);
    if (!process) return TokenHandle{};

    HANDLE token;
    if (!OpenProcessToken(process, TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_ADJUST_PRIVILEGES, &token)) {
        CloseHandle(process);
        return TokenHandle{};
    }

    HANDLE duplicatedToken;
    if (!DuplicateTokenEx(token, MAXIMUM_ALLOWED, nullptr, SecurityImpersonation,
                         TokenImpersonation, &duplicatedToken)) {
        CloseHandle(token);
        CloseHandle(process);
        return TokenHandle{};
    }

    CloseHandle(token);
    CloseHandle(process);
    return TokenHandle(duplicatedToken);
}

bool TrustedInstallerExecutor::EnableAllPrivileges(const TokenHandle& token) noexcept {
    bool allSucceeded = true;

    for (size_t i = 0; i < REQUIRED_PRIVILEGES_COUNT; ++i) {
        const wchar_t* privilege = REQUIRED_PRIVILEGES[i];
        
        TOKEN_PRIVILEGES tp{};
        LUID luid;

        if (LookupPrivilegeValueW(nullptr, privilege, &luid)) {
            tp.PrivilegeCount = 1;
            tp.Privileges[0].Luid = luid;
            tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
            
            if (!AdjustTokenPrivileges(token.get(), FALSE, &tp, sizeof(tp), nullptr, nullptr)) {
                allSucceeded = false;
            }
        } else {
            allSucceeded = false;
        }
    }

    return allSucceeded;
}

// File operations
bool TrustedInstallerExecutor::WriteFileAsTrustedInstaller(const std::wstring& path, const std::vector<BYTE>& data) noexcept {
    if (!EnablePrivilege(L"SeDebugPrivilege") || !EnablePrivilege(L"SeImpersonatePrivilege")) {
        return false;
    }

    auto systemToken = GetSystemToken();
    if (!systemToken) return false;

    if (!ImpersonateLoggedOnUser(systemToken.get())) {
        return false;
    }

    auto tiPid = StartTrustedInstallerService();
    if (!tiPid) {
        RevertToSelf();
        return false;
    }

    auto tiToken = GetTrustedInstallerToken(*tiPid);
    RevertToSelf();

    if (!tiToken) return false;

    EnableAllPrivileges(tiToken);
    return WriteFileWithToken(tiToken, path, data);
}

bool TrustedInstallerExecutor::WriteFileWithToken(const TokenHandle& token, const std::wstring& path, const std::vector<BYTE>& data) noexcept {
    bool success = false;

    if (ImpersonateLoggedOnUser(token.get())) {
        HANDLE hFile = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        
        if (hFile != INVALID_HANDLE_VALUE) {
            DWORD bytesWritten = 0;
            if (WriteFile(hFile, data.data(), static_cast<DWORD>(data.size()), &bytesWritten, nullptr)) {
                success = (bytesWritten == data.size());
            }
            CloseHandle(hFile);
        }
        RevertToSelf();
    }

    return success;
}

bool TrustedInstallerExecutor::DeleteFileAsTrustedInstaller(const std::wstring& path) noexcept {
    if (!EnablePrivilege(L"SeDebugPrivilege") || !EnablePrivilege(L"SeImpersonatePrivilege")) {
        return false;
    }

    auto systemToken = GetSystemToken();
    if (!systemToken) return false;

    if (!ImpersonateLoggedOnUser(systemToken.get())) {
        return false;
    }

    auto tiPid = StartTrustedInstallerService();
    if (!tiPid) {
        RevertToSelf();
        return false;
    }

    auto tiToken = GetTrustedInstallerToken(*tiPid);
    RevertToSelf();

    if (!tiToken) return false;

    EnableAllPrivileges(tiToken);
    return DeleteFileWithToken(tiToken, path);
}

bool TrustedInstallerExecutor::DeleteFileWithToken(const TokenHandle& token, const std::wstring& path) noexcept {
    bool success = false;

    if (ImpersonateLoggedOnUser(token.get())) {
        if (DeleteFileW(path.c_str())) {
            success = true;
        } else {
            success = (GetLastError() == ERROR_FILE_NOT_FOUND);
        }
        RevertToSelf();
    }

    return success;
}

// Registry operations
bool TrustedInstallerExecutor::WriteRegistryValueAsTrustedInstaller(HKEY hKeyRoot, const std::wstring& subKey, 
                                                                  const std::wstring& valueName, const std::wstring& value) noexcept {
    if (!EnablePrivilege(L"SeDebugPrivilege") || !EnablePrivilege(L"SeImpersonatePrivilege")) {
        return false;
    }

    auto systemToken = GetSystemToken();
    if (!systemToken) return false;

    if (!ImpersonateLoggedOnUser(systemToken.get())) {
        return false;
    }

    auto tiPid = StartTrustedInstallerService();
    if (!tiPid) {
        RevertToSelf();
        return false;
    }

    auto tiToken = GetTrustedInstallerToken(*tiPid);
    RevertToSelf();

    if (!tiToken) return false;

    EnableAllPrivileges(tiToken);
    return WriteRegistryValueWithToken(tiToken, hKeyRoot, subKey, valueName, value);
}

bool TrustedInstallerExecutor::WriteRegistryValueWithToken(const TokenHandle& token, HKEY hKeyRoot, const std::wstring& subKey,
                                                         const std::wstring& valueName, const std::wstring& value) noexcept {
    bool success = false;

    if (ImpersonateLoggedOnUser(token.get())) {
        HKEY hKey = nullptr;
        
        if (RegOpenKeyExW(hKeyRoot, subKey.c_str(), 0, KEY_WRITE | KEY_WOW64_64KEY, &hKey) == ERROR_SUCCESS) {
            DWORD dataSize = static_cast<DWORD>((value.length() + 1) * sizeof(wchar_t));
            
            if (RegSetValueExW(hKey, valueName.empty() ? nullptr : valueName.c_str(), 0, REG_EXPAND_SZ, 
                             reinterpret_cast<const BYTE*>(value.c_str()), dataSize) == ERROR_SUCCESS) {
                success = true;
            }
            
            RegCloseKey(hKey);
        }
        
        RevertToSelf();
    }

    return success;
}

bool TrustedInstallerExecutor::DeleteRegistryKeyAsTrustedInstaller(HKEY hKeyRoot, const std::wstring& subKey) noexcept {
    if (!EnablePrivilege(L"SeDebugPrivilege") || !EnablePrivilege(L"SeImpersonatePrivilege")) {
        return false;
    }

    auto systemToken = GetSystemToken();
    if (!systemToken) return false;

    if (!ImpersonateLoggedOnUser(systemToken.get())) {
        return false;
    }

    auto tiPid = StartTrustedInstallerService();
    if (!tiPid) {
        RevertToSelf();
        return false;
    }

    auto tiToken = GetTrustedInstallerToken(*tiPid);
    RevertToSelf();

    if (!tiToken) return false;

    EnableAllPrivileges(tiToken);
    return DeleteRegistryKeyWithToken(tiToken, hKeyRoot, subKey);
}

bool TrustedInstallerExecutor::DeleteRegistryKeyWithToken(const TokenHandle& token, HKEY hKeyRoot, const std::wstring& subKey) noexcept {
    bool success = false;

    if (ImpersonateLoggedOnUser(token.get())) {
        if (RegDeleteTreeW(hKeyRoot, subKey.c_str()) == ERROR_SUCCESS) {
            success = true;
        }
        
        RevertToSelf();
    }

    return success;
}

// Utility
bool TrustedInstallerExecutor::IsCurrentProcessElevated() noexcept {
    HANDLE token;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
        return false;
    }

    TOKEN_ELEVATION elevation{};
    DWORD size = sizeof(elevation);
    
    bool result = GetTokenInformation(token, TokenElevation, &elevation, size, &size);
    CloseHandle(token);
    
    return result && elevation.TokenIsElevated;
}