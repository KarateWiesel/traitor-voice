// Traitor Voice – GMod client module (gmcl_traitorvoice_win32.dll / gmcl_traitorvoice_win64.dll)
// SPDX-License-Identifier: MIT
//
// Lua API (client realm, after require("traitorvoice")):
//   traitorvoice.VERSION                      -> number (module version, 100 = 0.1.0)
//   traitorvoice.PROTOCOL                     -> number
//   traitorvoice.Update(state)                -> writes the game state for the TS3 plugin
//   traitorvoice.GetStatus()                  -> table with the plugin state
//
// The module never opens a network connection. It only talks to the TS3 plugin through
// the shared memory described in shared/traitorvoice_protocol.h.

#define GMMODULE
#include <GarrysMod/Lua/Interface.h>

#include "traitorvoice_protocol.h"

#include <algorithm>
#include <cstdio>

using namespace GarrysMod::Lua;

#ifndef LUA_FUNCTION
#define LUA_FUNCTION(name) static int name(lua_State* state)
#endif

#define TV_MODULE_VERSION 100

static HANDLE g_mapping = nullptr;
static TvShared* g_shared = nullptr;
static TvGameState g_game;  // scratch buffer, written to shared memory in one go

static double getNumberField(lua_State* state, int tableIndex, const char* name, double fallback)
{
    LUA->GetField(tableIndex, name);
    double value = LUA->IsType(-1, Type::NUMBER) ? LUA->GetNumber(-1) : fallback;
    LUA->Pop();
    return value;
}

static bool getBoolField(lua_State* state, int tableIndex, const char* name, bool fallback)
{
    LUA->GetField(tableIndex, name);
    bool value = LUA->IsType(-1, Type::BOOL) ? LUA->GetBool(-1) : fallback;
    LUA->Pop();
    return value;
}

static float clampf(double v, float lo, float hi)
{
    return (float)std::min<double>(hi, std::max<double>(lo, v));
}

// traitorvoice.Update({ active=bool, voiceActivation=bool, muteUnknown=bool, transmit=0|1|2,
//   masterVolume=n, radioVolume=n, radioEffect=n, serverUid="...",
//   clients = { { ts=id, gain=n, x=n, y=n, z=n, occ=n, flags=n }, ... } })
LUA_FUNCTION(TV_Update)
{
    LUA->CheckType(1, Type::TABLE);
    if (!g_shared) {
        LUA->PushBool(false);
        return 1;
    }

    TvGameState& g = g_game;
    g.protocol = TV_PROTOCOL_VERSION;
    g.heartbeat = GetTickCount();
    if (g.heartbeat == 0)
        g.heartbeat = 1;

    uint32_t flags = 0;
    if (getBoolField(state, 1, "active", false))
        flags |= TV_GF_ACTIVE;
    if (getBoolField(state, 1, "voiceActivation", false))
        flags |= TV_GF_VOICE_ACTIVATION;
    if (getBoolField(state, 1, "muteUnknown", true))
        flags |= TV_GF_MUTE_UNKNOWN;
    g.flags = flags;

    const double tx = getNumberField(state, 1, "transmit", 0);
    g.transmit = (tx >= 2) ? TV_TX_RADIO : (tx >= 1 ? TV_TX_PROXIMITY : TV_TX_NONE);
    g.masterVolume = clampf(getNumberField(state, 1, "masterVolume", 1.0), 0.0f, 2.0f);
    g.radioVolume = clampf(getNumberField(state, 1, "radioVolume", 1.0), 0.0f, 2.0f);
    g.radioEffect = clampf(getNumberField(state, 1, "radioEffect", 0.6), 0.0f, 1.0f);

    memset(g.expectedServerUid, 0, sizeof(g.expectedServerUid));
    LUA->GetField(1, "serverUid");
    if (LUA->IsType(-1, Type::STRING)) {
        const char* uid = LUA->GetString(-1);
        strncpy_s(g.expectedServerUid, sizeof(g.expectedServerUid), uid, _TRUNCATE);
    }
    LUA->Pop();

    uint32_t count = 0;
    LUA->GetField(1, "clients");
    if (LUA->IsType(-1, Type::TABLE)) {
        const int clientsIndex = LUA->Top();
        for (int i = 1; count < TV_MAX_CLIENTS; ++i) {
            LUA->PushNumber(i);
            LUA->GetTable(clientsIndex);
            if (!LUA->IsType(-1, Type::TABLE)) {
                LUA->Pop();
                break;
            }
            const int entry = LUA->Top();
            const double ts = getNumberField(state, entry, "ts", -1);
            if (ts >= 0 && ts <= 65535) {
                TvClient& c = g.clients[count++];
                c.tsClientId = (uint16_t)ts;
                c.reserved = 0;
                c.flags = (uint32_t)getNumberField(state, entry, "flags", 0);
                c.gain = clampf(getNumberField(state, entry, "gain", 0), 0.0f, 1.0f);
                c.x = (float)getNumberField(state, entry, "x", 0);
                c.y = (float)getNumberField(state, entry, "y", 0);
                c.z = (float)getNumberField(state, entry, "z", 0);
                c.occlusion = clampf(getNumberField(state, entry, "occ", 0), 0.0f, 1.0f);
            }
            LUA->Pop();
        }
    }
    LUA->Pop();
    g.clientCount = count;

    tvWrite(&g_shared->game, g);
    LUA->PushBool(true);
    return 1;
}

