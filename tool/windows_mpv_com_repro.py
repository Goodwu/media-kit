"""Isolate libmpv COM teardown from Dart and the media-kit fork."""
import ctypes as c
import pathlib
import sys
mpv = c.CDLL(str(pathlib.Path("libmpv-2.dll").resolve()))
mpv.mpv_create.restype = c.c_void_p
mpv.mpv_initialize.argtypes = [c.c_void_p]
mpv.mpv_get_property_string.argtypes = [c.c_void_p, c.c_char_p]
mpv.mpv_get_property_string.restype = c.c_void_p
mpv.mpv_free.argtypes = [c.c_void_p]
mpv.mpv_terminate_destroy.argtypes = [c.c_void_p]
ole = c.WinDLL("ole32")
ole.CoIncrementMTAUsage.argtypes = [c.POINTER(c.c_void_p)]
ole.CoIncrementMTAUsage.restype = c.c_long
ole.CoDecrementMTAUsage.argtypes = [c.c_void_p]
ole.CoDecrementMTAUsage.restype = c.c_long
for i in range(3):
    ctx = mpv.mpv_create()
    assert ctx and mpv.mpv_initialize(ctx) >= 0
    devices = mpv.mpv_get_property_string(ctx, b"audio-device-list")
    print("devices", c.string_at(devices) if devices else None, flush=True)
    if devices:
        mpv.mpv_free(devices)
    cookie = c.c_void_p()
    if sys.argv[1] == "mta":
        hr = ole.CoIncrementMTAUsage(c.byref(cookie))
        print("CoIncrementMTAUsage", hr, cookie.value, flush=True)
        assert hr >= 0
    print("terminate", i, flush=True)
    mpv.mpv_terminate_destroy(ctx)
    print("terminated", i, flush=True)
    if cookie.value:
        assert ole.CoDecrementMTAUsage(cookie) >= 0
print("PASS", flush=True)
