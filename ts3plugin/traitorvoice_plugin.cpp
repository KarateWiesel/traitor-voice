// Traitor Voice – TeamSpeak 3 client plugin
// SPDX-License-Identifier: MIT
//
// Architecture inspired by Gspeak (https://github.com/Thendon/Gspeak, MIT): the plugin reads
// per-speaker data written by a GMod module into shared memory, places speakers with the
// TeamSpeak 3D functions and edits each speaker's audio. This file is an independent rewrite.

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include "teamspeak/public_definitions.h"
#include "teamspeak/public_errors.h"
#include "ts3_functions.h"

#include "traitorvoice_protocol.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <random>
#include <set>
#include <thread>
#include <unordered_map>

#define TV_PLUGIN_API_VERSION 26
#define TV_PLUGIN_VERSION_NUM 100
#define TV_PLUGIN_VERSION_STR "0.1.0"
#define TV_SAMPLE_RATE 48000.0f
#define TV_MAX_CHANNELS 8

#define EXPORT extern "C" __declspec(dllexport)

static TS3Functions ts3;

// --------------------------------------------------------------------------------------------
// State shared between the worker thread and the audio callbacks
// --------------------------------------------------------------------------------------------

struct SpeakerInfo {
    uint32_t flags = 0;
    float gain = 0.0f;
    float occlusion = 0.0f;
};

struct Snapshot {
    bool active = false;
    bool muteUnknown = true;
    float masterVolume = 1.0f;
    float radioVolume = 1.0f;
    float radioEffect = 0.6f;
    std::unordered_map<anyID, SpeakerInfo> speakers;
};

struct FilterState {
    float lp1[TV_MAX_CHANNELS] = {};
    float lp2[TV_MAX_CHANNELS] = {};
    float hpIn[TV_MAX_CHANNELS] = {};
    float hpOut[TV_MAX_CHANNELS] = {};
    float occ[TV_MAX_CHANNELS] = {};
};

static HANDLE g_mapping = nullptr;
static TvShared* g_shared = nullptr;

static std::mutex g_snapMutex;
static Snapshot g_snap;  // guarded by g_snapMutex

static std::mutex g_filterMutex;
static std::unordered_map<anyID, FilterState> g_filters;  // guarded by g_filterMutex

static std::mutex g_talkMutex;
static std::set<anyID> g_talking;  // guarded by g_talkMutex

static std::atomic<float> g_micLevel{0.0f};
static std::atomic<bool> g_running{false};
static std::thread g_worker;

// Input (push-to-talk) handling
static uint64 g_controlledSchid = 0;
static int g_originalInputDeactivated = -1;  // -1 = we have not touched the input
static int g_lastInputDeactivated = -1;

// --------------------------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------------------------

static void logInfo(const char* msg)
{
    if (ts3.logMessage)
        ts3.logMessage(msg, LogLevel_INFO, "TraitorVoice", 0);
}

static void setInputDeactivated(uint64 schid, int deactivated)
{
    if (!schid)
        return;
    if (g_originalInputDeactivated < 0) {
        int current = 0;
        if (ts3.getClientSelfVariableAsInt(schid, CLIENT_INPUT_DEACTIVATED, &current) == ERROR_ok)
            g_originalInputDeactivated = current;
        else
            g_originalInputDeactivated = INPUT_ACTIVE;
        g_controlledSchid = schid;
    }
    if (g_lastInputDeactivated == deactivated && g_controlledSchid == schid)
        return;
    if (ts3.setClientSelfVariableAsInt(schid, CLIENT_INPUT_DEACTIVATED, deactivated) == ERROR_ok)
        ts3.flushClientSelfUpdates(schid, nullptr);
    g_lastInputDeactivated = deactivated;
}

static void restoreInput()
{
    if (g_originalInputDeactivated >= 0 && g_controlledSchid) {
        if (ts3.setClientSelfVariableAsInt(g_controlledSchid, CLIENT_INPUT_DEACTIVATED, g_originalInputDeactivated) ==
            ERROR_ok)
            ts3.flushClientSelfUpdates(g_controlledSchid, nullptr);
    }
    g_originalInputDeactivated = -1;
    g_lastInputDeactivated = -1;
    g_controlledSchid = 0;
}

// --------------------------------------------------------------------------------------------
// Worker thread: 50 Hz, reads the game state, positions speakers, publishes plugin state
// --------------------------------------------------------------------------------------------

