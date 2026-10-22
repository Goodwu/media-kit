# Technical / Architecture Preferences

- Prefers hardware-direct HDR output over tone-mapping whenever the device supports it; tone-mapping is only a fallback and should never be the default when direct output is possible. Confidence: 0.85
- Wants a generic, config-driven decision capability (decide by input profile/capability configuration) instead of hardcoded per-device or per-profile special cases. Confidence: 0.8
- Clear separation of responsibilities: the low-level library/kit only reports capabilities, routing info and events; the app layer owns policy (whether to request an HDR source, when to switch sources). Confidence: 0.85
- Expects fallback playback (e.g. tone-mapped playback) not to be force-stopped by the library — the app decides when to switch. Confidence: 0.75
- Values consistency between the requested video source and the device's actual HDR display capability; mismatches should be reported, not silently handled. Confidence: 0.7
