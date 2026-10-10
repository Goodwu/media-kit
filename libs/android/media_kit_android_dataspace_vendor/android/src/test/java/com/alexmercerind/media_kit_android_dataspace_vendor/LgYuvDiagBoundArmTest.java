package com.alexmercerind.media_kit_android_dataspace_vendor;
import static org.junit.Assert.*;
import org.junit.Test;

import com.alexmercerind.media_kit_video.platformview.MediaCodecSurfaceTextureBridge;

/** A2 owner-bound YUV diag arm: ledger admission, pure gate, owner-key derivation. */
public class LgYuvDiagBoundArmTest {
 @Test public void armedOwnerRequiresPendingTokenAndRegisteredSurface() {
  LgExperimentSurfaceOwners o=new LgExperimentSurfaceOwners(); Object s=new Object();
  assertFalse(o.hasArmedOwner(null)); assertFalse(o.hasArmedOwner(""));
  assertFalse(o.hasArmedOwner("a")); // Not pending.
  assertTrue(o.enable(7,"a"));
  assertFalse(o.hasArmedOwner("a")); // Pending but no registered surface.
  o.register(s,7,1,2,1,"a");
  assertTrue(o.hasArmedOwner("a"));
  o.unregister(s,7,1,2,1,"a");
  assertFalse(o.hasArmedOwner("a")); // Revoke removed pending + surface.
  assertFalse(o.enable(7,"a")); // Retired token cannot re-arm.
 }
 @Test public void boundArmGateRequiresApplicabilityOwnerAndTuple() {
  // 0/0 unbound tuple and missing inputs refuse; only the full admission passes.
  String t="token";
  assertFalse(LgPqDataSpaceExt.canEnableYuvDiag(false,true,t,1));
  assertFalse(LgPqDataSpaceExt.canEnableYuvDiag(true,false,t,1));
  assertFalse(LgPqDataSpaceExt.canEnableYuvDiag(true,true,null,1));
  assertFalse(LgPqDataSpaceExt.canEnableYuvDiag(true,true,"",1));
  assertFalse(LgPqDataSpaceExt.canEnableYuvDiag(true,true,t,0));
  assertFalse(LgPqDataSpaceExt.canEnableYuvDiag(true,true,t,-3));
  assertTrue(LgPqDataSpaceExt.canEnableYuvDiag(true,true,t,7));
 }
 @Test public void ownerKeyIsTheFrozenFnv1a64OfTheToken() {
  // Reference vectors computed independently of the Java implementation
  // (hex literals: the 64-bit values exceed the signed long range).
  assertEquals(0xe71fa2190541574bL, MediaCodecSurfaceTextureBridge.ownerKey("abc"));
  assertEquals(0xaf63dc4c8601ec8cL, MediaCodecSurfaceTextureBridge.ownerKey("a"));
  assertEquals(0xaf63f54c86021707L, MediaCodecSurfaceTextureBridge.ownerKey("x"));
  assertEquals(0xc4deb989ed336b6aL, MediaCodecSurfaceTextureBridge.ownerKey("deadbeef01"));
  // Deterministic per token; distinct tokens derive distinct keys.
  String t1="0123456789abcdef0123456789abcdef";
  String t2="0123456789abcdef0123456789abcdeg";
  assertEquals(MediaCodecSurfaceTextureBridge.ownerKey(t1), MediaCodecSurfaceTextureBridge.ownerKey(t1));
  assertNotEquals(MediaCodecSurfaceTextureBridge.ownerKey(t1), MediaCodecSurfaceTextureBridge.ownerKey(t2));
 }
}