static void workerLoop()
{
    static TvGameState game;
    static TvPluginState out;
    bool wasActive = false;
    bool listenerSet = false;
    uint64 listenerSchid = 0;

    while (g_running.load()) {
        memset(&out, 0, sizeof(out));
        out.protocol = TV_PROTOCOL_VERSION;
        out.pluginVersion = TV_PLUGIN_VERSION_NUM;

        const uint64 schid = ts3.getCurrentServerConnectionHandlerID();
        int status = STATUS_DISCONNECTED;
        if (schid)
            ts3.getConnectionStatus(schid, &status);
        const bool connected = status == STATUS_CONNECTION_ESTABLISHED;
        out.connected = connected ? 1 : 0;

        if (connected) {
            anyID me = 0;
            if (ts3.getClientID(schid, &me) == ERROR_ok)
                out.ownClientId = me;
            uint64 channel = 0;
            if (ts3.getChannelOfClient(schid, me, &channel) == ERROR_ok) {
                out.channelIdLo = (uint32_t)(channel & 0xffffffffu);
                out.channelIdHi = (uint32_t)(channel >> 32);
            }
            char* uid = nullptr;
            if (ts3.getServerVariableAsString(schid, VIRTUALSERVER_UNIQUE_IDENTIFIER, &uid) == ERROR_ok && uid) {
                strncpy_s(out.serverUid, sizeof(out.serverUid), uid, _TRUNCATE);
                ts3.freeMemory(uid);
            }
        }

        const bool haveGame = tvRead(&g_shared->game, &game);
        bool active = connected && haveGame && game.protocol == TV_PROTOCOL_VERSION && tvIsFresh(game.heartbeat) &&
                      (game.flags & TV_GF_ACTIVE);
        if (active && game.expectedServerUid[0]) {
            game.expectedServerUid[TV_UID_LEN - 1] = 0;
            active = strcmp(game.expectedServerUid, out.serverUid) == 0;
        }
        out.active = active ? 1 : 0;

        // Publish the snapshot for the audio thread.
        {
            Snapshot snap;
            snap.active = active;
            if (active) {
                snap.muteUnknown = (game.flags & TV_GF_MUTE_UNKNOWN) != 0;
                snap.masterVolume = game.masterVolume;
                snap.radioVolume = game.radioVolume;
                snap.radioEffect = game.radioEffect;
                const uint32_t n = std::min<uint32_t>(game.clientCount, TV_MAX_CLIENTS);
                for (uint32_t i = 0; i < n; ++i) {
                    const TvClient& c = game.clients[i];
                    SpeakerInfo info;
                    info.flags = c.flags;
                    info.gain = c.gain;
                    info.occlusion = c.occlusion;
                    snap.speakers[c.tsClientId] = info;
                }
            }
            std::lock_guard<std::mutex> lock(g_snapMutex);
            g_snap = std::move(snap);
        }

        if (active) {
            // Listener sits in the origin looking along +z; speakers are sent relative to it.
            if (!listenerSet || listenerSchid != schid) {
                const TS3_VECTOR zero = {0.0f, 0.0f, 0.0f};
                const TS3_VECTOR forward = {0.0f, 0.0f, 1.0f};
                const TS3_VECTOR up = {0.0f, 1.0f, 0.0f};
                ts3.systemset3DSettings(schid, 1.0f, 1.0f);
                ts3.systemset3DListenerAttributes(schid, &zero, &forward, &up);
                listenerSet = true;
                listenerSchid = schid;
            }
            const uint32_t n = std::min<uint32_t>(game.clientCount, TV_MAX_CLIENTS);
            for (uint32_t i = 0; i < n; ++i) {
                const TvClient& c = game.clients[i];
                TS3_VECTOR pos = {c.x, c.y, c.z};
                if (c.flags & (TV_CF_RADIO | TV_CF_NO3D)) {
                    pos.x = 0.0f;
                    pos.y = 0.0f;
                    pos.z = 0.0f;
                }
                ts3.channelset3DAttributes(schid, c.tsClientId, &pos);
            }

            // Push-to-talk: TeamSpeak only sends while the game says so.
            const bool voiceActivation = (game.flags & TV_GF_VOICE_ACTIVATION) != 0;
            const bool wantSend = voiceActivation || game.transmit != TV_TX_NONE;
            setInputDeactivated(schid, wantSend ? INPUT_ACTIVE : INPUT_DEACTIVATED);
        } else if (wasActive) {
            restoreInput();
            listenerSet = false;
            std::lock_guard<std::mutex> lock(g_filterMutex);
            g_filters.clear();
        }
        wasActive = active;

        out.micLevel = g_micLevel.load();
        {
            std::lock_guard<std::mutex> lock(g_talkMutex);
            uint32_t i = 0;
            for (anyID id : g_talking) {
                if (i >= TV_MAX_CLIENTS)
                    break;
                out.talking[i++] = id;
            }
            out.talkingCount = i;
        }
        out.heartbeat = GetTickCount();
        if (out.heartbeat == 0)
            out.heartbeat = 1;
        tvWrite(&g_shared->plugin, out);

        Sleep(20);
    }

    restoreInput();
}

