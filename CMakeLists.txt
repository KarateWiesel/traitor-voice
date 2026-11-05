cmake_minimum_required(VERSION 3.20)
project(traitor_voice VERSION 0.1.0 LANGUAGES CXX)

if(NOT WIN32)
  message(FATAL_ERROR "Traitor Voice client components are Windows-only for now.")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# Static runtime: players do not need the Visual C++ Redistributable.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

include(FetchContent)
# Third-party headers are downloaded at configure time (not redistributed in this repo).
FetchContent_Declare(ts3sdk
  GIT_REPOSITORY https://github.com/TeamSpeak-Systems/ts3client-pluginsdk.git
  GIT_TAG 4aa90a53aa150cbf81e13bc97e68c0431b26499f)
FetchContent_Declare(gmodbase
  GIT_REPOSITORY https://github.com/Facepunch/gmod-module-base.git
  GIT_TAG 4fdafe7d762fe63f0360c67d9e119a129292712e)
FetchContent_MakeAvailable(ts3sdk gmodbase)

if(CMAKE_SIZEOF_VOID_P EQUAL 8)
  set(TV_ARCH win64)
else()
  set(TV_ARCH win32)
endif()

# --- GMod client module: gmcl_traitorvoice_win32.dll / gmcl_traitorvoice_win64.dll ---
add_library(gmcl_traitorvoice SHARED module/gmcl_traitorvoice.cpp)
target_include_directories(gmcl_traitorvoice PRIVATE shared ${gmodbase_SOURCE_DIR}/include)
set_target_properties(gmcl_traitorvoice PROPERTIES OUTPUT_NAME "gmcl_traitorvoice_${TV_ARCH}" PREFIX "")

# --- TeamSpeak 3 plugin: traitorvoice_win32.dll / traitorvoice_win64.dll ---
add_library(traitorvoice_ts3 SHARED ts3plugin/traitorvoice_plugin.cpp)
target_include_directories(traitorvoice_ts3 PRIVATE shared ${ts3sdk_SOURCE_DIR}/include)
set_target_properties(traitorvoice_ts3 PROPERTIES OUTPUT_NAME "traitorvoice_${TV_ARCH}" PREFIX "")

foreach(t gmcl_traitorvoice traitorvoice_ts3)
  target_compile_definitions(${t} PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS)
  if(MSVC)
    target_compile_options(${t} PRIVATE /W4 /permissive-)
  endif()
endforeach()
