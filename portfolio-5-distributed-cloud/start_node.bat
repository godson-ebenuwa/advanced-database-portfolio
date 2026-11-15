@echo off
rem Restart ONE node after you killed it.  Usage: start_node.bat 27018   (or 27019 / 27020)
set "BIN=C:\Program Files\MongoDB\Server\9.0\bin"
set "ROOT=C:\mongo-rs"
set /a N=%1-27017
start "mongod-%1 (node %N%)" "%BIN%\mongod.exe" --replSet lagosRS --port %1 --bind_ip localhost --dbpath "%ROOT%\n%N%\data" --logpath "%ROOT%\n%N%\mongod.log"
