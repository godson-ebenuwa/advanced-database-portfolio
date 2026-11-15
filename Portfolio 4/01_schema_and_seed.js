// =====================================================================
// Portfolio 4: MongoDB document model for Lagos Trust Bank
// Run:  mongosh --file 01_schema_and_seed.js
// Atlas/remote: mongosh "<connection-string>" --file 01_schema_and_seed.js
// Money is stored as integer KOBO (1 NGN = 100 kobo) in 64-bit integers, so there
// are no floating-point rounding errors. (Decimal128 is the alternative.)
// =====================================================================
load('helpers.js');
d.dropDatabase();

// ---- 1. Collections with JSON-Schema validation (the "schema-on-write" safety net) ----
function createWithValidator(name, schema) {
  try {
    d.createCollection(name, { validator: { $jsonSchema: schema }, validationAction: 'error' });
    print('created ' + name + ' WITH $jsonSchema validator');
  } catch (e) {
    d.createCollection(name);
    print('created ' + name + ' WITHOUT validator (server does not support it: ' + e.message.slice(0, 45) + '...)');
  }
}

createWithValidator('customers', {
  bsonType: 'object',
  required: ['customerNo', 'name', 'email', 'bvn', 'createdAt'],
  properties: {
    customerNo: { bsonType: 'string' },
    name:  { bsonType: 'object', required: ['first', 'last'] },
    email: { bsonType: 'string', pattern: '^.+@.+$' },
    bvn:   { bsonType: 'string', pattern: '^[0-9]{11}$' }
  }
});
createWithValidator('accounts', {
  bsonType: 'object',
  required: ['accountNumber', 'customerId', 'type', 'balanceKobo', 'status'],
  properties: {
    accountNumber: { bsonType: 'string', pattern: '^[0-9]{10}$' },
    type:   { enum: ['Savings', 'Current', 'Fixed Deposit'] },
    status: { enum: ['ACTIVE', 'DORMANT', 'FROZEN', 'CLOSED'] },
    balanceKobo: { bsonType: ['int', 'long'], minimum: 0 }        // like CHECK (balance >= 0)
  }
});
createWithValidator('transactions', {
  bsonType: 'object',
  required: ['accountNumber', 'type', 'amountKobo', 'channel', 'createdAt'],
  properties: {
    type:    { enum: ['DEPOSIT', 'WITHDRAWAL', 'TRANSFER_DEBIT', 'TRANSFER_CREDIT', 'REVERSAL'] },
    channel: { enum: ['MOBILE', 'USSD', 'ATM', 'POS', 'WEB'] },
    amountKobo: { bsonType: ['int', 'long'], minimum: 1 }
  }
});
d.createCollection('transfers');

// ---- 2. Deterministic pseudo-random numbers so every run gives the same data ----
let seed = 12345;
const rnd  = () => { seed = (seed * 1664525 + 1013904223) % 4294967296; return seed / 4294967296; };
const pick = arr => arr[Math.floor(rnd() * arr.length)];
const pad  = (n, w) => String(n).padStart(w, '0');
const kobo = naira => NumberLong(String(Math.round(naira * 100)));   // string arg avoids precision warnings

const firstNames = ['Adaeze','Tunde','Amina','Chinedu','Ngozi','Ibrahim','Funke','Emeka','Zainab','Segun'];
const lastNames  = ['Okafor','Bello','Yusuf','Adeyemi','Nwosu','Abubakar','Ogunleye','Eze','Mohammed','Balogun'];
const cities     = [['Lagos','Lagos'],['Ikeja','Lagos'],['Abuja','FCT'],['Port Harcourt','Rivers'],['Kano','Kano']];
const branches   = [
  { branchId: 1, name: 'Ikeja Main',      city: 'Lagos' },
  { branchId: 2, name: 'Victoria Island', city: 'Lagos' },
  { branchId: 3, name: 'Wuse II',         city: 'Abuja' }
];

// ---- 3. Customers (profile, addresses, KYC and devices are EMBEDDED: one read gets everything) ----
const N_CUSTOMERS = 2000;
const customers = [];
const named = [
  ['Adaeze','Okafor','adaeze@example.com','08011111111','22211111111'],
  ['Tunde','Bello','tunde@example.com','08022222222','22222222222'],
  ['Amina','Yusuf','amina@example.com','08033333333','22233333333']
];
for (let i = 0; i < N_CUSTOMERS; i++) {
  const nm  = i < 3 ? named[i] : [pick(firstNames), pick(lastNames), 'user' + i + '@example.com',
                                  '09' + pad(i, 9), pad(100000000 + i, 11)];
  const loc = pick(cities);
  customers.push({
    customerNo: 'C' + pad(i + 1, 6),
    name: { first: nm[0], last: nm[1] },
    email: nm[2], phone: nm[3], bvn: nm[4],
    dateOfBirth: new Date(Date.UTC(1960 + Math.floor(rnd() * 40), Math.floor(rnd() * 12), 1 + Math.floor(rnd() * 28))),
    addresses: [{ type: 'HOME', line1: 'Street ' + i, city: loc[0], state: loc[1] }],
    kyc: {
      tier: 1 + Math.floor(rnd() * 3),
      verifiedAt: daysAgo(Math.floor(rnd() * 700)),
      documents: [{ type: 'NIN', number: pad(30000000000 + i, 11) }]
    },
    devices: rnd() < 0.8 ? [{ deviceId: 'DEV' + pad(i, 6), os: pick(['Android', 'iOS']), lastSeen: daysAgo(Math.floor(rnd() * 30)) }] : [],
    preferences: { language: 'en', alerts: { sms: true, email: rnd() < 0.5 } },
    createdAt: daysAgo(Math.floor(rnd() * 1000))
  });
}
d.customers.insertMany(customers);
const custIds = d.customers.find({}, { _id: 1 }).sort({ customerNo: 1 }).toArray().map(c => c._id);

