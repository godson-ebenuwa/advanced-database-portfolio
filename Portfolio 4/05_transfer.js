// =====================================================================
// Portfolio 4: money transfer in MongoDB (compare with Portfolio 3, PostgreSQL)
// Run: mongosh --file 05_transfer.js
// MongoDB guarantees atomicity for ONE document. A transfer touches TWO account documents,
// so we use: (1) a guarded atomic update per document, (2) an idempotency key,
// (3) a compensating action if step 2 fails (saga pattern).
// A true multi-document ACID transaction is shown at the end (needs a replica set).
// =====================================================================
load('helpers.js');
d.transfers.createIndex({ reference: 1 }, { unique: true });   // idempotency key

const bal = no => naira(d.accounts.findOne({ accountNumber: no }).balanceKobo);
const show = (...nos) => nos.forEach(n => print('   ', n, 'NGN', bal(n)));

function transferFunds(fromNo, toNo, amountKobo, reference) {
  const amt = NumberLong(String(amountKobo));
  const neg = NumberLong(String(-amountKobo));

  // Step 0: record the intent. A duplicate reference (client retry) hits the unique index.
  try {
    d.transfers.insertOne({ reference, fromAccount: fromNo, toAccount: toNo, amountKobo: amt, status: 'PENDING', createdAt: new Date() });
  } catch (e) {
    if (e.code === 11000) return { ok: true, note: 'duplicate reference: ignored (idempotent), no money moved' };
    throw e;
  }

  // Step 1: debit. The filter AND the $inc are evaluated atomically on that one document,
  // so two concurrent withdrawals can never both pass the balance check.
  const debited = d.accounts.findOneAndUpdate(
    { accountNumber: fromNo, status: 'ACTIVE', balanceKobo: { $gte: amt } },
    { $inc: { balanceKobo: neg } },
    { returnDocument: 'after' });
  if (!debited) {
    d.transfers.updateOne({ reference }, { $set: { status: 'FAILED', reason: 'insufficient funds or source not ACTIVE' } });
    return { ok: false, note: 'FAILED: insufficient funds or source account not ACTIVE' };
  }

  // Step 2: credit.
  const credited = d.accounts.findOneAndUpdate(
    { accountNumber: toNo, status: 'ACTIVE' },
    { $inc: { balanceKobo: amt } },
    { returnDocument: 'after' });
  if (!credited) {
    // Compensating action: undo the debit.
    d.accounts.updateOne({ accountNumber: fromNo }, { $inc: { balanceKobo: amt } });
    d.transfers.updateOne({ reference }, { $set: { status: 'FAILED', reason: 'destination missing/inactive; debit compensated' } });
    return { ok: false, note: 'FAILED: destination invalid, debit was compensated (refunded)' };
  }

  // Step 3: ledger entries and final status.
  const now = new Date();
  d.transactions.insertMany([
    { accountNumber: fromNo, type: 'TRANSFER_DEBIT',  amountKobo: amt, balanceAfterKobo: debited.balanceKobo,  channel: 'WEB', meta: { reference }, createdAt: now, yearMonth: now.toISOString().slice(0, 7) },
    { accountNumber: toNo,   type: 'TRANSFER_CREDIT', amountKobo: amt, balanceAfterKobo: credited.balanceKobo, channel: 'WEB', meta: { reference }, createdAt: now, yearMonth: now.toISOString().slice(0, 7) }
  ]);
  d.transfers.updateOne({ reference }, { $set: { status: 'SUCCESS', completedAt: now } });
  return { ok: true, note: 'SUCCESS' };
}

// ---- reset demo state ----
d.transfers.deleteMany({ reference: /^DEMO/ });
d.transactions.deleteMany({ 'meta.reference': /^DEMO/ });
d.accounts.updateOne({ accountNumber: '0123456789' }, { $set: { balanceKobo: NumberLong('25000000') } });
d.accounts.updateOne({ accountNumber: '0234567891' }, { $set: { balanceKobo: NumberLong('80000000') } });
d.accounts.updateOne({ accountNumber: '0345678912' }, { $set: { balanceKobo: NumberLong('5000000'), status: 'ACTIVE' } });
const A = '0123456789', B = '0234567891', C = '0345678912';

header('Start'); show(A, B, C);

header('5a. Successful transfer: A -> B, NGN 50,000');
print(' ', transferFunds(A, B, 5000000, 'DEMO-001').note); show(A, B);

header('5b. Insufficient funds: C -> A, NGN 999,999 (nothing must change)');
print(' ', transferFunds(C, A, 99999900, 'DEMO-002').note); show(C, A);

header('5c. Idempotency: client retries DEMO-001 after a timeout (must NOT move money twice)');
print(' ', transferFunds(A, B, 5000000, 'DEMO-001').note); show(A, B);

header('5d. Destination account does not exist: debit happens, then is compensated');
print(' ', transferFunds(A, '0000000000', 1000000, 'DEMO-003').note); show(A);

header('5e. Double-spend guard: C has NGN 1,000 and two NGN 800 withdrawals arrive');
d.accounts.updateOne({ accountNumber: C }, { $set: { balanceKobo: NumberLong('100000') } });
print('  first :', transferFunds(C, B, 80000, 'DEMO-004').note);
print('  second:', transferFunds(C, B, 80000, 'DEMO-005').note);
show(C);

header('Transfer log');
d.transfers.find({ reference: /^DEMO/ }, { _id: 0, reference: 1, status: 1, reason: 1 }).sort({ reference: 1 })
  .forEach(t => print(' ', t.reference, t.status.padEnd(8), t.reason || ''));

header('Ledger check: total debits must equal total credits');
const credits = d.transactions.aggregate([{ $match: { 'meta.reference': /^DEMO/, type: 'TRANSFER_CREDIT' } }, { $group: { _id: null, t: { $sum: '$amountKobo' } } }]).toArray();
const debits  = d.transactions.aggregate([{ $match: { 'meta.reference': /^DEMO/, type: 'TRANSFER_DEBIT'  } }, { $group: { _id: null, t: { $sum: '$amountKobo' } } }]).toArray();
print('  total debits  NGN', naira(debits[0].t));
print('  total credits NGN', naira(credits[0].t), (toNum(debits[0].t) === toNum(credits[0].t)) ? ' -> balanced' : ' -> MISMATCH');

header('5f. Multi-document ACID transaction (needs a replica set / Atlas; skipped on standalone servers)');
try {
  const session = db.getMongo().startSession();
  const sdb = session.getDatabase(DB_NAME);
  session.startTransaction({ readConcern: { level: 'snapshot' }, writeConcern: { w: 'majority' } });
  try {
    const amt = NumberLong('100000');
    sdb.accounts.updateOne({ accountNumber: A, balanceKobo: { $gte: amt } }, { $inc: { balanceKobo: NumberLong('-100000') } });
    sdb.accounts.updateOne({ accountNumber: B }, { $inc: { balanceKobo: amt } });
    sdb.transfers.insertOne({ reference: 'DEMO-TXN-001', fromAccount: A, toAccount: B, amountKobo: amt, status: 'SUCCESS', createdAt: new Date() });
    session.commitTransaction();
    print('  committed: both accounts and the transfer record changed together');
  } catch (e) {
    session.abortTransaction();
    print('  aborted, nothing changed:', e.message.slice(0, 90));
  }
  session.endSession();
} catch (e) {
  print('  SKIPPED on this server: ' + e.message.slice(0, 90));
}
