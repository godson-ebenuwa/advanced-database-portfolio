#!/usr/bin/env bash
# =====================================================================
# Portfolio 4: Redis (key-value) for the parts of a bank that need speed and expiry.
# Run: ./06_redis_keyvalue.sh      (needs redis-cli and a Redis server on localhost:6379;
#      Docker: docker run -d --name redis -p 6379:6379 redis:7)
# Each line prints the command (">") and Redis's reply.
# =====================================================================
R() { echo "> $*"; redis-cli -n 5 "$@"; }       # database 5 so we never touch other data
section() { echo; echo "=== $* ==="; }

R FLUSHDB > /dev/null

section "1. Balance cache (read-heavy; expires so stale data cannot live long)"
R SET balance:0123456789 25000000 EX 60
R GET balance:0123456789
R TTL balance:0123456789
R DECRBY balance:0123456789 5000000          # atomic integer update in kobo
R GET balance:0123456789

section "2. Idempotency key: SET NX means only the FIRST request with this reference wins"
R SET idem:TRF-1001 processing NX EX 86400
R SET idem:TRF-1001 processing NX EX 86400   # retry: returns (nil), so do not process again
R GET idem:TRF-1001

section "3. Login brute-force protection: at most 5 failed attempts per 15 minutes"
for i in 1 2 3 4 5 6; do
  n=$(redis-cli -n 5 INCR fail:08011111111)
  [ "$n" = "1" ] && redis-cli -n 5 EXPIRE fail:08011111111 900 > /dev/null   # window starts on the first failure
  if [ "$n" -gt 5 ]; then echo "attempt $i: count=$n -> BLOCKED"; else echo "attempt $i: count=$n -> allowed"; fi
done
R TTL fail:08011111111

section "4. One-time password with automatic expiry (2 seconds here; 300 in production)"
R SET otp:08011111111 482913 EX 2
R GET otp:08011111111
echo "(waiting 3 seconds...)"; sleep 3
R GET otp:08011111111                         # expired: (nil)

section "5. Short-lived lock so two workers cannot process the same account at once"
R SET lock:acct:0123456789 worker-A NX PX 5000
R SET lock:acct:0123456789 worker-B NX PX 5000   # (nil): lock already held
R PTTL lock:acct:0123456789
R DEL lock:acct:0123456789
R SET lock:acct:0123456789 worker-B NX PX 5000   # now B can take it

section "6. Session as a hash"
R HSET session:abc123 customerNo C000001 device DEV000000 channel MOBILE
R EXPIRE session:abc123 1800
R HGETALL session:abc123

section "7. Real-time leaderboard: today's biggest spenders (sorted set)"
R ZINCRBY spend:2026-11-14 150000 C000001
R ZINCRBY spend:2026-11-14 90000  C000002
R ZINCRBY spend:2026-11-14 420000 C000003
R ZINCRBY spend:2026-11-14 60000  C000001
R ZREVRANGE spend:2026-11-14 0 2 WITHSCORES
R ZREVRANK spend:2026-11-14 C000001

section "Memory and keys"
R DBSIZE
R KEYS '*'
