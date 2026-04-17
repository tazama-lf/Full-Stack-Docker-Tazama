FROM python:3.9-slim-bookworm

WORKDIR /app

RUN apt-get update && apt-get install -y \
    curl \
    bash \
    procps \
    ca-certificates \
    tar \
    && rm -rf /var/lib/apt/lists/*

# Java 11 (Temurin) - Debian bookworm does not ship OpenJDK 11 packages by default.
# Using a pinned release URL for reproducible builds.
ARG TEMURIN_11_TAG=jdk-11.0.30+7
ARG TEMURIN_11_TGZ=OpenJDK11U-jdk_x64_linux_hotspot_11.0.30_7.tar.gz
RUN mkdir -p /opt/java && \
    curl -fsSL "https://github.com/adoptium/temurin11-binaries/releases/download/${TEMURIN_11_TAG}/${TEMURIN_11_TGZ}" -o /tmp/temurin11.tgz && \
    tar -xzf /tmp/temurin11.tgz -C /opt/java --strip-components=1 && \
    rm -f /tmp/temurin11.tgz

ARG SPARK_VERSION=3.4.2
ARG HADOOP_PROFILE=hadoop3
ARG HUDI_BUNDLE_VERSION=0.14.1
ARG HADOOP_AWS_VERSION=3.3.4
ARG AWS_SDK_BUNDLE_VERSION=1.12.262

RUN mkdir -p /opt /opt/jars && \
    curl -fsSL "https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-${HADOOP_PROFILE}.tgz" -o /tmp/spark.tgz && \
    tar -xzf /tmp/spark.tgz -C /opt && \
    mv "/opt/spark-${SPARK_VERSION}-bin-${HADOOP_PROFILE}" /opt/spark && \
    rm -f /tmp/spark.tgz

RUN curl -fsSL "https://repo1.maven.org/maven2/org/apache/hudi/hudi-spark3.4-bundle_2.12/${HUDI_BUNDLE_VERSION}/hudi-spark3.4-bundle_2.12-${HUDI_BUNDLE_VERSION}.jar" -o /opt/jars/hudi-spark3.4-bundle_2.12-0.14.1.jar && \
    curl -fsSL "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_AWS_VERSION}/hadoop-aws-${HADOOP_AWS_VERSION}.jar" -o /opt/jars/hadoop-aws-3.3.4.jar && \
    curl -fsSL "https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/${AWS_SDK_BUNDLE_VERSION}/aws-java-sdk-bundle-${AWS_SDK_BUNDLE_VERSION}.jar" -o /opt/jars/aws-java-sdk-bundle-1.12.262.jar

ENV JAVA_HOME=/opt/java
ENV SPARK_HOME=/opt/spark
ENV PATH=$SPARK_HOME/bin:$JAVA_HOME/bin:$PATH
ENV SPARK_JARS=/opt/jars/hudi-spark3.4-bundle_2.12-0.14.1.jar,/opt/jars/hadoop-aws-3.3.4.jar,/opt/jars/aws-java-sdk-bundle-1.12.262.jar
ENV APP_PORT=7619

# Python deps
RUN pip3 install --upgrade pip
RUN pip3 install fastapi uvicorn pandas pyspark==3.4.2

# Expose API port
EXPOSE 7619

# Copy code
COPY . .

# Permissions (optional)
RUN chmod -R 777 /app

# Run FastAPI
CMD ["sh", "-c", "uvicorn automation_orchestrator_api:app --host 0.0.0.0 --port ${APP_PORT:-7619} --log-level info"]
