// Shows who is PRIMARY and who is SECONDARY.
// Run:  mongosh "mongodb://localhost:27018,localhost:27019,localhost:27020/?replicaSet=lagosRS&serverSelectionTimeoutMS=3000" --file 01_replica_status.js
const hello = db.hello();
print('Replica set:', hello.setName, '| primary seen by the driver:', hello.primary);
print('Members the driver knows:', hello.hosts.join(', '));

print('\nMEMBER STATUS');
const st = rs.status();
st.members.forEach(m =>
  print(m.name.padEnd(18), m.stateStr.padEnd(10), 'health', m.health,
        '| last operation applied:', m.optimeDate ? m.optimeDate.toISOString() : '-'));

const votes = rs.conf().members.length;
print('\nVoting members:', votes, '| a MAJORITY needs', Math.floor(votes / 2) + 1, 'of them to elect a primary or acknowledge w:"majority" writes');