// ---- 4. Accounts (REFERENCE the customer; branch details are a small embedded snapshot) ----
const accounts = [
  { accountNumber: '0123456789', c: 0, b: 0, type: 'Savings',       naira: 250000 },
  { accountNumber: '0234567891', c: 1, b: 1, type: 'Current',       naira: 800000 },
  { accountNumber: '0345678912', c: 2, b: 2, type: 'Savings',       naira: 50000 },
  { accountNumber: '0456789123', c: 0, b: 0, type: 'Fixed Deposit', naira: 500000 }
].map(a => ({
  accountNumber: a.accountNumber, customerId: custIds[a.c], branch: branches[a.b],
  type: a.type, balanceKobo: kobo(a.naira), status: 'ACTIVE', openedAt: daysAgo(400)
}));
const N_ACCOUNTS = 3000;
for (let i = 0; i < N_ACCOUNTS; i++) {
  accounts.push({
    accountNumber: String(1000000000 + i),
    customerId: custIds[3 + (i % (N_CUSTOMERS - 3))],
    branch: pick(branches),
    type: pick(['Savings', 'Current', 'Fixed Deposit']),
    balanceKobo: kobo(Math.floor(rnd() * 5000000)),
    status: pick(['ACTIVE', 'ACTIVE', 'ACTIVE', 'ACTIVE', 'DORMANT', 'FROZEN']),
    openedAt: daysAgo(Math.floor(rnd() * 1000))
  });
}
d.accounts.insertMany(accounts);
const acctNos = accounts.map(a => a.accountNumber);

// ---- 5. Transactions: POLYMORPHIC documents. Each channel stores different `meta` fields ----
function makeTxn(accountNumber, daysBack) {
  const channel   = pick(['MOBILE', 'USSD', 'ATM', 'POS', 'WEB']);
  const createdAt = daysAgo(daysBack);
  const metaByChannel = {
    MOBILE: { deviceId: 'DEV' + pad(Math.floor(rnd() * 2000), 6), appVersion: pick(['4.1', '4.2', '5.0']) },
    USSD:   { shortcode: '*737#', sessionId: 'S' + Math.floor(rnd() * 1e9) },
    ATM:    { atmId: 'ATM' + pad(Math.floor(rnd() * 300), 4), location: pick(['Ikeja', 'Lekki', 'Wuse', 'Garki']) },
    POS:    { terminalId: 'T' + pad(Math.floor(rnd() * 900), 4), merchant: pick(['Shoprite', 'Jumia Pay', 'Chicken Rep']), mcc: pick(['5411', '5812', '5999']) },
    WEB:    { ip: '102.89.' + Math.floor(rnd() * 255) + '.' + Math.floor(rnd() * 255), browser: pick(['Chrome', 'Safari', 'Firefox']) }
  };
  return {
    accountNumber,
    type: pick(['DEPOSIT', 'WITHDRAWAL', 'DEPOSIT', 'WITHDRAWAL', 'DEPOSIT']),
    amountKobo: kobo(100 + Math.floor(rnd() * 200000)),
    balanceAfterKobo: kobo(Math.floor(rnd() * 5000000)),       // random: for performance testing only
    channel, meta: metaByChannel[channel],
    createdAt,
    yearMonth: createdAt.toISOString().slice(0, 7)             // "computed pattern": precomputed for fast monthly reports
  };
}
let batch = [];
for (let i = 0; i < 50000; i++) {
  batch.push(makeTxn(pick(acctNos), rnd() * 365));
  if (batch.length === 5000) { d.transactions.insertMany(batch); batch = []; }
}
// A guaranteed busy account for the statement demo:
for (let i = 0; i < 120; i++) batch.push(makeTxn('0123456789', rnd() * 90));
d.transactions.insertMany(batch);

header('Seed complete');
['customers', 'accounts', 'transactions', 'transfers'].forEach(c => print(c.padEnd(14), d[c].countDocuments()));
header('Sample customer document (embedded model)');
printjson(d.customers.findOne({ email: 'adaeze@example.com' }, { _id: 0 }));
header('Sample transaction (USSD and ATM show different meta fields)');
printjson(d.transactions.findOne({ channel: 'USSD' }, { _id: 0 }));
printjson(d.transactions.findOne({ channel: 'ATM' }, { _id: 0 }));
