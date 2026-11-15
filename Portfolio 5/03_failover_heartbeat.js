// Writes one document per second with w:"majority" and reports which node is primary.
// Start it, then KILL the primary's window while it runs (see README) and watch the failover.
// Run:  mongosh "mongodb://localhost:27018,localhost:27019,localhost:27020/?replicaSet=lagosRS&serverSelectionTimeoutMS=3000" --file 03_failover_heartbeat.js
const c = db.getSiblingDB('lagos_trust_bank_nosql').heartbeat;
c.drop();
let ok = 0, failed = 0, last = null, firstFail = null, recovered = null;

print('Writing 1 doc per second for about 60 iterations. Kill the primary now...');
for (let i = 1; i <= 60; i++) {
  let primary = '(no primary reachable)';
  try { primary = db.hello().primary || primary; } catch (e) { /* election in progress */ }

  let status;
  try {
    c.insertOne({ i, ts: new Date(), primaryAtWrite: primary }, { writeConcern: { w: 'majority', wtimeout: 3000 } });
    ok++; status = 'OK';
    if (firstFail && !recovered) recovered = new Date();
  } catch (e) {
    failed++; status = 'FAILED: ' + e.message.slice(0, 60);
    if (!firstFail) firstFail = new Date();
  }
  if (primary !== last) print('>>> primary is now:', primary);
  print(String(i).padStart(2), new Date().toISOString().slice(11, 19), primary.padEnd(22), status);
  last = primary;
  sleep(1000);
}
print('\nSUMMARY: ' + ok + ' writes succeeded, ' + failed + ' failed.');
if (firstFail && recovered) print('Outage lasted about ' + Math.round((recovered - firstFail) / 1000) + ' seconds (first failure to first success).');
