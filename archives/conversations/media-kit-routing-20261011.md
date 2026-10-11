# MK-ROUTING-20261011

## Current State

2026-10-12：库最新已推送bd9b9f852949af8980faaad337064a0830c405da的R01a终态中央6110898494：573video+3原macOS专用Linux跳过、298lab及两包严格分析通过，query/实际插件Java、Darwin宿主及OHOS unsigned HAP各成功，完整native/设备验收未完成。App最新1965ba0e6c50316f1a64f6830bb0877d5f84606e（CI03）已推送回读，本地严格分析No issues、211Flutter、bundle、Chrome DOM与实际main_web release构建通过并独立复核；中央6111208521。远端source run38155973408尚在执行，已完成Python job114518915972实际263项通过，artifact11708632336；不虚称远端App整体通过。

CORE-R01b已实现内部创建请求契约统一，范围新hdr_output_contract、Slot/backend.prepareOutput/Session._createController及直接测试，现有Slot类型导出配套contract一行导出。完整vo/topology/requestedHwdec/GPU/EGL/Surface/offscreen身份用于复用，不推导已观察YUV arm。旧初始未知身份重建、失败且清理失败的输出不能偶然ready后复用，publish异常纳入原失败清理。旧测试配置共享SDK边界已发现，私有pubget重解析成功且无tracked lock变化；最终64目标私有SDK测试/全库strict通过，独立critical复审78项/全库strict通过。新增发布失败两例修复前红灯保留，真实carrier夹具已改surfacetexture。日志/tmp/mk-r01b-{final-tests,final-analyze,publication-baseline,review-final-tests,review-final-analyze}.log。检查点及后续CI见docs/plans/core-r01b-handoff-20261012.json；不能据此声称native呈现、实际decoder或完整R01完成。

App1965ba0e+库bd9b9f85 source run38155973408 attempt1已SUCCESS，实际strict零问题、211Flutter/1Chrome/263Python、Web/bundle与10包前后源码绑定/两仓freshness通过，中央终态6111284247。source artifact11709080173/Python11708632336已下载按ID核验。Release Build38155973649整体FAIL，所有平台失败在native/ABI/签名前（cache/兄弟source/旧锁/空tag），其源码子作业通过不表示Release通过。此终态只证明旧bd9向量，不改标R01b新库。

已读取DEVICE最新中央6111018306/6111060791并回应6111090195：P8.4路线/数据空间仅passed_for_vector，NV12/HWC合成证据不等于实体呈现，截图黑不定性生产渲染失败；保留批准FULL shader+range1。native process-global arm与advisory owner由DEVICE登记修复，公共Dart仍CORE唯一集成；旧DV001构建审查不因DV002更正关闭。真实decoder/presenter复核、可执行独立软件catalog、配置闭环、ReleaseCI/native/设备验收仍开放，产品experimental默认false。

### 接手及R01a首次检查点（历史溯源）

CORE继任已登记中央PR4 comment6110756605。唯一三个routing/MK-ROUTING-20261011分支及主草稿PR继续；DEVICE负责原native构建/实机，不新开工作线。干净worktree接续，原checkout dirty均保留。

权威方案为v3，接手入口为docs/plans/media-kit-routing-core-takeover-20261011.md。CORE-F01模型/Session/plan/report和App报告回归均已实现并完成宿主验证，终态6110447335/6110417510只证明库6e7570fc+App569138fa：571video、3原macOS专用Linux跳过、298lab、192App Flutter、同App SHA此前244Python、bundle/来源/新鲜度通过；分析34info，整体未全绿。原planned/pending已归并，不重新实现。

CORE-R01a仅认领hdr_route依赖标签、realizer::_baseLayerConvert、Session::_hwdecDependency及测试。SurfaceTexture请求路径不等于YUV presenter，mismatch不声称decoder/importer根因；输出slot/backend/GPU契约/软件catalog仍后续开放。不改LG像素、owner/ACK/lease/nativeDV/源事实或App默认实验门。

DEVICE DV001仍1095a43，review5483753705/comment6110373174没有新修复。续审6110762843：nm失败误放行、仅QueueFamilyProperties2漏检、正式bundle传播/staging/成员来源未闭环；PR5 cbcc6bb8档案复制符号缺陷，输入表与结果SHA不一致、完整APK/patch/链接来源不足、LYA帧推进缺证。本机JAR三成员及显式NDK读取支持该样本no-op，不证明配方或最新F01/HDR验收。保持未集成，DEVICE在原PR修。

R01a实现已完成：最终hwdec独立SurfaceTexture依赖与Session排除，双门成功copy及二次失败有界测试；50关联用例通过，严格分析无问题，V1独立审核无阻塞，独立92关联用例通过。源码CI/App最新组合未验收，记录见docs/plans/core-r01a-handoff-20261011.json。

下一步：独立审核后及时commit/push/readback、当前源码CI；随后输出身份/decoder复核及可执行独立替代，真实选项闭环、34info和Release CI。构建开始固定最新适用输入，期间不pull；旧向量不重标新SHA。

## History

- 2026-10-11：全文读取takeover/v3/中央App台账/F01/CI02/最终评论及DEVICE最新认领；中央登记接手与文件范围6110756605、续审6110762843。CORE-R01a已派发worker，DEVICE配方保持其所有权。
