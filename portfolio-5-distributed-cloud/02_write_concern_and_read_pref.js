// Durability vs speed (write concern) and fresh vs possibly-stale reads (read preference).
// Run with the same replica-set connection string as 01_replica_status.js
const t = db.getSiblingDB('lagos_trust_bank_nosql').ha_test;
t.drop();

header = s => print('\n=== ' + s + ' ===');

header('1. Write concern: how many nodes must confirm before the write is acknowledged?');
function bench(label, wc, n = 100) {
  const s = Date.now();
  for (let i = 0; i < n; i++) t.insertOne({ label, i, ts: new Date() }, { writeConcern: wc });
  const ms = Date.now() - s;
  print(label.padEnd(30), n, 'inserts:', String(ms).padStart(6), 'ms total,', (ms / n).toFixed(2), 'ms each');
}
bench('w:1 (primary only)', { w: 1 });
bench('w:"majority" (2 of 3 nodes)', { w: 'majority' });
bench('w:3 (all nodes)', { w: 3 });
print('=> stronger guarantees cost latency. Money movements should use w:"majority".');

header('2. Read preference: read from a SECONDARY');
db.getMongo().setReadPref('secondary');
print('count read from a secondary :', t.countDocuments({}));
db.getMongo().setReadPref('primary');
print('count read from the primary :', t.countDocuments({}));

header('3. Can a secondary return STALE data? write with w:1, then immediately read from a secondary');
let stale = 0;
const trials = 300;
for (let i = 0; i < trials; i++) {
  db.getMongo().setReadPref('primary');
  t.insertOne({ probe: i }, { writeConcern: { w: 1 } });
  db.getMongo().setReadPref('secondary');
  if (t.countDocuments({ probe: i }) === 0) stale++;
}
db.getMongo().setReadPref('primary');
print('stale reads:', stale, 'out of', trials);
print('On one laptop replication takes microseconds, so 0 is common here. Across the internet (Atlas, other');
print('regions) lag is real. The point is that a secondary read is only EVENTUALLY consistent.');

header('4. Read concern "majority": only return data a majority of nodes have confirmed');
print('majority-read count:', t.find().readConcern('majority').toArray().length);
