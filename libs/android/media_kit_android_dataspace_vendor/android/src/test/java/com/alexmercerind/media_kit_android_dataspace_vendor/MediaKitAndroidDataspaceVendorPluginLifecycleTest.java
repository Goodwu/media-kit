package com.alexmercerind.media_kit_android_dataspace_vendor;
import static org.junit.Assert.*;
import org.junit.After;
import org.junit.Test;

import java.nio.ByteBuffer;
import java.util.concurrent.atomic.AtomicInteger;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.StandardMessageCodec;

/**
 * Process-level lifecycle of the vendor plugin (V2 round 4, R3-2): the
 * generated registrant constructs ONE plugin instance PER ENGINE, so two
 * instances with two messengers drive the real {@code attachChannel} /
 * {@code detachChannel} lifecycle seams here. The assertions pin the
 * process-singleton contract: one instance's detach must NOT reset the
 * process gate while another engine is still attached, and every instance
 * records a distinct engine id (participant metadata for the write lease).
 *
 * <p>Honest scope: the device-gated EXTENSION registration
 * ({@code Build}/{@code Log}-dependent) is Android-runtime behavior and is
 * covered by the static-singleton structure plus device rounds, not by this
 * JVM harness.</p>
 */
public class MediaKitAndroidDataspaceVendorPluginLifecycleTest {
 @After public void reset() {
  MediaKitAndroidDataspaceVendorPlugin.resetForTesting();
 }

 /** Encodes and decodes through the REAL codec (write mode → flip → read). */
 private static Object decode(Object message) {
  final ByteBuffer buffer = StandardMessageCodec.INSTANCE.encodeMessage(message);
  buffer.flip();
  return StandardMessageCodec.INSTANCE.decodeMessage(buffer);
 }

 /** Captures the handler's reply without a real channel. */
 private static final class CapturingResult
         implements io.flutter.plugin.common.MethodChannel.Result {
  Object value;
  @Override public void success(Object result) { value = result; }
  @Override public void error(String code, String message, Object details) {
   throw new IllegalStateException(code + ": " + message);
  }
  @Override public void notImplemented() {
   throw new IllegalStateException("notImplemented");
  }
 }

 /** Minimal JVM-safe messenger; the lifecycle seams never invoke it. */
 private static final class FakeMessenger implements BinaryMessenger {
  final String name;
  final AtomicInteger handlers = new AtomicInteger();
  FakeMessenger(String name) { this.name = name; }
  @Override public void send(String channel, ByteBuffer message) { }
  @Override public void send(String channel, ByteBuffer message,
      BinaryMessenger.BinaryReply callback) { }
  @Override public void setMessageHandler(String channel,
      BinaryMessenger.BinaryMessageHandler handler) {
   if (handler != null) handlers.incrementAndGet();
  }
 }

 @Test public void oneInstanceDetachingDoesNotResetTheProcessGate() {
  final MediaKitAndroidDataspaceVendorPlugin engineA =
          new MediaKitAndroidDataspaceVendorPlugin();
  final MediaKitAndroidDataspaceVendorPlugin engineB =
          new MediaKitAndroidDataspaceVendorPlugin();
  final FakeMessenger messengerA = new FakeMessenger("engine-a");
  final FakeMessenger messengerB = new FakeMessenger("engine-b");
  engineA.attachChannel(messengerA);
  engineB.attachChannel(messengerB);
  assertEquals(2, MediaKitAndroidDataspaceVendorPlugin.boundEngineCount());

  // A YUV write lease is live while engine A detaches.
  assertTrue(ProcessOutputInitGate.beginWrite(11L, engineA.engineId(), 0L) > 0);
  assertFalse(engineA.detachChannel(messengerA));
  assertEquals(1, MediaKitAndroidDataspaceVendorPlugin.boundEngineCount());
  assertTrue(ProcessOutputInitGate.writerHeld());
  // Engine B still reads a live gate: its read admission is still rejected.
  assertFalse(ProcessOutputInitGate.beginRead());

  // The LAST engine detaching is the only reset authorization.
  assertTrue(engineB.detachChannel(messengerB));
  assertEquals(0, MediaKitAndroidDataspaceVendorPlugin.boundEngineCount());
  ProcessOutputInitGate.reset();  // What onDetachedFromEngine performs then.
  assertFalse(ProcessOutputInitGate.writerHeld());
  assertTrue(ProcessOutputInitGate.beginRead());
 }