// Marks the game side as inactive so the plugin hands control back to TeamSpeak.
LUA_FUNCTION(TV_Release)
{
    if (g_shared) {
        g_game.flags = 0;
        g_game.transmit = TV_TX_NONE;
        g_game.clientCount = 0;
        g_game.heartbeat = 0;
        tvWrite(&g_shared->game, g_game);
    }
    return 0;
}

LUA_FUNCTION(TV_GetStatus)
{
    LUA->CreateTable();
    if (!g_shared)
        return 1;

    static TvPluginState p;
    const bool ok = tvRead(&g_shared->plugin, &p);

    const bool running = ok && tvIsFresh(p.heartbeat);
    LUA->PushBool(running);
    LUA->SetField(-2, "pluginRunning");
    LUA->PushBool(ok && p.protocol == TV_PROTOCOL_VERSION);
    LUA->SetField(-2, "protocolOk");
    LUA->PushNumber(ok ? p.protocol : 0);
    LUA->SetField(-2, "pluginProtocol");
    LUA->PushNumber(ok ? p.pluginVersion : 0);
    LUA->SetField(-2, "pluginVersion");
    LUA->PushBool(running && p.connected != 0);
    LUA->SetField(-2, "connected");
    LUA->PushBool(running && p.active != 0);
    LUA->SetField(-2, "active");
    LUA->PushNumber(running ? p.ownClientId : -1);
    LUA->SetField(-2, "clientId");
    char channel[32];
    snprintf(channel, sizeof(channel), "%llu", ((unsigned long long)p.channelIdHi << 32) | p.channelIdLo);
    LUA->PushString(running ? channel : "0");
    LUA->SetField(-2, "channelId");
    p.serverUid[TV_UID_LEN - 1] = 0;
    LUA->PushString(running ? p.serverUid : "");
    LUA->SetField(-2, "serverUid");
    LUA->PushNumber(running ? p.micLevel : 0);
    LUA->SetField(-2, "micLevel");

    LUA->CreateTable();
    const uint32_t n = running ? std::min<uint32_t>(p.talkingCount, TV_MAX_CLIENTS) : 0;
    for (uint32_t i = 0; i < n; ++i) {
        LUA->PushNumber(i + 1);
        LUA->PushNumber(p.talking[i]);
        LUA->SetTable(-3);
    }
    LUA->SetField(-2, "talking");
    return 1;
}

GMOD_MODULE_OPEN()
{
    memset(&g_game, 0, sizeof(g_game));
    g_shared = tvOpenShared(&g_mapping);

    LUA->PushSpecial(SPECIAL_GLOB);
    LUA->CreateTable();
    LUA->PushNumber(TV_MODULE_VERSION);
    LUA->SetField(-2, "VERSION");
    LUA->PushNumber(TV_PROTOCOL_VERSION);
    LUA->SetField(-2, "PROTOCOL");
    LUA->PushBool(g_shared != nullptr);
    LUA->SetField(-2, "SHARED_MEMORY_OK");
    LUA->PushCFunction(TV_Update);
    LUA->SetField(-2, "Update");
    LUA->PushCFunction(TV_Release);
    LUA->SetField(-2, "Release");
    LUA->PushCFunction(TV_GetStatus);
    LUA->SetField(-2, "GetStatus");
    LUA->SetField(-2, "traitorvoice");
    LUA->Pop();
    return 0;
}

GMOD_MODULE_CLOSE()
{
    if (g_shared) {
        g_game.flags = 0;
        g_game.transmit = TV_TX_NONE;
        g_game.clientCount = 0;
        g_game.heartbeat = 0;
        tvWrite(&g_shared->game, g_game);
    }
    tvCloseShared(g_shared, g_mapping);
    g_shared = nullptr;
    g_mapping = nullptr;
    return 0;
}
