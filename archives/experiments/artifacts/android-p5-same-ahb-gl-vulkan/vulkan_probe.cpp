#include <jni.h>
#include <android/hardware_buffer.h>
#include <android/hardware_buffer_jni.h>
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_android.h>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

#ifndef VK_PROBE_FULL_RANGE
#define VK_PROBE_FULL_RANGE 0
#endif

static std::string sampleImage(VkPhysicalDevice gpu, VkDevice device,
                               uint32_t queue_index, VkImage image,
                               VkSamplerYcbcrConversion conversion,
                               uint32_t width, uint32_t height) {
  VkSampler sampler = VK_NULL_HANDLE;
  VkImageView view = VK_NULL_HANDLE;
  VkBuffer output = VK_NULL_HANDLE;
  VkDeviceMemory output_memory = VK_NULL_HANDLE;
  VkDescriptorSetLayout set_layout = VK_NULL_HANDLE;
  VkDescriptorPool pool = VK_NULL_HANDLE;
  VkPipelineLayout pipeline_layout = VK_NULL_HANDLE;
  VkShaderModule shader = VK_NULL_HANDLE;
  VkPipeline pipeline = VK_NULL_HANDLE;
  VkCommandPool command_pool = VK_NULL_HANDLE;
  std::string status;
  VkResult result = VK_SUCCESS;
  auto work = [&]() {
    VkSamplerYcbcrConversionInfo conversion_ref{
        VK_STRUCTURE_TYPE_SAMPLER_YCBCR_CONVERSION_INFO};
    conversion_ref.conversion = conversion;
    VkSamplerCreateInfo sampler_info{VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
    sampler_info.pNext = &conversion_ref;
    sampler_info.magFilter = VK_FILTER_NEAREST;
    sampler_info.minFilter = VK_FILTER_NEAREST;
    sampler_info.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;
    sampler_info.addressModeU = sampler_info.addressModeV =
        sampler_info.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    sampler_info.maxLod = 0;
    result = vkCreateSampler(device, &sampler_info, nullptr, &sampler);
    if (result) { status = "createSampler=" + std::to_string(result); return; }
    VkImageViewCreateInfo view_info{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    view_info.pNext = &conversion_ref;
    view_info.image = image;
    view_info.viewType = VK_IMAGE_VIEW_TYPE_2D;
    view_info.format = VK_FORMAT_UNDEFINED;
    view_info.components = {VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY,
                            VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY};
    view_info.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    result = vkCreateImageView(device, &view_info, nullptr, &view);
    if (result) { status = "createImageView=" + std::to_string(result); return; }
    VkBufferCreateInfo buffer_info{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    buffer_info.size = 10 * 4 * sizeof(float);
    buffer_info.usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
    buffer_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    result = vkCreateBuffer(device, &buffer_info, nullptr, &output);
    if (result) { status = "createBuffer=" + std::to_string(result); return; }
    VkMemoryRequirements req{};
    vkGetBufferMemoryRequirements(device, output, &req);
    VkPhysicalDeviceMemoryProperties mem_props{};
    vkGetPhysicalDeviceMemoryProperties(gpu, &mem_props);
    uint32_t type = mem_props.memoryTypeCount;
    for (uint32_t i = 0; i < mem_props.memoryTypeCount; ++i) {
      if ((req.memoryTypeBits & (1u << i)) &&
          (mem_props.memoryTypes[i].propertyFlags &
           (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) ==
              (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {
        type = i; break;
      }
    }
    if (type == mem_props.memoryTypeCount) { status = "noCoherentMemory"; return; }
    VkMemoryAllocateInfo alloc{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    alloc.allocationSize = req.size;
    alloc.memoryTypeIndex = type;
    result = vkAllocateMemory(device, &alloc, nullptr, &output_memory);
    if (result) { status = "allocateOutput=" + std::to_string(result); return; }
    result = vkBindBufferMemory(device, output, output_memory, 0);
    if (result) { status = "bindOutput=" + std::to_string(result); return; }
    void *mapped = nullptr;
    result = vkMapMemory(device, output_memory, 0, req.size, 0, &mapped);
    if (result) { status = "mapOutput=" + std::to_string(result); return; }
    std::memset(mapped, 0xCD, 10 * 4 * sizeof(float));
    vkUnmapMemory(device, output_memory);
    VkDescriptorSetLayoutBinding bindings[2]{};
    bindings[0].binding = 0;
    bindings[0].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    bindings[0].descriptorCount = 1;
    bindings[0].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
    bindings[0].pImmutableSamplers = &sampler;
    bindings[1].binding = 1;
    bindings[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    bindings[1].descriptorCount = 1;
    bindings[1].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
    VkDescriptorSetLayoutCreateInfo layout_info{
        VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    layout_info.bindingCount = 2;
    layout_info.pBindings = bindings;
    result = vkCreateDescriptorSetLayout(device, &layout_info, nullptr, &set_layout);
    if (result) { status = "createSetLayout=" + std::to_string(result); return; }
    VkDescriptorPoolSize sizes[2] = {{VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 8},
                                     {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1}};
    VkDescriptorPoolCreateInfo pool_info{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    pool_info.maxSets = 1;
    pool_info.poolSizeCount = 2;
    pool_info.pPoolSizes = sizes;
    result = vkCreateDescriptorPool(device, &pool_info, nullptr, &pool);
    if (result) { status = "createPool=" + std::to_string(result); return; }
    VkDescriptorSetAllocateInfo set_alloc{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
    set_alloc.descriptorPool = pool;
    set_alloc.descriptorSetCount = 1;
    set_alloc.pSetLayouts = &set_layout;
    VkDescriptorSet set = VK_NULL_HANDLE;
    result = vkAllocateDescriptorSets(device, &set_alloc, &set);
    if (result) { status = "allocateSet=" + std::to_string(result); return; }
    VkDescriptorImageInfo image_descriptor{sampler, view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
    VkDescriptorBufferInfo output_descriptor{output, 0, VK_WHOLE_SIZE};
    VkWriteDescriptorSet writes[2]{};
    for (auto &write : writes) write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    writes[0].dstSet = set;
    writes[0].dstBinding = 0;
    writes[0].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    writes[0].descriptorCount = 1;
    writes[0].pImageInfo = &image_descriptor;
    writes[1].dstSet = set;
    writes[1].dstBinding = 1;
    writes[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    writes[1].descriptorCount = 1;
    writes[1].pBufferInfo = &output_descriptor;
    vkUpdateDescriptorSets(device, 2, writes, 0, nullptr);
    VkPushConstantRange push{VK_SHADER_STAGE_COMPUTE_BIT, 0, 2 * sizeof(int)};
    VkPipelineLayoutCreateInfo pipeline_layout_info{
        VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    pipeline_layout_info.setLayoutCount = 1;
    pipeline_layout_info.pSetLayouts = &set_layout;
    pipeline_layout_info.pushConstantRangeCount = 1;
    pipeline_layout_info.pPushConstantRanges = &push;
    result = vkCreatePipelineLayout(device, &pipeline_layout_info, nullptr, &pipeline_layout);
    if (result) { status = "createPipelineLayout=" + std::to_string(result); return; }
    std::ifstream file("/data/local/tmp/media-kit-vk-sample.spv", std::ios::binary);
    if (!file) { status = "shaderMissing"; return; }
    std::vector<char> code((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    if (code.empty() || code.size() % 4) { status = "shaderInvalid"; return; }
    VkShaderModuleCreateInfo shader_info{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    shader_info.codeSize = code.size();
    shader_info.pCode = reinterpret_cast<const uint32_t *>(code.data());
    result = vkCreateShaderModule(device, &shader_info, nullptr, &shader);
    if (result) { status = "createShader=" + std::to_string(result); return; }
    VkComputePipelineCreateInfo pipeline_info{VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO};
    pipeline_info.stage = {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO};
    pipeline_info.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    pipeline_info.stage.module = shader;
    pipeline_info.stage.pName = "main";
    pipeline_info.layout = pipeline_layout;
    result = vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &pipeline_info, nullptr, &pipeline);
    if (result) { status = "createPipeline=" + std::to_string(result); return; }
    VkCommandPoolCreateInfo command_pool_info{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    command_pool_info.queueFamilyIndex = queue_index;
    result = vkCreateCommandPool(device, &command_pool_info, nullptr, &command_pool);
    if (result) { status = "createCommandPool=" + std::to_string(result); return; }
    VkCommandBufferAllocateInfo command_alloc{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    command_alloc.commandPool = command_pool;
    command_alloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    command_alloc.commandBufferCount = 1;
    VkCommandBuffer command = VK_NULL_HANDLE;
    result = vkAllocateCommandBuffers(device, &command_alloc, &command);
    if (result) { status = "allocateCommand=" + std::to_string(result); return; }
    VkCommandBufferBeginInfo begin{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    result = vkBeginCommandBuffer(command, &begin);
    if (result) { status = "beginCommand=" + std::to_string(result); return; }
    VkImageMemoryBarrier image_barrier{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    image_barrier.srcAccessMask = 0;
    image_barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
    image_barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    image_barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    image_barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_EXTERNAL;
    image_barrier.dstQueueFamilyIndex = queue_index;
    image_barrier.image = image;
    image_barrier.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                         VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0,
                         0, nullptr, 0, nullptr, 1, &image_barrier);
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline_layout,
                            0, 1, &set, 0, nullptr);
    int dimensions[2] = {static_cast<int>(width), static_cast<int>(height)};
    vkCmdPushConstants(command, pipeline_layout, VK_SHADER_STAGE_COMPUTE_BIT,
                       0, sizeof(dimensions), dimensions);
    vkCmdDispatch(command, 10, 1, 1);
    VkBufferMemoryBarrier output_barrier{VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER};
    output_barrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    output_barrier.dstAccessMask = VK_ACCESS_HOST_READ_BIT;
    output_barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    output_barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    output_barrier.buffer = output;
    output_barrier.offset = 0;
    output_barrier.size = VK_WHOLE_SIZE;
    vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                         VK_PIPELINE_STAGE_HOST_BIT, 0, 0, nullptr,
                         1, &output_barrier, 0, nullptr);
    result = vkEndCommandBuffer(command);
    if (result) { status = "endCommand=" + std::to_string(result); return; }
    VkQueue queue = VK_NULL_HANDLE;
    vkGetDeviceQueue(device, queue_index, 0, &queue);
    VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &command;
    result = vkQueueSubmit(queue, 1, &submit, VK_NULL_HANDLE);
    if (result) { status = "queueSubmit=" + std::to_string(result); return; }
    result = vkQueueWaitIdle(queue);
    if (result) { status = "queueWait=" + std::to_string(result); return; }
    result = vkMapMemory(device, output_memory, 0, req.size, 0, &mapped);
    if (result) { status = "readMap=" + std::to_string(result); return; }
    const float *values = static_cast<const float *>(mapped);
    char buf[128];
    status = "samples=";
    for (int j = 0; j < 10; ++j) {
      std::snprintf(buf, sizeof(buf), "%d:(%.9f,%.9f,%.9f,%.9f);",
                    j, values[4*j], values[4*j+1], values[4*j+2], values[4*j+3]);
      status += buf;
    }
    vkUnmapMemory(device, output_memory);
  };
  work();
  if (command_pool) vkDestroyCommandPool(device, command_pool, nullptr);
  if (pipeline) vkDestroyPipeline(device, pipeline, nullptr);
  if (shader) vkDestroyShaderModule(device, shader, nullptr);
  if (pipeline_layout) vkDestroyPipelineLayout(device, pipeline_layout, nullptr);
  if (pool) vkDestroyDescriptorPool(device, pool, nullptr);
  if (set_layout) vkDestroyDescriptorSetLayout(device, set_layout, nullptr);
  if (output) vkDestroyBuffer(device, output, nullptr);
  if (output_memory) vkFreeMemory(device, output_memory, nullptr);
  if (view) vkDestroyImageView(device, view, nullptr);
  if (sampler) vkDestroySampler(device, sampler, nullptr);
  return status;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_media_1kit_1test_P5CodecProbe_inspectVulkanImport(
    JNIEnv *env, jclass, jobject hardware_buffer, jint, jint, jint, jint) {
  AHardwareBuffer *buffer = AHardwareBuffer_fromHardwareBuffer(env, hardware_buffer);
  AHardwareBuffer_Desc desc{};
  AHardwareBuffer_describe(buffer, &desc);
  std::string out = "AHB format=" + std::to_string(desc.format) +
      " usage=" + std::to_string(desc.usage) +
      " size=" + std::to_string(desc.width) + "x" + std::to_string(desc.height);
  VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
  app.apiVersion = VK_API_VERSION_1_1;
  VkInstanceCreateInfo ici{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
  ici.pApplicationInfo = &app;
  VkInstance instance = VK_NULL_HANDLE;
  VkResult result = vkCreateInstance(&ici, nullptr, &instance);
  if (result != VK_SUCCESS) return env->NewStringUTF((out + " createInstance=" + std::to_string(result)).c_str());
  uint32_t gpu_count = 0;
  result = vkEnumeratePhysicalDevices(instance, &gpu_count, nullptr);
  if (result != VK_SUCCESS || !gpu_count) {
    out += " enumerateGPUs=" + std::to_string(result) + " count=" + std::to_string(gpu_count);
    vkDestroyInstance(instance, nullptr);
    return env->NewStringUTF(out.c_str());
  }
  std::vector<VkPhysicalDevice> gpus(gpu_count);
  vkEnumeratePhysicalDevices(instance, &gpu_count, gpus.data());
  for (uint32_t i = 0; i < gpu_count; ++i) {
    VkPhysicalDeviceProperties gp{};
    vkGetPhysicalDeviceProperties(gpus[i], &gp);
    out += " GPU[" + std::to_string(i) + "]=" + gp.deviceName +
        " api=" + std::to_string(gp.apiVersion);
    uint32_t ext_count = 0;
    vkEnumerateDeviceExtensionProperties(gpus[i], nullptr, &ext_count, nullptr);
    std::vector<VkExtensionProperties> extensions(ext_count);
    vkEnumerateDeviceExtensionProperties(gpus[i], nullptr, &ext_count, extensions.data());
    bool ahb_ext = false;
    for (const auto &ext : extensions)
      if (std::string(ext.extensionName) == VK_ANDROID_EXTERNAL_MEMORY_ANDROID_HARDWARE_BUFFER_EXTENSION_NAME) ahb_ext = true;
    out += " AHBext=" + std::to_string(ahb_ext);
    if (!ahb_ext) continue;
    uint32_t queue_count = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(gpus[i], &queue_count, nullptr);
    std::vector<VkQueueFamilyProperties> queues(queue_count);
    vkGetPhysicalDeviceQueueFamilyProperties(gpus[i], &queue_count, queues.data());
    uint32_t queue_index = queue_count;
    for (uint32_t q = 0; q < queue_count; ++q)
      if (queues[q].queueCount && (queues[q].queueFlags & VK_QUEUE_GRAPHICS_BIT)) { queue_index = q; break; }
    if (queue_index == queue_count) { out += " noGraphicsQueue"; continue; }
    float priority = 1.0f;
    VkDeviceQueueCreateInfo qci{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    qci.queueFamilyIndex = queue_index;
    qci.queueCount = 1;
    qci.pQueuePriorities = &priority;
    const char *names[] = {VK_ANDROID_EXTERNAL_MEMORY_ANDROID_HARDWARE_BUFFER_EXTENSION_NAME};
    VkPhysicalDeviceSamplerYcbcrConversionFeatures ycbcr{
        VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SAMPLER_YCBCR_CONVERSION_FEATURES};
    VkPhysicalDeviceFeatures2 features{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2};
    features.pNext = &ycbcr;
    vkGetPhysicalDeviceFeatures2(gpus[i], &features);
    out += " samplerYcbcrConversion=" + std::to_string(ycbcr.samplerYcbcrConversion);
    if (!ycbcr.samplerYcbcrConversion) continue;
    VkDeviceCreateInfo dci{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    dci.pNext = &features;
    dci.queueCreateInfoCount = 1;
    dci.pQueueCreateInfos = &qci;
    dci.enabledExtensionCount = 1;
    dci.ppEnabledExtensionNames = names;
    VkDevice device = VK_NULL_HANDLE;
    result = vkCreateDevice(gpus[i], &dci, nullptr, &device);
    if (result != VK_SUCCESS) { out += " createDevice=" + std::to_string(result); continue; }
    auto get = reinterpret_cast<PFN_vkGetAndroidHardwareBufferPropertiesANDROID>(
        vkGetDeviceProcAddr(device, "vkGetAndroidHardwareBufferPropertiesANDROID"));
    if (!get) { out += " missingProc"; vkDestroyDevice(device, nullptr); continue; }
    VkAndroidHardwareBufferFormatPropertiesANDROID fmt{
        VK_STRUCTURE_TYPE_ANDROID_HARDWARE_BUFFER_FORMAT_PROPERTIES_ANDROID};
    VkAndroidHardwareBufferPropertiesANDROID props{
        VK_STRUCTURE_TYPE_ANDROID_HARDWARE_BUFFER_PROPERTIES_ANDROID};
    props.pNext = &fmt;
    result = get(device, buffer, &props);
    out += " query=" + std::to_string(result);
    if (result == VK_SUCCESS) {
      out += " vkFormat=" + std::to_string(fmt.format) +
          " externalFormat=" + std::to_string(fmt.externalFormat) +
          " features=" + std::to_string(fmt.formatFeatures) +
          " model=" + std::to_string(fmt.suggestedYcbcrModel) +
          " range=" + std::to_string(fmt.suggestedYcbcrRange) +
          " xChroma=" + std::to_string(fmt.suggestedXChromaOffset) +
          " yChroma=" + std::to_string(fmt.suggestedYChromaOffset) +
          " components=" + std::to_string(fmt.samplerYcbcrConversionComponents.r) + "," +
              std::to_string(fmt.samplerYcbcrConversionComponents.g) + "," +
              std::to_string(fmt.samplerYcbcrConversionComponents.b) + "," +
              std::to_string(fmt.samplerYcbcrConversionComponents.a) +
          " allocSize=" + std::to_string(props.allocationSize) +
          " memoryTypeBits=" + std::to_string(props.memoryTypeBits);
      VkExternalFormatANDROID external{VK_STRUCTURE_TYPE_EXTERNAL_FORMAT_ANDROID};
      external.externalFormat = fmt.externalFormat;
      VkSamplerYcbcrConversionCreateInfo conversion_info{
          VK_STRUCTURE_TYPE_SAMPLER_YCBCR_CONVERSION_CREATE_INFO};
      conversion_info.pNext = &external;
      conversion_info.format = fmt.format;
      conversion_info.ycbcrModel = VK_SAMPLER_YCBCR_MODEL_CONVERSION_YCBCR_IDENTITY;
      conversion_info.ycbcrRange = VK_PROBE_FULL_RANGE ?
          VK_SAMPLER_YCBCR_RANGE_ITU_FULL : fmt.suggestedYcbcrRange;
      conversion_info.components = fmt.samplerYcbcrConversionComponents;
      conversion_info.xChromaOffset = fmt.suggestedXChromaOffset;
      conversion_info.yChromaOffset = fmt.suggestedYChromaOffset;
      conversion_info.chromaFilter = VK_FILTER_NEAREST;
      VkSamplerYcbcrConversion conversion = VK_NULL_HANDLE;
      result = vkCreateSamplerYcbcrConversion(device, &conversion_info, nullptr, &conversion);
      out += " createIdentityConversion=" + std::to_string(result);
      out += " requestedRange=" + std::to_string(conversion_info.ycbcrRange);
      if (result == VK_SUCCESS) {
        VkExternalMemoryImageCreateInfo memory_image{
            VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO};
        memory_image.handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_ANDROID_HARDWARE_BUFFER_BIT_ANDROID;
        external.pNext = &memory_image;
        VkImageCreateInfo image_info{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
        image_info.pNext = &external;
        image_info.imageType = VK_IMAGE_TYPE_2D;
        image_info.format = fmt.format;
        image_info.extent = {desc.width, desc.height, 1};
        image_info.mipLevels = 1;
        image_info.arrayLayers = 1;
        image_info.samples = VK_SAMPLE_COUNT_1_BIT;
        image_info.tiling = VK_IMAGE_TILING_OPTIMAL;
        image_info.usage = VK_IMAGE_USAGE_SAMPLED_BIT;
        image_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
        image_info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        VkImage image = VK_NULL_HANDLE;
        result = vkCreateImage(device, &image_info, nullptr, &image);
        out += " createImage=" + std::to_string(result);
        if (result == VK_SUCCESS) {
          VkDeviceMemory memory = VK_NULL_HANDLE;
          VkMemoryRequirements requirements{};
          vkGetImageMemoryRequirements(device, image, &requirements);
          out += " imageMemoryBits=" + std::to_string(requirements.memoryTypeBits);
          uint32_t bits = props.memoryTypeBits & requirements.memoryTypeBits;
          if (bits) {
            uint32_t memory_index = 0;
            while (!(bits & (1u << memory_index))) ++memory_index;
            VkImportAndroidHardwareBufferInfoANDROID import{
                VK_STRUCTURE_TYPE_IMPORT_ANDROID_HARDWARE_BUFFER_INFO_ANDROID};
            import.buffer = buffer;
            VkMemoryDedicatedAllocateInfo dedicated{
                VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO};
            import.pNext = &dedicated;
            dedicated.image = image;
            VkMemoryAllocateInfo alloc{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
            alloc.pNext = &import;
            alloc.allocationSize = props.allocationSize;
            alloc.memoryTypeIndex = memory_index;
            result = vkAllocateMemory(device, &alloc, nullptr, &memory);
            out += " importMemory=" + std::to_string(result);
            if (result == VK_SUCCESS) {
              result = vkBindImageMemory(device, image, memory, 0);
              out += " bindImage=" + std::to_string(result);
              if (result == VK_SUCCESS)
                out += " " + sampleImage(gpus[i], device, queue_index, image,
                                          conversion, desc.width, desc.height);
            }
          } else out += " noCommonMemoryType";
          vkDestroyImage(device, image, nullptr);
          if (memory != VK_NULL_HANDLE) vkFreeMemory(device, memory, nullptr);
        }
        vkDestroySamplerYcbcrConversion(device, conversion, nullptr);
      }
    }
    vkDestroyDevice(device, nullptr);
  }
  vkDestroyInstance(instance, nullptr);
  return env->NewStringUTF(out.c_str());
}