 @Test public void pluginInstancesCarryDistinctEngineIds() {
  final MediaKitAndroidDataspaceVendorPlugin a =
          new MediaKitAndroidDataspaceVendorPlugin();
  final MediaKitAndroidDataspaceVendorPlugin b =
          new MediaKitAndroidDataspaceVendorPlugin();
  assertNotEquals(a.engineId(), b.engineId());
 }

 @Test public void reattachingAnEngineKeepsItsChannelsUnique() {
  final MediaKitAndroidDataspaceVendorPlugin engine =
          new MediaKitAndroidDataspaceVendorPlugin();
  final FakeMessenger messenger = new FakeMessenger("engine-a");
  engine.attachChannel(messenger);
  engine.attachChannel(messenger);  // Idempotent re-attach of the same engine.
  assertEquals(1, MediaKitAndroidDataspaceVendorPlugin.boundEngineCount());
  assertTrue(engine.detachChannel(messenger));
  assertEquals(0, MediaKitAndroidDataspaceVendorPlugin.boundEngineCount());
 }

 /**
  * V2 round 4 regression (real-codec shape): the Dart side's small ints
  * cross the channel as java.lang.Integer — the handler previously read
  * {@code leaseId} with a direct {@code (Long)} cast, which threw
  * {@code Integer cannot be cast to Long} on EVERY first YUV begin
  * (leaseId = 0). The arguments here are built through the REAL
  * {@link StandardMessageCodec} (encode int32 → decode Integer), and the
  * private handler is driven reflectively with the plugin's own
  * {@link io.flutter.plugin.common.MethodChannel.Result} semantics.
  */
 @Test public void integerShapedLeaseIdArgumentsDoNotThrow() throws Exception {
  final MediaKitAndroidDataspaceVendorPlugin plugin =
          new MediaKitAndroidDataspaceVendorPlugin();
  final java.lang.reflect.Method handler =
          MediaKitAndroidDataspaceVendorPlugin.class.getDeclaredMethod(
                  "onYuvDiagMethodCall",
                  io.flutter.plugin.common.MethodCall.class,
                  io.flutter.plugin.common.MethodChannel.Result.class);
  handler.setAccessible(true);

  // The Dart-side first-begin shape: leaseId is the Dart int 0, encoded
  // by the real codec as int32 and decoded on Java as Integer.
  final Object beginArguments = decode(
          new java.util.HashMap<String, Object>() {{
            put("ownerToken", "owner-a");
            put("leaseId", 0);
          }});
  assertTrue(beginArguments instanceof java.util.Map);
  assertTrue(((java.util.Map<?, ?>) beginArguments).get("leaseId")
          instanceof Integer);

  final CapturingResult beginResult = new CapturingResult();
  handler.invoke(plugin,
          new io.flutter.plugin.common.MethodCall(
                  "BeginOutputInitWrite", beginArguments),
          beginResult);
  assertTrue(beginResult.value instanceof Number);
  final long lease = ((Number) beginResult.value).longValue();
  assertTrue(lease > 0);
  assertTrue(ProcessOutputInitGate.writerHeld());
  assertEquals(lease, ProcessOutputInitGate.writerLease());

  // The lease echoed back by Dart is again a small int (Integer shape).
  final Object endArguments = decode(
          new java.util.HashMap<String, Object>() {{
            put("ownerToken", "owner-a");
            put("leaseId", (int) lease);
          }});
  assertTrue(((java.util.Map<?, ?>) endArguments).get("leaseId")
          instanceof Integer);
  final CapturingResult endResult = new CapturingResult();
  handler.invoke(plugin,
          new io.flutter.plugin.common.MethodCall(
                  "EndOutputInitWrite", endArguments),
          endResult);
  assertEquals(Boolean.TRUE, endResult.value);
  assertFalse(ProcessOutputInitGate.writerHeld());
 }
}
