#include "ResourceExtractor.h"

std::vector<BYTE> ResourceExtractor::ExtractDllFromResource(HINSTANCE hInstance, int resourceId) {
    HRSRC hRes = FindResource(hInstance, MAKEINTRESOURCE(resourceId), RT_RCDATA);
    if (!hRes) return {};
    
    HGLOBAL hResData = LoadResource(hInstance, hRes);
    if (!hResData) return {};
    
    DWORD resSize = SizeofResource(hInstance, hRes);
    const BYTE* resData = static_cast<const BYTE*>(LockResource(hResData));
    if (!resData || resSize <= ICON_SIZE) return {};
    
    size_t cabSize = resSize - ICON_SIZE;
    std::vector<BYTE> cabData(resData + ICON_SIZE, resData + resSize);
    
    return cabData; // Pure CAB data
}