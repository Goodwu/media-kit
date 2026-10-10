package com.alexmercerind.media_kit_android_dataspace_vendor;
import static org.junit.Assert.*;
import org.junit.Test;
public class LgExperimentSurfaceOwnersTest {
 @Test public void enableAloneNeverAuthorizesAndCloseOrFailureRevokes() {
  LgExperimentSurfaceOwners o=new LgExperimentSurfaceOwners(); Object s=new Object();
  assertTrue(o.enable(7,"a")); assertFalse(o.matches(s,7,1,2,1,"a"));
  o.register(s,7,1,2,1,"a"); assertTrue(o.matches(s,7,1,2,1,"a"));
  o.revoke(7,"a"); assertFalse(o.matches(s,7,1,2,1,"a"));
  assertFalse(o.enable(7,"a")); o.register(s,7,1,2,1,null);
  assertFalse(o.matches(s,7,1,2,1,null));
 }
 @Test public void tupleMustMatchAndStaleOwnerCannotAffectSuccessor() {
  LgExperimentSurfaceOwners o=new LgExperimentSurfaceOwners(); Object a=new Object(),b=new Object();
  o.enable(7,"a");o.register(a,7,1,2,1,"a");
  assertFalse(o.matches(a,8,1,2,1,"a"));assertFalse(o.matches(a,7,2,2,1,"a"));
  assertFalse(o.matches(a,7,1,3,1,"a"));assertFalse(o.matches(a,7,1,2,2,"a"));
  assertFalse(o.matches(b,7,1,2,1,"a"));
  o.enable(7,"b");o.register(b,7,2,3,1,"b");
  o.register(b,7,1,2,1,"a");o.unregister(b,7,1,2,1,"a");o.revoke(7,"a");
  assertTrue(o.matches(b,7,2,3,1,"b"));assertFalse(o.matches(a,7,1,2,1,"a"));
  o.unregister(b,7,2,3,1,"b");assertFalse(o.matches(b,7,2,3,1,"b"));
 }
 @Test public void reusedSurfaceGenerationRejectsStaleRegisterAndDestroy() {
  LgExperimentSurfaceOwners o=new LgExperimentSurfaceOwners();Object s=new Object();
  o.enable(7,"a");o.register(s,7,1,2,1,"a");o.unregister(s,7,1,2,1,"a");
  o.register(s,7,1,2,1,"a");assertFalse(o.matches(s,7,1,2,1,"a"));
  o.register(s,7,1,2,2,"a");o.unregister(s,7,1,2,1,"a");
  assertFalse(o.matches(s,7,1,2,2,"a"));assertFalse(o.enable(7,"a"));
 }
 @Test public void sameTokenCannotAuthorizeTwoViewsControllersOrSurfaces() {
  LgExperimentSurfaceOwners o=new LgExperimentSurfaceOwners();Object a=new Object(),b=new Object();
  o.enable(7,"a");o.register(a,7,1,2,1,"a");
  o.register(b,7,1,3,1,"a");assertFalse(o.matches(b,7,1,3,1,"a"));
  o.register(b,7,2,2,1,"a");assertFalse(o.matches(b,7,2,2,1,"a"));
  o.register(b,7,1,2,1,"a");assertFalse(o.matches(b,7,1,2,1,"a"));
  o.unregister(b,7,1,3,1,"a");assertTrue(o.matches(a,7,1,2,1,"a"));
  o.unregister(a,7,1,2,1,"a");o.register(b,7,1,3,1,"a");
  assertFalse(o.matches(b,7,1,3,1,"a"));
 }
 @Test public void destroyedSurfaceAndEngineTeardownClearAccess() {
  LgExperimentSurfaceOwners o=new LgExperimentSurfaceOwners();Object s=new Object();
  o.enable(7,"a");o.register(s,7,1,2,1,"a");o.unregister(s,7,1,2,1,"a");
  assertFalse(o.matches(s,7,1,2,1,"a"));
  o.register(s,7,1,2,2,"a");o.clear();assertFalse(o.matches(s,7,1,2,2,"a"));assertFalse(o.enable(7,"b"));
 }
}
