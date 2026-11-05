// Traitor Voice – shared memory protocol between gmcl_traitorvoice (GMod) and the TS3 plugin.
// SPDX-License-Identifier: MIT
//
// Layout rules: the GMod module may be 32-bit while TeamSpeak is 64-bit, so every struct here
// uses fixed-size 4-byte-aligned fields only (no pointers, no 64-bit integers, no bool).
// Each half has exactly one writer and uses a sequence lock:
//   seq odd  = write in progress, seq even = consistent.
#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <stdint.h>
#include <string.h>

#define TV_PROTOCOL_VERSION 1u
#define TV_MAX_CLIENTS 128
#define TV_UID_LEN 64
#define TV_SHM_NAME L"Local\\TraitorVoice_v1"

// Heartbeats older than this (ms) mean the other side is gone.
#define TV_HEARTBEAT_TIMEOUT_MS 1500u

// --- written by GMod ------------------------------------------------------------------------

enum TvClientFlags : uint32_t {
    TV_CF_MUTED = 1u << 0,  // never hear this speaker (e.g. dead speaker while I am alive)
    TV_CF_RADIO = 1u << 1,  // speaker is transmitting over the radio: radio effect, no 3D
    TV_CF_NO3D  = 1u << 2,  // hear without position (e.g. dead <-> dead)
};

enum TvTransmit : uint32_t {
    TV_TX_NONE      = 0,
    TV_TX_PROXIMITY = 1,
    TV_TX_RADIO     = 2,
};

enum TvGameFlags : uint32_t {
    TV_GF_ACTIVE           = 1u << 0,  // GMod is on a Traitor Voice server, plugin should take over
    TV_GF_VOICE_ACTIVATION = 1u << 1,  // player uses TS voice activation instead of push-to-talk
    TV_GF_MUTE_UNKNOWN     = 1u << 2,  // mute TS clients that are not in the game
};

#pragma pack(push, 4)

struct TvClient {
    uint16_t tsClientId;  // TeamSpeak anyID of the speaker
    uint16_t reserved;
    uint32_t flags;       // TvClientFlags
    float gain;           // 0..1, distance + voice level (radio: radio volume)
    float x, y, z;        // speaker position relative to the listener in metres: x right, y up, z forward
    float occlusion;      // 0 = free line of sight, 1 = fully blocked
};

struct TvGameState {
    volatile LONG seq;
    uint32_t protocol;     // TV_PROTOCOL_VERSION
    uint32_t heartbeat;    // GetTickCount() of the last update
    uint32_t flags;        // TvGameFlags
    uint32_t transmit;     // TvTransmit: what the local player sends right now
    float masterVolume;    // 0..2
    float radioVolume;     // 0..2
    float radioEffect;     // 0..1 strength of the radio filter
    char expectedServerUid[TV_UID_LEN];  // optional; empty = accept any TS server
    uint32_t clientCount;
    TvClient clients[TV_MAX_CLIENTS];
};

// --- written by the TS3 plugin --------------------------------------------------------------

struct TvPluginState {
    volatile LONG seq;
    uint32_t protocol;     // TV_PROTOCOL_VERSION
    uint32_t pluginVersion;  // e.g. 100 = 0.1.0
    uint32_t heartbeat;    // GetTickCount()
    uint32_t connected;    // 1 = connected to a TS server
    uint32_t active;       // 1 = plugin is currently processing voices for GMod
    uint16_t ownClientId;
    uint16_t reserved;
    uint32_t channelIdLo;
    uint32_t channelIdHi;
    char serverUid[TV_UID_LEN];
    float micLevel;        // 0..1 peak of the local microphone
    uint32_t talkingCount;
    uint16_t talking[TV_MAX_CLIENTS];  // TS client IDs that are talking right now
};

struct TvShared {
    TvGameState game;
    TvPluginState plugin;
};

#pragma pack(pop)

static_assert(sizeof(TvClient) == 28, "TvClient layout changed");
static_assert(sizeof(TvGameState) == 4 * 8 + TV_UID_LEN + 4 + 28 * TV_MAX_CLIENTS, "TvGameState layout changed");
static_assert(sizeof(TvPluginState) == 4 * 9 + TV_UID_LEN + 4 + 4 + 2 * TV_MAX_CLIENTS, "TvPluginState layout changed");

// --- helpers --------------------------------------------------------------------------------

// Opens (or creates) the shared memory. Both sides call this; whoever comes first creates it.
inline TvShared* tvOpenShared(HANDLE* outMapping)
{
    HANDLE mapping = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0,
                                        (DWORD)sizeof(TvShared), TV_SHM_NAME);
    if (!mapping)
        return nullptr;
    const bool created = GetLastError() != ERROR_ALREADY_EXISTS;
    void* view = MapViewOfFile(mapping, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(TvShared));
    if (!view) {
        CloseHandle(mapping);
        return nullptr;
    }
    if (created)
        memset(view, 0, sizeof(TvShared));
    *outMapping = mapping;
    return static_cast<TvShared*>(view);
}

inline void tvCloseShared(TvShared* shared, HANDLE mapping)
{
    if (shared)
        UnmapViewOfFile(shared);
    if (mapping)
        CloseHandle(mapping);
}

// Single writer: copies everything after the seq field from src into dst.
template <class T>
inline void tvWrite(T* dst, const T& src)
{
    InterlockedIncrement(&dst->seq);  // odd: writing
    MemoryBarrier();
    memcpy(reinterpret_cast<char*>(dst) + sizeof(LONG), reinterpret_cast<const char*>(&src) + sizeof(LONG),
           sizeof(T) - sizeof(LONG));
    MemoryBarrier();
    InterlockedIncrement(&dst->seq);  // even: done
}

// Reader: returns false if no consistent snapshot could be taken.
template <class T>
inline bool tvRead(const T* src, T* out)
{
    for (int attempt = 0; attempt < 16; ++attempt) {
        const LONG before = src->seq;
        if (before & 1) {
            YieldProcessor();
            continue;
        }
        MemoryBarrier();
        memcpy(out, const_cast<const T*>(src), sizeof(T));
        MemoryBarrier();
        if (src->seq == before)
            return true;
    }
    return false;
}

inline bool tvIsFresh(uint32_t heartbeat)
{
    return heartbeat != 0 && (uint32_t)(GetTickCount() - heartbeat) < TV_HEARTBEAT_TIMEOUT_MS;
}
