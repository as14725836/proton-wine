/*
 * Wayland touch handling
 *
 * Copyright (c) 2026 The412Banner
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA
 */

#if 0
#pragma makedep unix
#endif

#include "config.h"

#include <stdlib.h>

#include "waylanddrv.h"
#include "wine/debug.h"

WINE_DEFAULT_DEBUG_CHANNEL(waylanddrv);

/* A finger stays with the window it went down on until it lifts: wl_touch only names the surface in
 * the down event, and Windows expects the whole WM_POINTER* sequence for one id to reach one window
 * even if the finger slides off it. */
struct touch_point
{
    int32_t id;
    HWND hwnd;
    POINT last;     /* wl_touch.up carries no position; Windows still wants one */
    BOOL active;
};

#define MAX_TOUCH_POINTS 10
static struct touch_point touch_points[MAX_TOUCH_POINTS];

static struct touch_point *touch_point_find(int32_t id)
{
    int i;
    for (i = 0; i < MAX_TOUCH_POINTS; i++)
        if (touch_points[i].active && touch_points[i].id == id) return &touch_points[i];
    return NULL;
}

static struct touch_point *touch_point_add(int32_t id, HWND hwnd)
{
    int i;
    struct touch_point *tp = touch_point_find(id);
    if (tp) tp->active = FALSE;  /* stale id: start it again */
    for (i = 0; i < MAX_TOUCH_POINTS; i++)
    {
        if (touch_points[i].active) continue;
        touch_points[i].id = id;
        touch_points[i].hwnd = hwnd;
        touch_points[i].last.x = 0;
        touch_points[i].last.y = 0;
        touch_points[i].active = TRUE;
        return &touch_points[i];
    }
    return NULL;
}

/* Surface-local wl_fixed coordinates -> screen coordinates, exactly as the pointer does. */
static BOOL touch_screen_coords(HWND hwnd, wl_fixed_t sx, wl_fixed_t sy, POINT *screen)
{
    struct wayland_win_data *data;
    struct wayland_surface *surface;
    RECT *window_rect;

    if (!(data = wayland_win_data_get(hwnd))) return FALSE;
    if (!(surface = data->wayland_surface))
    {
        wayland_win_data_release(data);
        return FALSE;
    }

    window_rect = &surface->window.rect;
    wayland_surface_coords_to_window(surface,
                                     wl_fixed_to_double(sx),
                                     wl_fixed_to_double(sy),
                                     (int *)&screen->x, (int *)&screen->y);
    screen->x += window_rect->left;
    screen->y += window_rect->top;
    /* Rounding can land a finger just outside its window; bring it back in. */
    if (screen->x >= window_rect->right) screen->x = window_rect->right - 1;
    else if (screen->x < window_rect->left) screen->x = window_rect->left;
    if (screen->y >= window_rect->bottom) screen->y = window_rect->bottom - 1;
    else if (screen->y < window_rect->top) screen->y = window_rect->top;

    wayland_win_data_release(data);
    return TRUE;
}

/* wineserver reads a WM_POINTER* lparam as a point normalized to 0..65535 over the virtual screen
 * (server/queue.c queue_pointer_message), not as pixels - encode it that way or every finger lands
 * near the top-left corner. Same encoding as upstream winewayland touch. */
static LPARAM touch_lparam(POINT pos)
{
    RECT vscreen = NtUserGetVirtualScreenRect(MDT_RAW_DPI);
    int width = vscreen.right - vscreen.left, height = vscreen.bottom - vscreen.top;
    int x, y;

    if (width <= 0 || height <= 0) return 0;
    x = (int)((long long)pos.x * 65535 / width);
    y = (int)((long long)pos.y * 65535 / height);
    x = max(0, min(x, 65535));
    y = max(0, min(y, 65535));
    return MAKELPARAM(x, y);
}

/* One finger to Windows as a WM_POINTER* message, the same shape winex11.drv builds from XInput2
 * raw touch: the id goes in wParamL so a game can tell fingers apart. */
static void touch_send(HWND hwnd, UINT msg, int32_t id, POINT pos, int extra_flags)
{
    INPUT input = {0};

    input.type = INPUT_HARDWARE;
    input.hi.uMsg = msg;
    input.hi.wParamL = id;
    input.hi.wParamH = POINTER_MESSAGE_FLAG_INRANGE | POINTER_MESSAGE_FLAG_INCONTACT | extra_flags;

    TRACE("hwnd=%p msg=%#x id=%d pos=%dx%d flags=%#x\n", hwnd, msg, id,
          (int)pos.x, (int)pos.y, input.hi.wParamH);

    NtUserSendHardwareInput(hwnd, 0, &input, touch_lparam(pos));
}

