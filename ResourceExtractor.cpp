#include "ResourceExtractor.h"
#include <windows.h>

std::vector<BYTE> ResourceExtractor::ExtractDllFromResource(HINSTANCE hInstance, int resourceId) {
    // 1. Załaduj zasób
    HRSRC hRes = FindResource(hInstance, MAKEINTRESOURCE(resourceId), RT_RCDATA);
    if (!hRes) return {};
    
    HGLOBAL hResData = LoadResource(hInstance, hRes);
    if (!hResData) return {};
    
    DWORD resSize = SizeofResource(hInstance, hRes);
    const BYTE* resData = static_cast<const BYTE*>(LockResource(hResData));
    if (!resData || resSize <= ICON_SIZE) return {};
    
    // 2. Wyciągnij dane CAB (po ikonie)
    size_t cabSize = resSize - ICON_SIZE;
    std::vector<BYTE> cabData(resData + ICON_SIZE, resData + resSize);
    
    return cabData; // Zwróć surowe dane CAB
}