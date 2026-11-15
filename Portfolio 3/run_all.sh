#!/usr/bin/env bash
# Runs every demo with two concurrent psql sessions and saves the output in evidence/.
# Usage: ./run_all.sh [database_name]     (needs psql on the PATH; on Windows use Git Bash or WSL,
# or open two psql/pgAdmin windows and run the *_s1.sql and *_s2.sql files by hand within 1 second.)
DB=${1:-lagos_trust_bank}
P="psql -X -q -d $DB"
cd "$(dirname "$0")"; mkdir -p evidence

$P -f 00_functions.sql
$P -f 01_commit_rollback.sql > evidence/01_commit_rollback.txt 2>&1

run_pair () {  # $1 = name  $2 = file prefix s1  $3 = file prefix s2  $4.. = extra psql args
  name=$1; f1=$2; f2=$3
  $P -c "SELECT reset_demo()" > /dev/null
  { echo "### Balance before:"; $P -c "SELECT account_id, balance FROM account WHERE account_id IN (1,2) ORDER BY 1"; } > evidence/$name.txt
  $P -f $f1 > evidence/${name}_s1.log 2>&1 &
  $P -f $f2 > evidence/${name}_s2.log 2>&1 &
  wait
  { echo "### Session 1 output:"; cat evidence/${name}_s1.log; echo "### Session 2 output:"; cat evidence/${name}_s2.log
    echo "### Balance after:"; $P -c "SELECT account_id, balance FROM account WHERE account_id IN (1,2) ORDER BY 1"; } >> evidence/$name.txt
  rm -f evidence/${name}_s1.log evidence/${name}_s2.log
}

run_pair 02_lost_update          02_lost_update_s1.sql          02_lost_update_s2.sql
run_pair 03_fix_for_update       03_fix_for_update_s1.sql       03_fix_for_update_s2.sql
run_pair 04_fix_repeatable_read  04_fix_repeatable_read_s1.sql  04_fix_repeatable_read_s2.sql
run_pair 05_deadlock             05_deadlock_s1.sql             05_deadlock_s2.sql
run_pair 06_deadlock_fixed       06_deadlock_fixed_s1.sql       06_deadlock_fixed_s2.sql
run_pair 07_dirty_read           07_dirty_read_s1.sql           07_dirty_read_s2.sql

for lvl in "READ COMMITTED" "REPEATABLE READ"; do
  tag=$(echo "$lvl" | tr ' ' '_')
  $P -c "SELECT reset_demo()" > /dev/null
  $P -v level="$lvl" -f 07_isolation_reader.sql > evidence/07_isolation_$tag.txt 2>&1 &
  $P -f 07_isolation_writer.sql >> evidence/07_isolation_$tag.txt 2>&1 &
  wait
done
$P -c "SELECT reset_demo()" > /dev/null
echo "Done. See the evidence/ folder."
