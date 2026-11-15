@echo off
rem Run ONCE after the three nodes are up. Tells the nodes they form one replica set.
mongosh --port 27018 --quiet --eval "rs.initiate({_id:'lagosRS', members:[{_id:0,host:'localhost:27018'},{_id:1,host:'localhost:27019'},{_id:2,host:'localhost:27020'}]})"
echo.
echo Wait 10-20 seconds for an election, then run 01_replica_status.js (see README).
