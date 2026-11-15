// Shared helpers, loaded by the other scripts with load("helpers.js").
// Run every script from inside this folder:  mongosh --file 02_queries.js
const DB_NAME = 'lagos_trust_bank_nosql';
const d = db.getSiblingDB(DB_NAME);

const toNum   = k => (k && typeof k.toNumber === 'function') ? k.toNumber() : Number(k);
const naira   = k => (toNum(k) / 100).toLocaleString('en-NG', { minimumFractionDigits: 2 });
const daysAgo = n => new Date(Date.now() - n * 86400000);
const header  = t => print('\n=== ' + t + ' ===');

// Average run time in ms of fn() over `runs` runs (after one warm-up run).
function timeIt(fn, runs = 20) {
  fn();
  const s = Date.now();
  for (let i = 0; i < runs; i++) fn();
  return ((Date.now() - s) / runs).toFixed(2);
}

// Summarise an explain() so the output is short and comparable before/after indexing.
function planOf(cursor) {
  const e  = cursor.explain('executionStats');
  const qp = e.queryPlanner || {};
  const wp = JSON.stringify(qp.winningPlan || qp);
  const stages = [...new Set(wp.match(/COLLSCAN|IXSCAN|FETCH|SORT|SCAN [a-z0-9_]+|SEARCH [a-z0-9_ ]+/g) || [])];
  const es = e.executionStats;
  return {
    stages,
    keysExamined: es ? es.totalKeysExamined : 'n/a (server does not report)',
    docsExamined: es ? es.totalDocsExamined : 'n/a (server does not report)',
    returned:     es ? es.nReturned : 'n/a'
  };
}
