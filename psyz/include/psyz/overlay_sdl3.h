#ifndef PSYZ_OVERLAY_SDL3_H
#define PSYZ_OVERLAY_SDL3_H
#include <SDL3/SDL.h>

#ifdef __cplusplus
extern "C" {
#endif

// Called for each SDL3 input event.
// Use this to forward events to overlay input handling (e.g., ImGui).
typedef void (*PsyzOverlayEventCB_SDL3)(const SDL_Event* event);

// Register the SDL3 event callback.
// Returns the previous callback, or NULL if none was set.
PsyzOverlayEventCB_SDL3 Psyz_OverlayEvent_SDL3(PsyzOverlayEventCB_SDL3 cb);

/* A consuming filter runs before the observer and SDK shortcuts. Return true
 * for events owned by a modal settings panel (including Escape). */
typedef bool (*PsyzOverlayEventFilter_SDL3)(const SDL_Event* event);
PsyzOverlayEventFilter_SDL3 Psyz_SetOverlayEventFilter_SDL3(PsyzOverlayEventFilter_SDL3 filter);
/* Shares fullscreen state with the SDK F4 shortcut. */
bool Psyz_SetFullscreen_SDL3(bool enabled);
/* Physical PS1 button index uses libetc PAD bit positions, 0..15. */
int Psyz_GetKeyboardBinding_SDL3(unsigned button);
int Psyz_SetKeyboardBinding_SDL3(unsigned button, SDL_Scancode key);
/* SDL gamepad button, or SDL_GAMEPAD_BUTTON_COUNT + 0/1 for L/R trigger. */
int Psyz_GetGamepadBinding_SDL3(unsigned button);
int Psyz_SetGamepadBinding_SDL3(unsigned button, int binding);

#ifdef __cplusplus
}
#endif

#endif // PSYZ_OVERLAY_SDL3_H
