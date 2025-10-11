#pragma once
#include <Windows.h>
#include <vector>

class ResourceExtractor {
public:
    static std::vector<BYTE> ExtractDllFromResource(HINSTANCE hInstance, int resourceId);
    
private:
    static constexpr size_t ICON_SIZE = 3774;
};