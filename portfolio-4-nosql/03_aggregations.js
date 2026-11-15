// Portfolio 4: aggregation pipelines.   Run: mongosh --file 03_aggregations.js
load('helpers.js');

header('A1. Volume and value by channel  ($group + $sort)');
d.transactions.aggregate([
  { $group: { _id: '$channel', transactions: { $sum: 1 }, totalKobo: { $sum: '$amountKobo' } } },
  { $sort: { totalKobo: -1 } }
]).forEach(r => print(r._id.padEnd(7), String(r.transactions).padStart(6), 'txns   NGN', naira(r.totalKobo)));

header('A2. Monthly deposits vs withdrawals, last 6 months ($match, $group on precomputed yearMonth)');
d.transactions.aggregate([
  { $match: { type: { $in: ['DEPOSIT', 'WITHDRAWAL'] }, createdAt: { $gte: daysAgo(180) } } },
  { $group: { _id: { month: '$yearMonth', type: '$type' }, n: { $sum: 1 }, totalKobo: { $sum: '$amountKobo' } } },
  { $sort: { '_id.month': 1, '_id.type': 1 } }
]).forEach(r => print(r._id.month, r._id.type.padEnd(11), String(r.n).padStart(5), 'txns   NGN', naira(r.totalKobo)));

header('A3. Top 5 accounts by total withdrawals ($match, $group, $sort, $limit)');
d.transactions.aggregate([
  { $match: { type: 'WITHDRAWAL' } },
  { $group: { _id: '$accountNumber', withdrawnKobo: { $sum: '$amountKobo' }, n: { $sum: 1 } } },
  { $sort: { withdrawnKobo: -1 } },
  { $limit: 5 }
]).forEach(r => print(r._id, String(r.n).padStart(4), 'withdrawals   NGN', naira(r.withdrawnKobo)));

header('A4. Device OS distribution across customers ($unwind on an embedded array)');
d.customers.aggregate([
  { $unwind: '$devices' },
  { $group: { _id: '$devices.os', customers: { $sum: 1 } } },
  { $sort: { customers: -1 } }
]).forEach(r => print(r._id.padEnd(8), r.customers));

header('A5. Top 5 customers by total balance, joined to their names ($lookup). Needs real MongoDB');
try {
  d.accounts.aggregate([
    { $match: { status: 'ACTIVE' } },
    { $group: { _id: '$customerId', totalKobo: { $sum: '$balanceKobo' }, accounts: { $sum: 1 } } },
    { $sort: { totalKobo: -1 } },
    { $limit: 5 },
    { $lookup: { from: 'customers', localField: '_id', foreignField: '_id', as: 'c' } },
    { $unwind: '$c' },
    { $project: { _id: 0, customerNo: '$c.customerNo', name: '$c.name', accounts: 1, totalKobo: 1 } }
  ]).forEach(r => print(r.customerNo, (r.name.first + ' ' + r.name.last).padEnd(20), r.accounts, 'accts   NGN', naira(r.totalKobo)));
} catch (e) {
  print('SKIPPED on this server: ' + e.message.slice(0, 80));
}
