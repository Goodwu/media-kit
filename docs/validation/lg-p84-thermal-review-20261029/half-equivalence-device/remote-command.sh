test ! -e /data/local/tmp/lg-half-equivalence-5e9feab4ad474a27b51019da09598406/result.json || exit 73
/data/local/tmp/lg-half-equivalence-5e9feab4ad474a27b51019da09598406/lg_half_equivalence /data/local/tmp/lg-half-equivalence-5e9feab4ad474a27b51019da09598406/result.json >/data/local/tmp/lg-half-equivalence-5e9feab4ad474a27b51019da09598406/stdout.txt 2>/data/local/tmp/lg-half-equivalence-5e9feab4ad474a27b51019da09598406/stderr.txt &
probe_pid=$!
echo "$probe_pid" >/data/local/tmp/lg-half-equivalence-5e9feab4ad474a27b51019da09598406/pid.txt
wait "$probe_pid"
probe_rc=$?
echo "$probe_rc" >/data/local/tmp/lg-half-equivalence-5e9feab4ad474a27b51019da09598406/exit.txt
exit "$probe_rc"
