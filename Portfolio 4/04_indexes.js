// Portfolio 4: indexing, explain and timing, before and after.   Run: mongosh --file 04_indexes.js
// Re-running is safe: it drops the demo indexes first so "before" is always un-indexed.
load('helpers.js');
['customers', 'accounts', 'transactions'].forEach(c =>
  d[c].getIndexes().filter(i => i.name !== '_id_').forEach(i => d[c].dropIndex(i.name)));

const queries = {
  'statement (account + 90 days, newest first)': () =>
      d.transactions.find({ accountNumber: '0123456789', createdAt: { $gte: daysAgo(90) } }).sort({ createdAt: -1 }),
  'customer by email':     () => d.customers.find({ email: 'adaeze@example.com' }),
  'accounts of customer':  () => d.accounts.find({ customerId: d.customers.findOne({ email: 'adaeze@example.com' })._id })
};

function measure(label) {
  header(label);
  for (const [name, q] of Object.entries(queries)) {
    const p = planOf(q());
    print(name.padEnd(46), '| stages:', p.stages.join(' > '), '| keys:', p.keysExamined, '| docs:', p.docsExamined,
          '| avg ms:', timeIt(() => q().toArray()));
  }
}

measure('BEFORE indexes');

header('Creating indexes');
function ix(coll, keys, opts, why) {
  try { print(d[coll].createIndex(keys, opts || {}).padEnd(34), why); }
  catch (e) { print('SKIPPED', JSON.stringify(keys), '(' + e.message.slice(0, 60) + ')'); }
}
ix('transactions', { accountNumber: 1, createdAt: -1 }, {}, 'equality field first, sort/range field second (like Portfolio 2)');
ix('customers',    { email: 1 },         { unique: true }, 'login/teller lookup, enforces uniqueness');
ix('customers',    { bvn: 1 },           { unique: true }, 'regulatory identifier must be unique');
ix('accounts',     { accountNumber: 1 }, { unique: true }, 'natural key');
ix('accounts',     { customerId: 1 },    {},               'reference lookup (documents have no automatic FK indexes)');
// MongoDB-only index types (skipped automatically on servers that lack them):
ix('transactions', { amountKobo: -1 }, { partialFilterExpression: { amountKobo: { $gte: NumberLong('100000000') } }, name: 'big_txn_partial' },
   'PARTIAL: only transactions >= NGN 1,000,000 (AML monitoring), tiny index');
d.createCollection('otp_codes');
ix('otp_codes', { createdAt: 1 }, { expireAfterSeconds: 300 }, 'TTL: documents expire automatically after 5 minutes');

measure('AFTER indexes');

header('Unique index enforcement (duplicate email must be rejected)');
try {
  const c = d.customers.findOne({ email: 'adaeze@example.com' }, { _id: 0 });
  d.customers.insertOne(c);
  print('!! duplicate accepted (unique index missing)');
} catch (e) { print('Rejected as expected:', e.message.slice(0, 70)); }

header('Index sizes (bytes)');
const st = d.transactions.stats();
print('transactions data size:', st.size, '| total index size:', st.totalIndexSize === undefined ? 'n/a' : st.totalIndexSize);
