#pragma once

#include "InGameOverlay/ImGui/imgui.h"

namespace overlay_imgui_compat {

inline void PushFont(ImFont* font)
{
#if IMGUI_VERSION_NUM >= 19200
    ImGui::PushFont(font, font ? font->LegacySize : 0.0f);
#else
    ImGui::PushFont(font);
#endif
}

inline void AddRect(ImDrawList* draw_list, const ImVec2& min, const ImVec2& max,
                    ImU32 color, float rounding, ImDrawFlags flags, float thickness)
{
#if IMGUI_VERSION_NUM >= 19208
    draw_list->AddRect(min, max, color, rounding, thickness, flags);
#else
    draw_list->AddRect(min, max, color, rounding, flags, thickness);
#endif
}

inline bool IsFontAtlasBuilt(const ImFontAtlas& atlas)
{
#if IMGUI_VERSION_NUM >= 19200
    return atlas.Fonts.Size > 0;
#else
    return atlas.IsBuilt();
#endif
}

} // namespace overlay_imgui_compat
