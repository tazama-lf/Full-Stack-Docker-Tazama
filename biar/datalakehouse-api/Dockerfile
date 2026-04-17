# ─────────────────────────────────────────────
# Stage: runtime
# ─────────────────────────────────────────────
FROM python:3.9-slim-bookworm

# Java + runtime tools required by Spark / PySpark
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jdk \
        curl \
        procps \
    && rm -rf /var/lib/apt/lists/*

ENV SPARK_VERSION=3.4.2
ENV HADOOP_PROFILE=hadoop3
ENV HUDI_BUNDLE_VERSION=0.14.1
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV SPARK_HOME=/opt/spark
ENV PATH=$SPARK_HOME/bin:$JAVA_HOME/bin:$PATH
ENV SPARK_JARS=/opt/jars/hudi-spark3.4-bundle_2.12-0.14.1.jar
ENV APP_PORT=8282

WORKDIR /app

# ── Spark ────────────────────────────────────
RUN mkdir -p /opt
RUN curl -fL# "https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-${HADOOP_PROFILE}.tgz" -o /tmp/spark.tgz
RUN tar -xzf /tmp/spark.tgz -C /opt
RUN mv "/opt/spark-${SPARK_VERSION}-bin-${HADOOP_PROFILE}" /opt/spark
RUN rm -f /tmp/spark.tgz

# ── Hudi datasource jar (needed for format("hudi")) ──
RUN mkdir -p /opt/jars
RUN curl -fL# "https://repo1.maven.org/maven2/org/apache/hudi/hudi-spark3.4-bundle_2.12/${HUDI_BUNDLE_VERSION}/hudi-spark3.4-bundle_2.12-${HUDI_BUNDLE_VERSION}.jar" -o /opt/jars/hudi-spark3.4-bundle_2.12-0.14.1.jar

# ── Python dependencies ───────────────────────
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Application code ──────────────────────────
COPY lakehouse_query_api.py .

# ── Warehouse mount-point ─────────────────────
# Mount your local warehouse here:
#   docker run -v /opt/Tazama_Warehouse:/opt/Tazama_Warehouse ...
RUN mkdir -p /opt/Tazama_Warehouse

VOLUME ["/opt/Tazama_Warehouse"]

EXPOSE 8282

CMD ["python", "lakehouse_query_api.py"]