static void touch_handle_down(void *data, struct wl_touch *wl_touch, uint32_t serial,
                              uint32_t time, struct wl_surface *wl_surface, int32_t id,
                              wl_fixed_t sx, wl_fixed_t sy)
{
    struct touch_point *tp;
    POINT screen;
    HWND hwnd;

    if (!wl_surface) return;
    /* The surface may be destroyed between the compositor sending this and us reading it. */
    if (!(hwnd = wl_surface_get_user_data(wl_surface))) return;
    if (!touch_screen_coords(hwnd, sx, sy, &screen)) return;
    if (!(tp = touch_point_add(id, hwnd))) return;  /* more fingers than we track */
    tp->last = screen;

    touch_send(hwnd, WM_POINTERDOWN, id, screen, POINTER_MESSAGE_FLAG_NEW);
}

static void touch_handle_up(void *data, struct wl_touch *wl_touch, uint32_t serial,
                            uint32_t time, int32_t id)
{
    struct touch_point *tp = touch_point_find(id);

    if (!tp) return;
    /* wl_touch.up carries no position, so release the finger where it last was. Sending 0,0 would
     * make the game see the touch jump to the corner before it ended. */
    touch_send(tp->hwnd, WM_POINTERUP, id, tp->last, 0);
    tp->active = FALSE;
}

static void touch_handle_motion(void *data, struct wl_touch *wl_touch, uint32_t time,
                                int32_t id, wl_fixed_t sx, wl_fixed_t sy)
{
    struct touch_point *tp = touch_point_find(id);
    POINT screen;

    if (!tp) return;
    if (!touch_screen_coords(tp->hwnd, sx, sy, &screen)) return;
    tp->last = screen;

    touch_send(tp->hwnd, WM_POINTERUPDATE, id, screen, 0);
}

static void touch_handle_frame(void *data, struct wl_touch *wl_touch)
{
    /* Each finger is sent as it arrives; nothing is batched, so there is nothing to flush. */
}

static void touch_handle_cancel(void *data, struct wl_touch *wl_touch)
{
    int i;

    /* The compositor took the gesture over: end every sequence so the game is not left believing
     * fingers are still down. */
    for (i = 0; i < MAX_TOUCH_POINTS; i++)
    {
        if (!touch_points[i].active) continue;
        touch_send(touch_points[i].hwnd, WM_POINTERUP, touch_points[i].id, touch_points[i].last, 0);
        touch_points[i].active = FALSE;
    }
}

static void touch_handle_shape(void *data, struct wl_touch *wl_touch, int32_t id,
                               wl_fixed_t major, wl_fixed_t minor)
{
    /* Contact ellipse: Windows carries it in POINTER_TOUCH_INFO, which this path does not build. */
}

static void touch_handle_orientation(void *data, struct wl_touch *wl_touch, int32_t id,
                                     wl_fixed_t orientation)
{
    /* As above: not represented in the hardware-input path. */
}

static const struct wl_touch_listener touch_listener =
{
    touch_handle_down,
    touch_handle_up,
    touch_handle_motion,
    touch_handle_frame,
    touch_handle_cancel,
    touch_handle_shape,
    touch_handle_orientation,
};

/**********************************************************************
 *          wayland_touch_init
 */
void wayland_touch_init(struct wl_touch *wl_touch)
{
    struct wayland_touch *touch = &process_wayland.touch;

    TRACE("wl_touch=%p\n", wl_touch);

    pthread_mutex_lock(&touch->mutex);
    touch->wl_touch = wl_touch;
    pthread_mutex_unlock(&touch->mutex);

    wl_touch_add_listener(wl_touch, &touch_listener, NULL);
}

/**********************************************************************
 *          wayland_touch_deinit
 */
void wayland_touch_deinit(void)
{
    struct wayland_touch *touch = &process_wayland.touch;
    int i;

    TRACE("\n");

    pthread_mutex_lock(&touch->mutex);
    if (touch->wl_touch)
    {
        wl_touch_release(touch->wl_touch);
        touch->wl_touch = NULL;
    }
    for (i = 0; i < MAX_TOUCH_POINTS; i++) touch_points[i].active = FALSE;
    pthread_mutex_unlock(&touch->mutex);
}
