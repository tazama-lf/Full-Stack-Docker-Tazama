@echo off
echo Pulling BIAR infrastructure images...
echo.

echo [1/8] logicalspark/docker-tikaserver:latest
docker pull logicalspark/docker-tikaserver:latest

echo [2/8] solr:9
docker pull solr:9

echo [3/8] apache/nifi:1.24.0
docker pull apache/nifi:1.24.0

echo [4/8] apache/ozone:2.0.0
docker pull apache/ozone:2.0.0

echo [5/8] amazon/aws-cli
docker pull amazon/aws-cli

echo [6/8] confluentinc/cp-zookeeper:7.5.0
docker pull confluentinc/cp-zookeeper:7.5.0

echo [7/8] confluentinc/cp-kafka:7.5.0
docker pull confluentinc/cp-kafka:7.5.0

echo [8/8] debezium/connect:2.5
docker pull debezium/connect:2.5

echo.
echo All images pulled.
pause
