echo @@gpu_thermal_pwrlevel
cat /sys/class/kgsl/kgsl-3d0/thermal_pwrlevel
echo @@battery_temp
cat /sys/class/thermal/thermal_zone30/temp
echo @@vts_temp
cat /sys/class/thermal/thermal_zone39/temp
echo @@settings
settings get system screen_brightness_mode
settings get system screen_brightness
settings get system accelerometer_rotation
settings get system user_rotation
settings get system screen_off_timeout
echo @@panel_hdr
cat /sys/devices/virtual/panel/img_tune/hdr_mode
echo @@gpu_max_gpuclk
cat /sys/class/kgsl/kgsl-3d0/max_gpuclk
echo @@cpu2cap
cat /sys/devices/system/cpu/cpu2/cpufreq/scaling_max_freq
echo @@power
dumpsys power