// --------------------------------------------------------------------------------------------
// Audio processing
// --------------------------------------------------------------------------------------------

static inline float onePoleAlpha(float cutoffHz)
{
    return 1.0f - std::exp(-2.0f * 3.14159265f * cutoffHz / TV_SAMPLE_RATE);
}

static inline short toShort(float v)
{
    if (v > 32767.0f)
        return 32767;
    if (v < -32768.0f)
        return -32768;
    return (short)v;
}

static void processSpeaker(FilterState& f, short* samples, int sampleCount, int channels, const SpeakerInfo& s,
                           const Snapshot& snap)
{
    const bool radio = (s.flags & TV_CF_RADIO) != 0;
    const int ch = std::min(channels, TV_MAX_CHANNELS);

    if (radio) {
        // Radio: band-pass (~350 Hz .. ~2800 Hz), soft clipping, a little noise.
        static thread_local std::minstd_rand rng(12345);
        std::uniform_real_distribution<float> noise(-1.0f, 1.0f);
        const float hpA = onePoleAlpha(350.0f);
        const float lpA = onePoleAlpha(2800.0f);
        const float strength = snap.radioEffect;
        const float drive = 1.0f + 4.0f * strength;
        const float norm = std::tanh(drive);
        const float gain = std::min(2.0f, snap.radioVolume * snap.masterVolume);
        for (int i = 0; i < sampleCount; ++i) {
            const float n = noise(rng) * 600.0f * strength;
            for (int c = 0; c < ch; ++c) {
                const int idx = i * channels + c;
                float x = samples[idx];
                // one-pole high-pass
                f.lp1[c] += hpA * (x - f.lp1[c]);
                float hp = x - f.lp1[c];
                // two one-pole low-passes
                f.lp2[c] += lpA * (hp - f.lp2[c]);
                f.hpOut[c] += lpA * (f.lp2[c] - f.hpOut[c]);
                float y = f.hpOut[c];
                // blend in the effect, then soft clip
                y = x * (1.0f - strength) + y * strength * 1.6f;
                y = 32767.0f * std::tanh(drive * y / 32767.0f) / norm;
                samples[idx] = toShort((y + n) * gain);
            }
        }
        return;
    }

    // Proximity: distance gain from GMod, optional low-pass for walls.
    const float gain = std::min(2.0f, s.gain * snap.masterVolume);
    const bool occluded = s.occlusion > 0.01f;
    // occlusion 0 -> 20 kHz (no effect), 1 -> 500 Hz
    const float cutoff = 20000.0f * std::pow(500.0f / 20000.0f, s.occlusion);
    const float a = onePoleAlpha(cutoff);
    for (int i = 0; i < sampleCount; ++i) {
        for (int c = 0; c < ch; ++c) {
            const int idx = i * channels + c;
            float y = samples[idx];
            if (occluded) {
                f.occ[c] += a * (y - f.occ[c]);
                f.hpIn[c] += a * (f.occ[c] - f.hpIn[c]);
                y = f.hpIn[c];
            } else {
                f.occ[c] = y;
                f.hpIn[c] = y;
            }
            samples[idx] = toShort(y * gain);
        }
    }
}

// --------------------------------------------------------------------------------------------
// Required plugin exports
// --------------------------------------------------------------------------------------------

EXPORT const char* ts3plugin_name() { return "Traitor Voice"; }
EXPORT const char* ts3plugin_version() { return TV_PLUGIN_VERSION_STR; }
EXPORT int ts3plugin_apiVersion() { return TV_PLUGIN_API_VERSION; }
EXPORT const char* ts3plugin_author() { return "KarateWiesel & Traitor Voice contributors"; }
EXPORT const char* ts3plugin_description()
{
    return "Positional voice for Garry's Mod TTT2. Inspired by Gspeak and ACRE 2. "
           "https://github.com/KarateWiesel/traitor-voice";
}
EXPORT void ts3plugin_setFunctionPointers(const struct TS3Functions funcs) { ts3 = funcs; }

