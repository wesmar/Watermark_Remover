#pragma once
#include <Windows.h>
#include <string>
#include <vector>
#include <optional>
#include <array>
#include <string_view>

class TrustedInstallerExecutor {
public:
    TrustedInstallerExecutor();
    ~TrustedInstallerExecutor();

    // File operations
    static bool WriteFileAsTrustedInstaller(const std::wstring& path, const std::vector<BYTE>& data) noexcept;
    static bool DeleteFileAsTrustedInstaller(const std::wstring& path) noexcept;
    
    // Registry operations
    static bool WriteRegistryValueAsTrustedInstaller(HKEY hKeyRoot, const std::wstring& subKey, 
                                                   const std::wstring& valueName, const std::wstring& value) noexcept;
    static bool DeleteRegistryKeyAsTrustedInstaller(HKEY hKeyRoot, const std::wstring& subKey) noexcept;
    
    // Utility
    static bool IsCurrentProcessElevated() noexcept;

private:
    class TokenHandle {
    public:
        TokenHandle() noexcept = default;
        TokenHandle(HANDLE handle) noexcept : handle_(handle) {}
        ~TokenHandle() { reset(); }
        
        TokenHandle(const TokenHandle&) = delete;
        TokenHandle& operator=(const TokenHandle&) = delete;
        
        TokenHandle(TokenHandle&& other) noexcept : handle_(other.handle_) { other.handle_ = nullptr; }
        TokenHandle& operator=(TokenHandle&& other) noexcept;
        
        operator bool() const noexcept { return handle_ && handle_ != INVALID_HANDLE_VALUE; }
        HANDLE get() const noexcept { return handle_; }
        HANDLE* address() noexcept { return &handle_; }
        void reset(HANDLE newHandle = nullptr) noexcept;
        HANDLE release() noexcept;
        
    private:
        HANDLE handle_{nullptr};
    };

    static bool EnablePrivilege(std::wstring_view privilegeName) noexcept;
    static TokenHandle GetSystemToken() noexcept;
    static std::optional<DWORD> GetProcessIdByName(std::wstring_view processName) noexcept;
    static std::optional<DWORD> StartTrustedInstallerService() noexcept;
    static TokenHandle GetTrustedInstallerToken(DWORD trustedInstallerPid) noexcept;
    static bool EnableAllPrivileges(const TokenHandle& token) noexcept;
    
    // File operations with token
    static bool WriteFileWithToken(const TokenHandle& token, const std::wstring& path, const std::vector<BYTE>& data) noexcept;
    static bool DeleteFileWithToken(const TokenHandle& token, const std::wstring& path) noexcept;
    
    // Registry operations with token
    static bool WriteRegistryValueWithToken(const TokenHandle& token, HKEY hKeyRoot, const std::wstring& subKey,
                                          const std::wstring& valueName, const std::wstring& value) noexcept;
    static bool DeleteRegistryKeyWithToken(const TokenHandle& token, HKEY hKeyRoot, const std::wstring& subKey) noexcept;

    bool comInitialized_{false};
    
    static constexpr const wchar_t* REQUIRED_PRIVILEGES[] = {
        L"SeDebugPrivilege",
        L"SeImpersonatePrivilege", 
        L"SeTakeOwnershipPrivilege"
    };
    static constexpr size_t REQUIRED_PRIVILEGES_COUNT = 3;
};