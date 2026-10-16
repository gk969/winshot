#pragma once

#ifndef WINVER
#define WINVER 0x0A00
#endif

#include <afxwin.h>
#include <afxext.h>
#include <afxcmn.h>

#include <windowsx.h>
#include <imm.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <dwmapi.h>

#include <gdiplus.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#pragma comment(lib, "gdiplus.lib")
#pragma comment(lib, "msimg32.lib")  // AlphaBlend, for the dim
#pragma comment(lib, "shcore.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "imm32.lib")
#pragma comment(lib, "dwmapi.lib")