EXPORT int ts3plugin_init()
{
    g_shared = tvOpenShared(&g_mapping);
    if (!g_shared) {
        char msg[128];
        snprintf(msg, sizeof(msg), "Traitor Voice: shared memory could not be opened (error %lu)", GetLastError());
        logInfo(msg);
        return 1;  // plugin failed to load
    }
    g_running = true;
    g_worker = std::thread(workerLoop);
    logInfo("Traitor Voice " TV_PLUGIN_VERSION_STR " loaded");
    return 0;
}

EXPORT void ts3plugin_shutdown()
{
    g_running = false;
    if (g_worker.joinable())
        g_worker.join();
    if (g_shared) {
        TvPluginState empty;
        memset(&empty, 0, sizeof(empty));
        tvWrite(&g_shared->plugin, empty);
    }
    tvCloseShared(g_shared, g_mapping);
    g_shared = nullptr;
    g_mapping = nullptr;
}

EXPORT int ts3plugin_requestAutoload() { return 1; }

// --------------------------------------------------------------------------------------------
// Events
// --------------------------------------------------------------------------------------------

EXPORT void ts3plugin_onTalkStatusChangeEvent(uint64 serverConnectionHandlerID, int status, int isReceivedWhisper,
                                              anyID clientID)
{
    std::lock_guard<std::mutex> lock(g_talkMutex);
    if (status == STATUS_TALKING)
        g_talking.insert(clientID);
    else
        g_talking.erase(clientID);
}

EXPORT void ts3plugin_onConnectStatusChangeEvent(uint64 serverConnectionHandlerID, int newStatus,
                                                 unsigned int errorNumber)
{
    if (newStatus == STATUS_DISCONNECTED) {
        std::lock_guard<std::mutex> lock(g_talkMutex);
        g_talking.clear();
    }
}

// TeamSpeak's own distance attenuation is disabled while we are active: GMod computes the gain.
EXPORT void ts3plugin_onCustom3dRolloffCalculationClientEvent(uint64 serverConnectionHandlerID, anyID clientID,
                                                              float distance, float* volume)
{
    std::lock_guard<std::mutex> lock(g_snapMutex);
    if (g_snap.active)
        *volume = 1.0f;
}

EXPORT void ts3plugin_onEditCapturedVoiceDataEvent(uint64 serverConnectionHandlerID, short* samples, int sampleCount,
                                                   int channels, int* edited)
{
    int peak = 0;
    for (int i = 0; i < sampleCount * channels; ++i)
        peak = std::max(peak, std::abs((int)samples[i]));
    const float level = std::min(1.0f, peak / 32767.0f);
    const float prev = g_micLevel.load();
    g_micLevel.store(level > prev ? level : prev * 0.9f + level * 0.1f);
}

EXPORT void ts3plugin_onEditPostProcessVoiceDataEvent(uint64 serverConnectionHandlerID, anyID clientID,
                                                      short* samples, int sampleCount, int channels,
                                                      const unsigned int* channelSpeakerArray,
                                                      unsigned int* channelFillMask)
{
    Snapshot snap;
    SpeakerInfo info;
    bool known = false;
    {
        std::lock_guard<std::mutex> lock(g_snapMutex);
        if (!g_snap.active)
            return;  // not in game: TeamSpeak behaves normally
        snap.active = true;
        snap.muteUnknown = g_snap.muteUnknown;
        snap.masterVolume = g_snap.masterVolume;
        snap.radioVolume = g_snap.radioVolume;
        snap.radioEffect = g_snap.radioEffect;
        auto it = g_snap.speakers.find(clientID);
        if (it != g_snap.speakers.end()) {
            info = it->second;
            known = true;
        }
    }

    const bool silence = known ? ((info.flags & TV_CF_MUTED) != 0 || (info.gain <= 0.0f && !(info.flags & TV_CF_RADIO)))
                               : snap.muteUnknown;
    if (silence) {
        memset(samples, 0, sizeof(short) * (size_t)sampleCount * (size_t)channels);
        return;
    }
    if (!known)
        return;

    std::lock_guard<std::mutex> lock(g_filterMutex);
    processSpeaker(g_filters[clientID], samples, sampleCount, channels, info, snap);
}
