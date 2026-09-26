package com.example.media_kit_test;
public final class ProbeMain {
  public static void main(String[] args) throws Exception {
    System.out.println(P5CodecProbe.run(args[0], 312, true, false, true,
        0, 0, 2, false, false, false));
  }
}
