# Matched thermal B1：GPU热限制触发，已中止

- 同ab4 APK、policy1/display-resample、本地原片0起播。B初电池32.3°C/VTS35.3°C，A初32.3/35.5，满足各≤0.5°C。
- Android AC/USB/status及sysfs Full/usb_online匹配；电池V/I原值持续保留，未用于推算GPU功率。
- 本轮出现KGSL `thermal_pwrlevel=4`、`max_gpuclk=401800000`，而近匹配前为0/652800000。即使panel thermald_status仍0，该证据也不能被panel0覆盖。
- Lead据此要求立即停止；向核验过命令的host PID39814发送SIGINT并进入reviewed finally。停止原因记为`fresh-gpu-thermal-cap-detected`，status=aborted、completeWindow=false。
- 原controller reason=interrupted-by-user保存在summary.controller-original.json及external-stop.json；不抹去原始控制流。instant汇总已明确diagnosticOnly/validCompletedProfile=false。
- hdr_lab已停止，设置/属性/原屏幕状态恢复验证通过；restoreErrors为空。未追加任何播放轮次。
- 最后运行样本及runtime/native计数见external-stop.json；约120秒live caps见caps-live.txt，停止后真实caps/供电/传感器另见post-stop-caps-supply.json，二者时间明确区分。
- **本轮不是完整6分钟热态结果，不能宣称降热成功；A起始/热态cap取证缺口及不同限频轨迹使因果比较受限。候选不得据此生产启用。**
