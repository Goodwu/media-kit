cmake_minimum_required(VERSION 3.22.1)
project(media_kit_dataspace_vendor)

# Vendor dataspace apply path only (perform op 19 + readback verification).
# No diagnostics probes: those stay in the hdr_lab test app.
# A4 module split: dataspace_apply.cpp keeps the generic entry channel (LYA
# path + JNI registrations); lg_fw_adapter.cpp is the LG firmware metadata
# adapter it delegates to. Exported symbol names and behavior are unchanged.
add_library(media_kit_dataspace_vendor SHARED dataspace_apply.cpp lg_fw_adapter.cpp)

find_library(android-lib android)
find_library(dl-lib dl)
find_library(log-lib log)
find_library(egl-lib EGL)

target_link_libraries(media_kit_dataspace_vendor ${android-lib} ${dl-lib} ${log-lib} ${egl-lib})
