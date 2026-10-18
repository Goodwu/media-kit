package com.alexmercerind.media_kit_android_dataspace_vendor;
import static org.junit.Assert.*;
import org.junit.After;
import org.junit.Test;

/**
 * Process-static output-initialization gate (V2 B1 rounds 3–4): the Java
 * statics ARE the cross-engine medium — every Flutter engine in this OS
 * process shares this class, so these assertions are the equivalent of the
 * cross-engine conflict negatives the Dart host tests cannot spawn. The
 * write identity is a process-unique LEASE id (R3-4): while a lease is
 * held every other acquire is rejected — the same token, engine or not.
 */
public class ProcessOutputInitGateTest {
 @After public void reset() { ProcessOutputInitGate.reset(); }

 @Test public void readersAreConcurrent() {
  assertTrue(ProcessOutputInitGate.beginRead());
  assertTrue(ProcessOutputInitGate.beginRead());
  assertEquals(2, ProcessOutputInitGate.readerCount());
  ProcessOutputInitGate.endRead();
  ProcessOutputInitGate.endRead();
  assertEquals(0, ProcessOutputInitGate.readerCount());
 }

 @Test public void writeIsRejectedWhileAnyReaderIsActive() {
  assertTrue(ProcessOutputInitGate.beginRead());
  assertEquals(0L, ProcessOutputInitGate.beginWrite(11L, 1L, 0L));
  assertFalse(ProcessOutputInitGate.writerHeld());
  // The rejected writer performed no state change at all.
  assertTrue(ProcessOutputInitGate.beginRead());
 }

 @Test public void readIsRejectedWhileAnyWriterIsLive() {
  assertTrue(ProcessOutputInitGate.beginWrite(11L, 1L, 0L) > 0);
  assertFalse(ProcessOutputInitGate.beginRead());
  assertEquals(0, ProcessOutputInitGate.readerCount());
  assertTrue(ProcessOutputInitGate.writerHeld());
 }

 @Test public void secondWriterWithADifferentKeyIsRejected() {
  final long lease = ProcessOutputInitGate.beginWrite(11L, 1L, 0L);
  assertTrue(lease > 0);
  assertEquals(0L, ProcessOutputInitGate.beginWrite(22L, 1L, 0L));
  assertEquals(11L, ProcessOutputInitGate.writerKey());
 }

 @Test public void sameKeyAcrossEnginesIsRejected() {
  // R3-4: the per-session single-open guard cannot see across engines, so
  // the lease identity must — the same token presented by a second engine
  // (or by the same engine as a NEW admission) is a conflict.
  final long lease = ProcessOutputInitGate.beginWrite(11L, 1L, 0L);
  assertTrue(lease > 0);
  assertEquals(0L, ProcessOutputInitGate.beginWrite(11L, 2L, 0L));
  assertEquals(0L, ProcessOutputInitGate.beginWrite(11L, 1L, 0L));
  assertTrue(ProcessOutputInitGate.writerHeld());
  assertEquals(1L, ProcessOutputInitGate.writerEngine());
  // Only a retry presenting the exact held lease id is idempotent.
  assertEquals(lease, ProcessOutputInitGate.beginWrite(11L, 1L, lease));
  // The second participant gets the write only after a true release.
  assertTrue(ProcessOutputInitGate.endWrite(lease));
  final long next = ProcessOutputInitGate.beginWrite(11L, 2L, 0L);
  assertTrue(next > 0);
  assertTrue(next != lease);
 }

 @Test public void staleEndWriteIsRejectedAndKeepsTheLease() {
  // R3-4: only the lease holder may end the write — an unknown or
  // superseded lease id changes nothing.
  final long lease = ProcessOutputInitGate.beginWrite(11L, 1L, 0L);
  assertFalse(ProcessOutputInitGate.endWrite(lease + 1));
  assertFalse(ProcessOutputInitGate.endWrite(0));
  assertTrue(ProcessOutputInitGate.writerHeld());
  assertEquals(lease, ProcessOutputInitGate.writerLease());
  assertTrue(ProcessOutputInitGate.endWrite(lease));
  assertFalse(ProcessOutputInitGate.writerHeld());
 }

 @Test public void endReadIsIdempotentAndFloored() {
  ProcessOutputInitGate.endRead();
  assertEquals(0, ProcessOutputInitGate.readerCount());
  assertTrue(ProcessOutputInitGate.beginRead());
  ProcessOutputInitGate.endRead();
  ProcessOutputInitGate.endRead();
  assertEquals(0, ProcessOutputInitGate.readerCount());
 }

 @Test public void releaseAllowsTheNextWriterAfterReadersDrain() {
  assertTrue(ProcessOutputInitGate.beginRead());
  assertEquals(0L, ProcessOutputInitGate.beginWrite(11L, 1L, 0L));
  ProcessOutputInitGate.endRead();
  assertTrue(ProcessOutputInitGate.beginWrite(11L, 1L, 0L) > 0);
  assertTrue(ProcessOutputInitGate.endWrite(
          ProcessOutputInitGate.writerLease()));
  assertTrue(ProcessOutputInitGate.beginRead());
 }
}
