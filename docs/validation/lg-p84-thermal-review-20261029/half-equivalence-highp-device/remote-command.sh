test ! -e /data/local/tmp/lg-half-highp-9220d2a699f64488b9a239a7a0a78d07/result.json || exit 73
/data/local/tmp/lg-half-highp-9220d2a699f64488b9a239a7a0a78d07/lg_half_equivalence /data/local/tmp/lg-half-highp-9220d2a699f64488b9a239a7a0a78d07/result.json highp-small-rtz >/data/local/tmp/lg-half-highp-9220d2a699f64488b9a239a7a0a78d07/stdout.txt 2>/data/local/tmp/lg-half-highp-9220d2a699f64488b9a239a7a0a78d07/stderr.txt &
probe_pid=$!
echo "$probe_pid" >/data/local/tmp/lg-half-highp-9220d2a699f64488b9a239a7a0a78d07/pid.txt
wait "$probe_pid"
probe_rc=$?
echo "$probe_rc" >/data/local/tmp/lg-half-highp-9220d2a699f64488b9a239a7a0a78d07/exit.txt
exit "$probe_rc"
