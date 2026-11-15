// Cloud evidence from your MongoDB Atlas cluster (it is already a 3-node replica set).
// Run:  mongosh "%MONGO_URI%" --file 04_atlas_status.js
const h = db.hello();
print('Atlas replica set :', h.setName);
print('Connected to      :', h.me, h.isWritablePrimary ? '(PRIMARY)' : '(SECONDARY)');
print('Primary           :', h.primary);
print('All members       :');
h.hosts.forEach(x => print('   ', x));

const t = db.getSiblingDB('lagos_trust_bank_nosql').ha_test_atlas;
t.drop();
let s = Date.now();
for (let i = 0; i < 20; i++) t.insertOne({ i }, { writeConcern: { w: 'majority' } });
print('\n20 inserts with w:"majority" over the internet:', ((Date.now() - s) / 20).toFixed(1), 'ms each');
s = Date.now();
for (let i = 0; i < 20; i++) t.insertOne({ i }, { writeConcern: { w: 1 } });
print('20 inserts with w:1 over the internet          :', ((Date.now() - s) / 20).toFixed(1), 'ms each');
print('(most of the time is network distance from your laptop to the Atlas region)');
t.drop();
