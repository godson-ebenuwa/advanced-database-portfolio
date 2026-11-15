@echo off
rem Starts 3 mongod nodes (replica set "lagosRS") on ports 27018, 27019, 27020, each in its own window.
rem EDIT the BIN line if your version folder differs (look inside C:\Program Files\MongoDB\Server\).
set "BIN=C:\Program Files\MongoDB\Server\9.0\bin"
set "ROOT=C:\mongo-rs"

if not exist "%BIN%\mongod.exe" (
  echo mongod.exe was not found in "%BIN%"
  echo Edit the BIN line at the top of this file, then run it again.
  pause
  exit /b 1
)
for %%N in (1 2 3) do if not exist "%ROOT%\n%%N\data" mkdir "%ROOT%\n%%N\data"

start "mongod-27018 (node 1)" "%BIN%\mongod.exe" --replSet lagosRS --port 27018 --bind_ip localhost --dbpath "%ROOT%\n1\data" --logpath "%ROOT%\n1\mongod.log"
start "mongod-27019 (node 2)" "%BIN%\mongod.exe" --replSet lagosRS --port 27019 --bind_ip localhost --dbpath "%ROOT%\n2\data" --logpath "%ROOT%\n2\mongod.log"
start "mongod-27020 (node 3)" "%BIN%\mongod.exe" --replSet lagosRS --port 27020 --bind_ip localhost --dbpath "%ROOT%\n3\data" --logpath "%ROOT%\n3\mongod.log"

echo Three mongod windows should now be open. If Windows Firewall asks, allow PRIVATE networks.
echo Wait about 10 seconds, then run init_replicaset.bat (only the FIRST time).
