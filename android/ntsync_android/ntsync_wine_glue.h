/*
 * Opt-in userspace ntsync for Android (WINENTSYNC=1) - Wine-side glue.
 *
 * The backend is ntsync-android by Joshua Tam (joshuatam, GameNative),
 * https://github.com/GameNative/ntsync-android, pinned at commit
 * 7ce6435e5979b1cb5341aa4b299f31e8937fe121 and statically linked as
 * libntsync_android.a (LGPL-3.0-only; see LICENSE next to this file and
 * share/licenses/ntsync-android/ in the packaged layer). The Wine wiring is
 * adapted from GameNative/proton-wine proton_11.0-2 (d67ac1e0, 0971187),
 * reworked so that it only ever engages when WINENTSYNC=1 is set: with the
 * variable unset every code path below is dead and the layer behaves exactly
 * like the esync build it replaces.
 *
 * These are the C entry points of the library (its include/ntsync_user.h).
 * They are declared here against the kernel uapi structs from ntsync_tmp.h,
 * which the including file must include first for the object/wait calls
 * (ntsync_init/ntsync_sweep_dead need no structs): the library mirrors the
 * kernel /dev/ntsync ABI 1:1 (identical struct layouts), so both backends
 * share one set of argument structs and ntsync_tmp.h stays untouched.
 */
#ifndef NTSYNC_WINE_GLUE_H
#define NTSYNC_WINE_GLUE_H

#include <stdint.h>
#include <stdlib.h>

/* Sentinel in the init_first_thread reply's inproc_device field meaning
 * "the server uses userspace ntsync; attach to the shared region yourself".
 * Object handles then travel in the sync_shm_idx reply field. Same value
 * as GameNative's build. */
#define NTSYNC_ANDROID_USED_BY_SERVER 0x7eadfe01

/* 1 when WINENTSYNC is set to a non-zero number and PROTON_NO_NTSYNC is not. */
static inline int ntsync_opt_in_requested(void)
{
    const char *e = getenv( "WINENTSYNC" ), *no = getenv( "PROTON_NO_NTSYNC" );
    return e && atoi( e ) && !(no && atoi( no ));
}

int32_t ntsync_init(const char *path);
int32_t ntsync_sweep_dead(void);

#ifdef NTSYNC_IOC_EVENT_READ
int32_t ntsync_create_sem(uint32_t *out_handle, const struct ntsync_sem_args *args);
int32_t ntsync_create_mutex(uint32_t *out_handle, const struct ntsync_mutex_args *args);
int32_t ntsync_create_event(uint32_t *out_handle, const struct ntsync_event_args *args);
int32_t ntsync_close(uint32_t handle);
int32_t ntsync_sem_release(uint32_t handle, uint32_t *count);
int32_t ntsync_sem_read(uint32_t handle, struct ntsync_sem_args *args);
int32_t ntsync_mutex_unlock(uint32_t handle, struct ntsync_mutex_args *args);
int32_t ntsync_mutex_kill(uint32_t handle, uint32_t owner);
int32_t ntsync_mutex_read(uint32_t handle, struct ntsync_mutex_args *args);
int32_t ntsync_event_set(uint32_t handle, uint32_t *prev);
int32_t ntsync_event_reset(uint32_t handle, uint32_t *prev);
int32_t ntsync_event_pulse(uint32_t handle, uint32_t *prev);
int32_t ntsync_event_read(uint32_t handle, struct ntsync_event_args *args);
int32_t ntsync_wait_any(struct ntsync_wait_args *args);
int32_t ntsync_wait_all(struct ntsync_wait_args *args);
#endif

#endif /* NTSYNC_WINE_GLUE_H */
