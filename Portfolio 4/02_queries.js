// Portfolio 4: CRUD and query examples.   Run: mongosh --file 02_queries.js
load('helpers.js');

header('Q1. Teller lookup: find a customer by email (one document holds profile, address, KYC, devices)');
const adaeze = d.customers.findOne({ email: 'adaeze@example.com' },
                                   { _id: 1, customerNo: 1, name: 1, 'addresses.city': 1, 'kyc.tier': 1 });
printjson(adaeze);

header('Q2. All accounts of that customer (reference lookup by customerId)');
d.accounts.find({ customerId: adaeze._id }, { _id: 0, accountNumber: 1, type: 1, 'branch.name': 1, balanceKobo: 1 })
  .forEach(a => print(a.accountNumber, a.type.padEnd(14), a.branch.name.padEnd(16), 'NGN', naira(a.balanceKobo)));

header('Q3. Account statement: last 90 days, newest 5 only');
d.transactions.find({ accountNumber: '0123456789', createdAt: { $gte: daysAgo(90) } },
                    { _id: 0, createdAt: 1, type: 1, channel: 1, amountKobo: 1 })
  .sort({ createdAt: -1 }).limit(5)
  .forEach(t => print(t.createdAt.toISOString().slice(0, 10), t.type.padEnd(11), t.channel.padEnd(7), 'NGN', naira(t.amountKobo)));
print('Total rows in the 90-day window:',
      d.transactions.countDocuments({ accountNumber: '0123456789', createdAt: { $gte: daysAgo(90) } }));

header('Q4. Polymorphic documents: USSD transactions above NGN 100,000 (query on a channel-specific field)');
print('count =', d.transactions.countDocuments({ channel: 'USSD', 'meta.shortcode': '*737#', amountKobo: { $gt: NumberLong('10000000') } }));
printjson(d.transactions.findOne({ channel: 'POS' }, { _id: 0, channel: 1, meta: 1 }));
print('^ a POS document has completely different meta fields, with no NULL columns and no schema change');

header('Q5. Query inside an array: customers with at least one Android device');
print('count =', d.customers.countDocuments({ 'devices.os': 'Android' }));

header('Q6. UPDATE embedded data: register a new device and upgrade KYC tier (no joins, one document)');
const before = d.customers.findOne({ email: 'tunde@example.com' }, { devices: 1, 'kyc.tier': 1 });
print('before: devices =', before.devices.length, ', kyc tier =', before.kyc.tier);
d.customers.updateOne({ email: 'tunde@example.com' }, {
  $push: { devices: { deviceId: 'DEV-NEW-001', os: 'Android', lastSeen: new Date() } },
  $set:  { 'kyc.tier': 3, 'preferences.alerts.email': true }
});
const after = d.customers.findOne({ email: 'tunde@example.com' }, { devices: 1, 'kyc.tier': 1 });
print('after:  devices =', after.devices.length, ', kyc tier =', after.kyc.tier);

header('Q7. UPSERT and DELETE');
const up = d.accounts.updateOne({ accountNumber: '9999999999' },
  { $setOnInsert: { customerId: adaeze._id, type: 'Savings', balanceKobo: NumberLong('0'), status: 'ACTIVE',
                    branch: { branchId: 1, name: 'Ikeja Main', city: 'Lagos' }, openedAt: new Date() } },
  { upsert: true });
print('upsertedCount =', up.upsertedCount);
print('deletedCount  =', d.accounts.deleteOne({ accountNumber: '9999999999' }).deletedCount);
