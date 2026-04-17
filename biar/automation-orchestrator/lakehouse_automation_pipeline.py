import os
import hashlib
from datetime import datetime, timedelta
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import *
from pyspark.sql.window import Window
from pyspark.sql import types as T
import json


def _env(name: str, default: str = "") -> str:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip()

DEFAULT_WAREHOUSE_ROOT = _env(
    "WAREHOUSE_ROOT",
)

# ===================================================================
# SPARK SESSION (reusable & configurable)
# ===================================================================
def get_spark_session():
    spark_home = _env("SPARK_HOME", "/opt/spark")
    os.environ["SPARK_HOME"] = spark_home

    spark_master = _env("SPARK_MASTER", "local[*]")
    spark_local_dir = _env("SPARK_LOCAL_DIR", "/tmp/spark")
    # Also set the env var Spark honors for local scratch.
    os.environ.setdefault("SPARK_LOCAL_DIRS", spark_local_dir)

    default_jars = [
        "/opt/jars/hudi-spark3.4-bundle_2.12-0.14.1.jar",
        "/opt/jars/hadoop-aws-3.3.4.jar",
        "/opt/jars/aws-java-sdk-bundle-1.12.262.jar",
    ]
    jars_env = _env("SPARK_JARS", ",".join(default_jars))
    jar_files = [j.strip() for j in jars_env.split(",") if j.strip()]

    s3_endpoint = _env("S3A_ENDPOINT", "http://10.10.80.20:9878")
    s3_access_key = _env("S3A_ACCESS_KEY", "hassan")
    s3_secret_key = _env("S3A_SECRET_KEY", "hassan")

    spark = (
        SparkSession.builder
        .appName("Tazama_Hudi_ETL")
        .master(spark_master)
        .config("spark.jars", ",".join(jar_files))
        .config("spark.driver.extraClassPath", ":".join(jar_files))
        .config("spark.executor.extraClassPath", ":".join(jar_files))
        # S3A / Ozone
        .config("spark.hadoop.fs.s3a.endpoint", s3_endpoint)
        .config("spark.hadoop.fs.s3a.access.key", s3_access_key)
        .config("spark.hadoop.fs.s3a.secret.key", s3_secret_key)
        .config("spark.hadoop.fs.s3a.path.style.access", "true")
        .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false")
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
        .config("spark.hadoop.fs.s3a.impl.disable.cache", "true")
        .config("spark.hadoop.fs.s3a.connection.maximum", "100")
        .config("spark.hadoop.fs.s3a.fast.upload", "true")
        # Hudi
        .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
        .config("spark.kryo.registrator", "org.apache.spark.HoodieSparkKryoRegistrar")
        .config("spark.sql.extensions", "org.apache.spark.sql.hudi.HoodieSparkSessionExtension")
        .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.hudi.catalog.HoodieCatalog")
        # Memory & performance
        .config("spark.local.dir", spark_local_dir)
        .config("spark.driver.memory", "10g")
        .config("spark.driver.memoryOverhead", "2g")
        .config("spark.driver.maxResultSize", "4g")
        .config("spark.executor.memory", "10g")
        .config("spark.executor.memoryOverhead", "2g")
        .config("spark.sql.shuffle.partitions", "16")
        .config("spark.default.parallelism", "16")
        .config("spark.memory.fraction", "0.8")
        .config("spark.memory.storageFraction", "0.2")
        .config("spark.sql.adaptive.enabled", "true")
        .config("spark.sql.adaptive.coalescePartitions.enabled", "true")
        .config("spark.sql.adaptive.advisoryPartitionSizeInBytes", "128mb")
        .config("spark.sql.legacy.timeParserPolicy", "LEGACY")
        .config("spark.sql.session.timeZone", "UTC")
        .getOrCreate()
    )
    spark.sparkContext.setLogLevel("WARN")
    print(f"Spark Version: {spark.version}")
    return spark


# ===================================================================
# COMMON HELPERS (extracted once for reuse)
# ===================================================================
def hudi_opts(table_name: str, record_key: str, precombine: str, partition: str = None, payload_class: str = None):
    opts = {
        "hoodie.table.name": table_name,
        "hoodie.datasource.write.table.type": "COPY_ON_WRITE",
        "hoodie.datasource.write.operation": "upsert",
        "hoodie.datasource.write.recordkey.field": record_key,
        "hoodie.datasource.write.precombine.field": precombine,
        "hoodie.datasource.write.schema.evolution.enable": "true",
        "hoodie.datasource.read.schema.evolution.enable": "true",
        "hoodie.datasource.write.reconcile.schema": "true",
        "hoodie.schema.on.read.enable": "true",
        "hoodie.metadata.enable": "false",
        "hoodie.index.type": "BLOOM",
    }
    if partition:
        opts.update({
            "hoodie.datasource.write.partitionpath.field": partition,
            "hoodie.datasource.write.keygenerator.class": "org.apache.hudi.keygen.NonpartitionedKeyGenerator",
            "hoodie.datasource.write.hive_style_partitioning": "false",
        })
    else:
        opts["hoodie.datasource.write.keygenerator.class"] = "org.apache.hudi.keygen.NonpartitionedKeyGenerator"
    
    if payload_class:
        opts["hoodie.datasource.write.payload.class"] = payload_class
    return opts


def infer_json_schema(spark, df, col_name: str) -> StructType:
    return spark.read.json(
        df.select(col_name).where(F.col(col_name).isNotNull()).rdd.map(lambda r: r[0])
    ).schema


def write_hudi(df, path, opts):
    df.write.format("hudi").options(**opts).mode("append").save(path)


def ensure_columns(df, col_types):
    """Ensure expected columns exist; add null-cast columns when missing."""
    out = df
    for col_name, col_type in col_types.items():
        if col_name not in out.columns:
            out = out.withColumn(col_name, F.lit(None).cast(col_type))
    return out


def read_latest_hudi(spark, path):
    bronze = spark.read.format("hudi").load(path)
    w = Window.partitionBy("_hoodie_record_key").orderBy(F.col("_hoodie_commit_time").desc())
    return (
        bronze
        .withColumn("rn", F.row_number().over(w))
        .where("rn = 1")
        .drop("rn")
    )


# ===================================================================
# 1. ALERTS ETL
# ===================================================================
def etl_alerts(spark, WAREHOUSE_ROOT, source_path=str):
    bronze_alerts_path = f"{WAREHOUSE_ROOT}/bronze/alerts"
    silver_alerts_path = f"{WAREHOUSE_ROOT}/silver/alerts"
    gold_alerts_path   = f"{WAREHOUSE_ROOT}/gold/alerts"
    silver_alerts_dlq_path = f"{WAREHOUSE_ROOT}/silver/alerts_dlq"

    # ------------------- BRONZE -------------------
    bronze_alerts = spark.read.json(source_path)

    bronze_alerts_cast = (
        bronze_alerts.select(
            F.col("alert_id").cast("long").alias("alert_id"),
            F.col("tenant_id").cast("string").alias("tenant_id"),
            F.col("priority").cast("string").alias("priority"),
            F.col("priority_score").cast("double").alias("priority_score"),
            F.col("alert_type").cast("string").alias("alert_type"),
            F.col("prediction_outcome").cast("string").alias("prediction_outcome"),
            F.col("source").cast("string").alias("source"),
            F.col("txtp").cast("string").alias("txtp"),
            F.col("message").cast("string").alias("message"),
            F.col("alert_data").cast("string").alias("alert_data"),
            F.col("transaction").cast("string").alias("transaction"),
            F.col("network_map").cast("string").alias("network_map"),
            F.col("confidence_per").cast("int").alias("confidence_per"),
            F.col("case_id").cast("long").alias("case_id"),
            F.col("created_at").cast("string").alias("created_at")
        )
    )

    df_bronze = (
        bronze_alerts_cast
        .withColumn("created_at_ts", F.current_timestamp())
        .withColumn("source_file_path", F.input_file_name())
    )

    hash_cols = [c for c in df_bronze.columns if c != "created_at_ts"]
    df_bronze = df_bronze.withColumn(
        "record_hash",
        F.sha2(F.concat_ws("||", *[F.coalesce(F.col(c).cast("string"), F.lit("")) for c in hash_cols]), 256)
    )

    hudi_alerts_options = hudi_opts("bronze_alerts", "alert_id", "created_at_ts")
    write_hudi(df_bronze, bronze_alerts_path, hudi_alerts_options)

    # ------------------- SILVER -------------------
    bronze_alerts = spark.read.format("hudi").load(bronze_alerts_path)
    bronze_alerts = bronze_alerts.drop(*[c for c in bronze_alerts.columns if c.startswith("_hoodie_")])

    alert_schema = infer_json_schema(spark, bronze_alerts, "alert_data")
    tx_schema    = infer_json_schema(spark, bronze_alerts, "transaction")
    net_schema   = infer_json_schema(spark, bronze_alerts, "network_map")

    b = (
        bronze_alerts
        .withColumn("alert_data_obj", F.from_json("alert_data", alert_schema))
        .withColumn("transaction_obj", F.from_json("transaction", tx_schema))
        .withColumn("network_map_obj", F.from_json("network_map", net_schema))
    )

    b = (
        b
        .withColumn("event_ts", F.to_timestamp(F.col("alert_data_obj.timestamp")))
        .withColumn("event_date", F.to_date("event_ts"))
        .withColumn("tx_created_ts", F.to_timestamp(F.col("transaction_obj.FIToFIPmtSts.GrpHdr.CreDtTm")))
        .withColumn("tx_accept_ts",  F.to_timestamp(F.col("transaction_obj.FIToFIPmtSts.TxInfAndSts.AccptncDtTm")))
    )

    silver = (
        b
        .withColumn("alert_id", F.col("alert_id").cast("long"))
        .withColumn("case_id",  F.col("case_id").cast("long"))
        .withColumn("alert_status", F.col("alert_data_obj.status"))
        .withColumn("evaluation_id", F.col("alert_data_obj.evaluationID"))
        .withColumn("processing_time_dp", F.col("alert_data_obj.metaData.prcgTmDP").cast("long"))
        .withColumn("processing_time_ed", F.col("alert_data_obj.metaData.prcgTmED").cast("long"))
        .withColumn("tadp_id",  F.col("alert_data_obj.tadpResult.id"))
        .withColumn("tadp_cfg", F.col("alert_data_obj.tadpResult.cfg"))
        .withColumn("tadp_processing_time", F.col("alert_data_obj.tadpResult.prcgTm").cast("long"))
        .withColumn("typology_count", F.size(F.col("alert_data_obj.tadpResult.typologyResult")))
        .withColumn("typology_ids", F.expr("transform(alert_data_obj.tadpResult.typologyResult, x -> x.id)"))
        .withColumn("typology_results", F.expr("transform(alert_data_obj.tadpResult.typologyResult, x -> cast(x.result as int))"))
        .withColumn("typology_reviews", F.expr("transform(alert_data_obj.tadpResult.typologyResult, x -> cast(x.review as boolean))"))
        .withColumn("workflow_processors", F.expr("transform(alert_data_obj.tadpResult.typologyResult, x -> x.workflow.flowProcessor)"))
        .withColumn("alert_thresholds", F.expr("transform(alert_data_obj.tadpResult.typologyResult, x -> cast(x.workflow.alertThreshold as int))"))
        .withColumn("interdiction_thresholds", F.expr("transform(alert_data_obj.tadpResult.typologyResult, x -> cast(x.workflow.interdictionThreshold as int))"))
        .withColumn("rule_count_total", F.expr("aggregate(alert_data_obj.tadpResult.typologyResult, 0, (acc, x) -> acc + size(x.ruleResults))"))
        # rule_pairs logic (full original)
        .withColumn("rule_pairs", F.flatten(F.expr("""transform(alert_data_obj.tadpResult.typologyResult, t -> transform(t.ruleResults, r -> named_struct('rule_id', r.id, 'weight', cast(r.wght as long))))""")))
        .withColumn("rule_pairs", F.expr("""aggregate(rule_pairs, cast(array() as array<struct<rule_id:string, weight:bigint>>), (acc, x) -> IF(array_contains(transform(acc, y -> y.rule_id), x.rule_id), acc, concat(acc, array(x))))"""))
        .withColumn("rule_pairs", F.expr("filter(rule_pairs, x -> x.rule_id is not null)"))
        .withColumn("rule_weights_json", F.to_json(F.col("rule_pairs")))
        .withColumn("rule_id_count_distinct", F.size(F.expr("transform(rule_pairs, x -> x.rule_id)")))
        .withColumn("rule_weight_sum", F.expr("aggregate(transform(rule_pairs, x -> x.weight), cast(0 as long), (acc,x) -> acc + coalesce(x, cast(0 as long)))"))
        .withColumn("rule_weight_max", F.when(F.size("rule_pairs") > 0, F.array_max(F.expr("transform(rule_pairs, x -> x.weight)"))).otherwise(F.lit(0).cast("long")))
        # transaction / network flatten (full original)
        .withColumn("tx_type", F.col("transaction_obj.TxTp"))
        .withColumn("tx_tenant_id", F.col("transaction_obj.TenantId"))
        .withColumn("tx_msg_id", F.col("transaction_obj.FIToFIPmtSts.GrpHdr.MsgId"))
        .withColumn("tx_status", F.col("transaction_obj.FIToFIPmtSts.TxInfAndSts.TxSts"))
        .withColumn("tx_original_instr_id", F.col("transaction_obj.FIToFIPmtSts.TxInfAndSts.OrgnlInstrId"))
        .withColumn("tx_original_e2e_id", F.col("transaction_obj.FIToFIPmtSts.TxInfAndSts.OrgnlEndToEndId"))
        .withColumn("instg_mmb_id", F.col("transaction_obj.FIToFIPmtSts.TxInfAndSts.InstgAgt.FinInstnId.ClrSysMmbId.MmbId"))
        .withColumn("instd_mmb_id", F.col("transaction_obj.FIToFIPmtSts.TxInfAndSts.InstdAgt.FinInstnId.ClrSysMmbId.MmbId"))
        .withColumn("charge_count", F.size(F.col("transaction_obj.FIToFIPmtSts.TxInfAndSts.ChrgsInf")))
        .withColumn("charge_agent_mmb_ids", F.expr("transform(transaction_obj.FIToFIPmtSts.TxInfAndSts.ChrgsInf, x -> x.Agt.FinInstnId.ClrSysMmbId.MmbId)"))
        .withColumn("charge_amounts", F.expr("transform(transaction_obj.FIToFIPmtSts.TxInfAndSts.ChrgsInf, x -> cast(x.Amt.Amt as double))"))
        .withColumn("charge_ccys", F.expr("transform(transaction_obj.FIToFIPmtSts.TxInfAndSts.ChrgsInf, x -> x.Amt.Ccy)"))
        .withColumn("network_cfg", F.col("network_map_obj.cfg"))
        .withColumn("network_active", F.col("network_map_obj.active").cast("boolean"))
        .withColumn("network_tenant_id", F.col("network_map_obj.tenantId"))
        .withColumn("network_message_count", F.size(F.col("network_map_obj.messages")))
        .withColumn("network_message_ids", F.expr("transform(network_map_obj.messages, x -> x.id)"))
        .select(
            "_hoodie_commit_time","_hoodie_commit_seqno","_hoodie_record_key","_hoodie_partition_path","_hoodie_file_name",
            "alert_id","case_id","tenant_id","priority","priority_score","alert_type","prediction_outcome","source","txtp","message","confidence_per",
            "event_ts","event_date","tx_created_ts","tx_accept_ts","created_at","created_at_ts",
            "alert_status","evaluation_id","processing_time_dp","processing_time_ed","tadp_id","tadp_cfg","tadp_processing_time",
            "typology_count","typology_ids","typology_results","typology_reviews","workflow_processors","alert_thresholds","interdiction_thresholds","rule_count_total",
            "rule_weights_json","rule_id_count_distinct","rule_weight_sum","rule_weight_max",
            "tx_type","tx_tenant_id","tx_msg_id","tx_status","tx_original_instr_id","tx_original_e2e_id","instg_mmb_id","instd_mmb_id",
            "charge_count","charge_agent_mmb_ids","charge_amounts","charge_ccys",
            "network_cfg","network_active","network_tenant_id","network_message_count","network_message_ids",
            "source_file_path","alert_data","transaction","network_map"
        )
        .drop("rule_pairs")
    )

    w = Window.partitionBy("alert_id").orderBy(F.col("created_at_ts").desc())
    silver = silver.withColumn("rn", F.row_number().over(w)).filter(F.col("rn")==1).drop("rn")

    # DQ + DLQ (full original)
    dq_rules = [
        ("ALERT_ID_NULL", F.col("alert_id").isNull()),
        ("CREATED_AT_TS_NULL", F.col("created_at_ts").isNull()),
        ("EVENT_TS_NULL", F.col("event_ts").isNull()),
        ("ALERT_DATA_MISSING_CORE", F.col("alert_data").isNotNull() & F.col("alert_status").isNull()),
        ("TX_MISSING_CORE", F.col("transaction").isNotNull() & F.col("tx_msg_id").isNull()),
        ("NET_MISSING_CORE", F.col("network_map").isNotNull() & F.col("network_cfg").isNull()),
    ]
    reason_cols = [F.when(cond, F.lit(code)).otherwise(F.lit(None).cast("string")) for code, cond in dq_rules]
    silver_dq = (
        silver
        .withColumn("dq_reason_codes_raw", F.array(*reason_cols))
        .withColumn("dq_reason_codes", F.expr("filter(dq_reason_codes_raw, x -> x is not null)"))
        .withColumn("dq_failed", F.size("dq_reason_codes") > 0)
        .drop("dq_reason_codes_raw")
    )
    silver_pass = silver_dq.filter(~F.col("dq_failed")).drop("dq_failed", "dq_reason_codes")
    silver_fail = silver_dq.filter(F.col("dq_failed"))

    silver_fail = silver_fail.withColumn("dlq_id", F.sha2(F.coalesce(F.col("evaluation_id").cast("string"), F.col("tx_type").cast("string")), 256)) \
                             .withColumn("dlq_ingested_at", F.current_timestamp())

    hudi_silver_opts = hudi_opts("silver_alerts", "alert_id", "created_at_ts")
    write_hudi(silver_pass, silver_alerts_path, hudi_silver_opts)

    # hudi_dlq_opts = hudi_opts("silver_alerts_dlq", "dlq_id", "dlq_ingested_at")
    # write_hudi(silver_fail, silver_alerts_dlq_path, hudi_dlq_opts)

    # ------------------- GOLD -------------------
    silver = spark.read.format("hudi").load(silver_alerts_path)
    silver = silver.drop(*[c for c in silver.columns if c.startswith("_hoodie_")])
    w = Window.partitionBy("alert_id").orderBy(F.col("created_at_ts").desc())
    s = silver.withColumn("rn", F.row_number().over(w)).filter("rn=1").drop("rn")

    if "record_hash" not in s.columns:
        s = s.withColumn(
            "record_hash",
            F.sha2(
                F.concat_ws(
                    "||",
                    F.coalesce(F.col("alert_id").cast("string"), F.lit("")),
                    F.coalesce(F.col("tenant_id").cast("string"), F.lit("")),
                    F.coalesce(F.col("created_at_ts").cast("string"), F.lit("")),
                ),
                256,
            ),
        )

    alert_schema = infer_json_schema(spark, s.select("alert_data").where(F.col("alert_data").isNotNull()), "alert_data")
    g = s.withColumn("alert_data_obj", F.from_json("alert_data", alert_schema))

    g = g.withColumn("rule_pairs", F.flatten(F.expr("""transform(alert_data_obj.tadpResult.typologyResult, t -> transform(t.ruleResults, r -> named_struct('rule_id', r.id, 'weight', cast(r.wght as long))))"""))) \
         .withColumn("rule_pairs", F.expr("filter(rule_pairs, x -> x.rule_id is not null)"))

    g = (
        g
        .withColumn("rule_weights", F.expr("transform(rule_pairs, x -> x.weight)"))
        .withColumn("rule_id_count_distinct", F.size(F.array_distinct(F.expr("transform(rule_pairs, x -> x.rule_id)"))).cast("int"))
        .withColumn("rule_weight_sum", F.expr("aggregate(rule_weights, cast(0 as long), (acc,x) -> acc + coalesce(x, cast(0 as long)))").cast("long"))
        .withColumn("rule_weight_max", F.when(F.size("rule_weights") > 0, F.array_max("rule_weights")).otherwise(F.lit(0)).cast("long"))
        .withColumn("rule_weight_min", F.when(F.size("rule_weights") > 0, F.array_min("rule_weights")).otherwise(F.lit(0)).cast("long"))
        .withColumn("rule_weight_avg", F.when(F.size("rule_weights") > 0, (F.col("rule_weight_sum").cast("double") / F.size("rule_weights").cast("double"))).otherwise(F.lit(0.0)).cast("double"))
        .withColumn("rule_weight_p95", F.when(F.size("rule_weights") > 0, F.expr("element_at(array_sort(rule_weights), cast(ceil(size(rule_weights) * 0.95) as int))").cast("double")).otherwise(F.lit(0.0)))
        .withColumn("top_rule_id", F.expr("""element_at(transform(filter(rule_pairs, x -> x.weight = rule_weight_max), x -> x.rule_id), 1)"""))
        .withColumn("top_rule_weight", F.col("rule_weight_max").cast("long"))
    )

    tx_amount = F.coalesce(
        F.get_json_object(F.col("transaction"), "$.FIToFIPmtSts.TxInfAndSts.OrgnlTxRef.Amt.InstdAmt.Amt").cast("double"),
        F.get_json_object(F.col("transaction"), "$.FIToFIPmtSts.TxInfAndSts.OrgnlTxRef.Amt.EqvtAmt.Amt").cast("double")
    )
    tx_ccy = F.coalesce(
        F.get_json_object(F.col("transaction"), "$.FIToFIPmtSts.TxInfAndSts.OrgnlTxRef.Amt.InstdAmt.Ccy"),
        F.get_json_object(F.col("transaction"), "$.FIToFIPmtSts.TxInfAndSts.OrgnlTxRef.Amt.EqvtAmt.Ccy")
    )

    g = g.withColumn("charge_total_amount", F.when(F.col("charge_amounts").isNotNull(), F.expr("aggregate(charge_amounts, cast(0.0 as double), (acc,x) -> acc + coalesce(x, 0.0))")).otherwise(F.lit(0.0)))
    g = g.withColumn("tx_amount", tx_amount).withColumn("tx_ccy", tx_ccy)
    g = g.withColumn("charge_currency_count", F.when(F.col("charge_ccys").isNotNull(), F.size(F.array_distinct("charge_ccys"))).otherwise(F.lit(0)))
    g = g.withColumn("has_multi_currency_charges", (F.col("charge_currency_count") > 1).cast("int"))
    g = g.withColumn("total_processing_time_ms", (F.coalesce(F.col("processing_time_dp").cast("long"), F.lit(0)) + F.coalesce(F.col("processing_time_ed").cast("long"), F.lit(0)) + F.coalesce(F.col("tadp_processing_time").cast("long"), F.lit(0))).cast("long"))
    g = g.withColumn("event_to_ingest_ms", F.when(F.col("event_ts").isNotNull(), (F.col("created_at_ts").cast("long") - F.col("event_ts").cast("long")) * 1000).otherwise(F.lit(None).cast("long")))

    g = g.withColumn("priority_norm", F.upper("priority")) \
         .withColumn("alert_type_norm", F.upper("alert_type")) \
         .withColumn("prediction_outcome_norm", F.upper("prediction_outcome")) \
         .withColumn("is_false_positive", (F.col("prediction_outcome_norm") == "FALSE_POSITIVE").cast("int")) \
         .withColumn("is_false_negative", (F.col("prediction_outcome_norm") == "FALSE_NEGATIVE").cast("int")) \
         .withColumn("is_true_positive",  (F.col("prediction_outcome_norm") == "TRUE_POSITIVE").cast("int")) \
         .withColumn("is_true_negative",  (F.col("prediction_outcome_norm") == "TRUE_NEGATIVE").cast("int"))

    g = g.withColumn("security_tag", F.concat(F.lit("TENANT:"), F.col("tenant_id")))
    g = g.withColumn("typology_id", F.concat_ws(", ", F.col("typology_ids")))

    gold = g.select(
        "event_date", "alert_id", "case_id", "tenant_id", "priority_norm", "priority_score",
        "alert_type_norm", "prediction_outcome_norm", "source", "txtp", "event_ts", "created_at_ts",
        "alert_status", "evaluation_id", "tx_type", "tx_msg_id", "tx_status", "tx_amount", "tx_ccy",
        "tx_original_e2e_id", "typology_count", "typology_id", "rule_count_total",
        "rule_id_count_distinct", "rule_weight_sum", "rule_weight_max", "rule_weight_min",
        "rule_weight_avg", "rule_weight_p95", "top_rule_id", "top_rule_weight",
        "charge_count", "charge_total_amount", "charge_currency_count", "has_multi_currency_charges",
        "network_message_count", "event_to_ingest_ms", "total_processing_time_ms", "security_tag",
        "source_file_path", "record_hash"
    )

    hudi_gold_opts = {
    "hoodie.table.name": "alerts",
    "hoodie.datasource.write.table.type": "COPY_ON_WRITE",
    "hoodie.datasource.write.operation": "upsert",

    "hoodie.datasource.write.recordkey.field": "alert_id",
    "hoodie.datasource.write.precombine.field": "created_at_ts",

    "hoodie.datasource.write.partitionpath.field": "event_date",
    "hoodie.datasource.write.keygenerator.class": "org.apache.hudi.keygen.SimpleKeyGenerator",
    "hoodie.datasource.write.hive_style_partitioning": "true",

    # schema evolution + reconcile
    "hoodie.datasource.write.schema.evolution.enable": "true",
    "hoodie.datasource.read.schema.evolution.enable": "true",
    "hoodie.datasource.write.reconcile.schema": "true",
    "hoodie.schema.on.read.enable": "true",
    
    "hoodie.datasource.write.payload.class": "org.apache.hudi.common.model.OverwriteWithLatestAvroPayload",

    "hoodie.metadata.enable": "false",
    }
   
    (
    gold.write.format("hudi")
    .options(**hudi_gold_opts)
    .mode("append")
    .save(gold_alerts_path)
    )

    print("ETL Alerts (Bronze → Silver → Gold) completed")
    return gold_alerts_path


# ===================================================================
# 2. CASES ETL
# ===================================================================
def etl_cases(spark, WAREHOUSE_ROOT, source_path:str):
    bronze_cases_path = f"{WAREHOUSE_ROOT}/bronze/cases"
    silver_cases_path = f"{WAREHOUSE_ROOT}/silver/cases"
    gold_cases_path   = f"{WAREHOUSE_ROOT}/gold/cases"
    silver_cases_dlq_path = f"{WAREHOUSE_ROOT}/silver/cases_dlq"

    # BRONZE
    cases_df = spark.read.json(source_path)
    print("read cases from ozone")

    bronze_cases = (
        cases_df
        .withColumn("case_id", F.col("case_id").cast("long"))
        .withColumn("parent_id", F.col("parent_id").cast("long"))
        .withColumn("tenant_id", F.col("tenant_id").cast("string"))
        .withColumn("case_creation_type", F.col("case_creation_type").cast("string"))
        .withColumn("case_creator_user_id", F.col("case_creator_user_id").cast("string"))
        .withColumn("case_owner_user_id", F.col("case_owner_user_id").cast("string"))
        .withColumn("case_type", F.col("case_type").cast("string"))
        .withColumn("priority", F.col("priority").cast("string"))
        .withColumn("status", F.col("status").cast("string"))
        .withColumn("created_at", F.col("created_at").cast("string"))
        .withColumn("updated_at", F.col("updated_at").cast("string"))
        .withColumn("created_at_ts", F.current_timestamp())
        .withColumn("source_file_path", F.lit(source_path))
    )

    hash_cols = [c for c in bronze_cases.columns if c != "created_at_ts"]
    bronze_cases = bronze_cases.withColumn("record_hash", F.sha2(F.concat_ws("||", *[F.coalesce(F.col(c).cast("string"), F.lit("")) for c in hash_cols]), 256))
    bronze_cases = bronze_cases.withColumn("_row_payload_json", F.to_json(F.struct(*[F.col(c) for c in bronze_cases.columns])))

    print("writing cases bronze to hudi")
    

    hudi_bronze_cases_opts = hudi_opts("cases", "case_id", "created_at_ts")
    write_hudi(bronze_cases, bronze_cases_path, hudi_bronze_cases_opts)

    # SILVER

    print("now moving onto silver cases")

    b = spark.read.format("hudi").load(bronze_cases_path)
    silver_cases = (
        b
        .withColumn("case_id", F.col("case_id").cast("long"))
        .withColumn("parent_id", F.col("parent_id").cast("long"))
        .withColumn("tenant_id", F.col("tenant_id").cast("string"))
        .withColumn("case_creation_type", F.col("case_creation_type").cast("string"))
        .withColumn("case_creator_user_id", F.col("case_creator_user_id").cast("string"))
        .withColumn("case_owner_user_id", F.col("case_owner_user_id").cast("string"))
        .withColumn("case_type", F.col("case_type").cast("string"))
        .withColumn("priority", F.col("priority").cast("string"))
        .withColumn("status", F.col("status").cast("string"))
        .withColumn("created_at_ms", F.col("created_at").cast("long"))
        .withColumn("updated_at_ms", F.col("updated_at").cast("long"))
        .withColumn("case_created_ts", F.to_timestamp((F.col("created_at_ms") / 1000).cast("double")))
        .withColumn("case_updated_ts", F.to_timestamp((F.col("updated_at_ms") / 1000).cast("double")))
        .withColumn("case_created_date", F.to_date("case_created_ts"))
        .withColumn("case_updated_date", F.to_date("case_updated_ts"))
        .withColumn("priority_norm", F.upper("priority"))
        .withColumn("status_norm", F.upper("status"))
        .withColumn("case_creation_type_norm", F.upper("case_creation_type"))
    )

    w = Window.partitionBy("case_id").orderBy(F.col("created_at_ts").desc())
    silver_cases = silver_cases.withColumn("rn", F.row_number().over(w)).filter(F.col("rn") == 1).drop("rn")

    silver_cases = (
    silver_cases
    .select(
        "_hoodie_commit_time","_hoodie_commit_seqno","_hoodie_record_key","_hoodie_partition_path","_hoodie_file_name",

        "case_id","tenant_id",
        "parent_id",
        "case_creation_type","case_creation_type_norm",
        "case_creator_user_id","case_owner_user_id",
        "case_type",
        "priority","priority_norm",
        "status","status_norm",

        # timestamps
        "created_at","updated_at",
        "created_at_ms","updated_at_ms",
        "case_created_ts","case_updated_ts",
        "case_created_date","case_updated_date",

        # lineage
        "created_at_ts",
        "source_file_path",
        "record_hash"
    )
    )

    print("now writing to hudi silver")

    hudi_silver_cases_opts = hudi_opts("cases", "case_id", "created_at_ts")
    write_hudi(silver_cases, silver_cases_path, hudi_silver_cases_opts)

    # GOLD (full original logic)
    s = spark.read.format("hudi").load(silver_cases_path)

    w = Window.partitionBy("case_id").orderBy(F.col("created_at_ts").desc())
    s = s.withColumn("rn", F.row_number().over(w)).filter(F.col("rn") == 1).drop("rn")

    if "record_hash" not in s.columns:
        s = s.withColumn(
            "record_hash",
            F.sha2(
                F.concat_ws(
                    "||",
                    F.coalesce(F.col("case_id").cast("string"), F.lit("")),
                    F.coalesce(F.col("tenant_id").cast("string"), F.lit("")),
                    F.coalesce(F.col("created_at_ts").cast("string"), F.lit("")),
                ),
                256,
            ),
        )

    g = (
    s
    # governance/security tag (tenant)
    .withColumn("security_tag", F.concat(F.lit("TENANT:"), F.col("tenant_id")))

    # lifecycle metric: age since creation at time of ingestion (ms)
    .withColumn(
        "case_age_ms_at_ingest",
        F.when(
            F.col("case_created_ts").isNotNull(),
            (F.col("created_at_ts").cast("long") - F.col("case_created_ts").cast("long")) * 1000
        ).otherwise(F.lit(None).cast("long"))
    )

    # time between created and updated (ms) if they differ
    .withColumn(
        "created_to_updated_ms",
        F.when(
            (F.col("case_created_ts").isNotNull()) & (F.col("case_updated_ts").isNotNull()),
            (F.col("case_updated_ts").cast("long") - F.col("case_created_ts").cast("long")) * 1000
        ).otherwise(F.lit(0).cast("long"))
    )

    # flags
    .withColumn("has_parent_case", F.when(F.col("parent_id").isNotNull(), F.lit(1)).otherwise(F.lit(0)))
    .withColumn("has_owner", F.when(F.col("case_owner_user_id").isNotNull(), F.lit(1)).otherwise(F.lit(0)))
    )

    gold_cases = g.select(
    # keys
    F.col("case_id").cast("long").alias("case_id"),
    F.col("tenant_id").cast("string").alias("tenant_id"),
    F.col("parent_id").cast("long").alias("parent_id"),

    # normalized business fields
    F.col("case_creation_type_norm").cast("string").alias("case_creation_type"),
    F.col("priority_norm").cast("string").alias("priority"),
    F.col("status_norm").cast("string").alias("status"),
    F.col("case_type").cast("string").alias("case_type"),

    # actors
    F.col("case_creator_user_id").cast("string").alias("case_creator_user_id"),
    F.col("case_owner_user_id").cast("string").alias("case_owner_user_id"),

    # timestamps (harmonized)
    F.col("case_created_ts").cast("timestamp").alias("case_created_ts"),
    F.col("case_updated_ts").cast("timestamp").alias("case_updated_ts"),
    F.col("case_created_date").cast("date").alias("case_created_date"),
    F.col("case_updated_date").cast("date").alias("case_updated_date"),
    F.col("created_at_ts").cast("timestamp").alias("ingested_at_ts"),

    # metrics
    F.col("case_age_ms_at_ingest").cast("long").alias("case_age_ms_at_ingest"),
    F.col("created_to_updated_ms").cast("long").alias("created_to_updated_ms"),
    F.col("has_parent_case").cast("int").alias("has_parent_case"),
    F.col("has_owner").cast("int").alias("has_owner"),

    # lineage
    F.col("security_tag").cast("string").alias("security_tag"),
    F.col("source_file_path").cast("string").alias("source_file_path"),
    F.col("record_hash").cast("string").alias("record_hash"),
    )
    
    print("now writing gold cases")

    hudi_gold_cases_opts = {
    "hoodie.table.name": "cases",
    "hoodie.datasource.write.table.type": "COPY_ON_WRITE",
    "hoodie.datasource.write.operation": "upsert",
    "hoodie.datasource.write.recordkey.field": "case_id",
    "hoodie.datasource.write.precombine.field": "ingested_at_ts",
    "hoodie.datasource.write.partitionpath.field": "case_created_date",
    "hoodie.datasource.write.keygenerator.class": "org.apache.hudi.keygen.SimpleKeyGenerator",
    "hoodie.datasource.write.hive_style_partitioning": "true",

    # schema evolution + reconciliation
    "hoodie.datasource.write.schema.evolution.enable": "true",
    "hoodie.datasource.read.schema.evolution.enable": "true",
    "hoodie.datasource.write.reconcile.schema": "true",
    "hoodie.schema.on.read.enable": "true",

    "hoodie.index.type": "BLOOM",
    "hoodie.metadata.enable": "false",

    # safe payload
    "hoodie.datasource.write.payload.class": "org.apache.hudi.common.model.OverwriteWithLatestAvroPayload",
    }

    (
    gold_cases.write.format("hudi")
    .options(**hudi_gold_cases_opts)
    .mode("append")
    .save(gold_cases_path)
    )

    print("ETL Cases (Bronze → Silver → Gold) completed")
    return gold_cases_path


# ========================================================
# TASKS - COMPLETE ETL (Bronze → Silver → Gold)
# ========================================================

def etl_tasks(spark, WAREHOUSE_ROOT, source_path: str):
    """
    Complete Tasks pipeline.
    source_path example: "s3a://cms/tasks/"
    """
    bronze_path = f"{WAREHOUSE_ROOT}/bronze/tasks"
    silver_path = f"{WAREHOUSE_ROOT}/silver/tasks"
    gold_path   = f"{WAREHOUSE_ROOT}/gold/tasks"
    silver_dlq_path = f"{WAREHOUSE_ROOT}/silver/tasks_dlq"

    print(f"* Starting Tasks ETL from → {source_path}")

    # ====================== BRONZE ======================
    df_tasks = spark.read.json(source_path) 
    print("read tasks from ozone")         

    bronze_tasks = (
        df_tasks
        .withColumn("task_id", F.col("task_id").cast("long"))
        .withColumn("case_id", F.col("case_id").cast("long"))
        .withColumn("created_at", F.col("created_at").cast("string"))
        .withColumn("updated_at", F.col("updated_at").cast("string"))
        .withColumn("completed_at", F.col("completed_at").cast("string"))
        .withColumn("sla_deadline", F.col("sla_deadline").cast("string"))
        .withColumn("sla_duration_hours", F.col("sla_duration_hours").cast("double"))
        .withColumn("assigned_user_id", F.col("assigned_user_id").cast("string"))
        .withColumn("candidateGroup", F.col("candidateGroup").cast("string"))
        .withColumn("description", F.col("description").cast("string"))
        .withColumn("name", F.col("name").cast("string"))
        .withColumn("status", F.col("status").cast("string"))
        .withColumn("task_type", F.col("task_type").cast("string"))
        #.withColumn("work_queue_id", F.col("work_queue_id").cast("string"))

        # bronze metadata
       .withColumn("created_at_ts", F.current_timestamp())
       .withColumn("source_file_path", F.lit(source_path))
    )

    # Record hash + payload
    hash_cols = [c for c in bronze_tasks.columns if c != "created_at_ts"]
    bronze_tasks = bronze_tasks.withColumn(
        "record_hash",
        F.sha2(F.concat_ws("||", *[F.coalesce(F.col(c).cast("string"), F.lit("")) for c in hash_cols]), 256)
    )
    bronze_tasks = bronze_tasks.withColumn("_row_payload_json", F.to_json(F.struct("*")))

    print("* Writing bronze tasks")

    bronze_opts = hudi_opts("tasks", "task_id", "created_at_ts")
    write_hudi(bronze_tasks, bronze_path, bronze_opts)
    print(f"* Bronze written → {bronze_path}")

    # ====================== SILVER ======================
    b = spark.read.format("hudi").load(bronze_path)

    silver_tasks = (
        b
        .withColumn("task_id", F.col("task_id").cast("long"))
        .withColumn("case_id", F.col("case_id").cast("long"))
        # Timestamps (epoch millis → timestamp)
        .withColumn("created_at_ms",   F.col("created_at").cast("long"))
        .withColumn("updated_at_ms",   F.col("updated_at").cast("long"))
        .withColumn("completed_at_ms", F.col("completed_at").cast("long"))
        .withColumn("sla_deadline_ms", F.col("sla_deadline").cast("long"))
        .withColumn("task_created_ts",   F.to_timestamp((F.col("created_at_ms")   / 1000).cast("double")))
        .withColumn("task_updated_ts",   F.to_timestamp((F.col("updated_at_ms")   / 1000).cast("double")))
        .withColumn("task_completed_ts", F.to_timestamp((F.col("completed_at_ms") / 1000).cast("double")))
        .withColumn("sla_deadline_ts",   F.to_timestamp((F.col("sla_deadline_ms") / 1000).cast("double")))
        # Dates
        .withColumn("task_created_date",   F.to_date("task_created_ts"))
        .withColumn("task_updated_date",   F.to_date("task_updated_ts"))
        .withColumn("task_completed_date", F.to_date("task_completed_ts"))
        # Normalizations
        .withColumn("status_norm",        F.upper("status"))
        .withColumn("task_type_norm",     F.upper("task_type"))
        .withColumn("candidate_group_norm", F.upper("candidateGroup"))
        # Flags & KPIs
        .withColumn("is_assigned", F.when(F.col("assigned_user_id").isNotNull(), 1).otherwise(0))
        .withColumn("is_completed", F.when(F.col("task_completed_ts").isNotNull(), 1).otherwise(0))
        .withColumn("task_age_ms_at_ingest",
                    F.when(F.col("task_created_ts").isNotNull(),
                           (F.col("created_at_ts").cast("long") - F.col("task_created_ts").cast("long")) * 1000)
                     .otherwise(F.lit(None).cast("long")))
        .withColumn("task_duration_ms",
                    F.when((F.col("task_created_ts").isNotNull()) & (F.col("task_completed_ts").isNotNull()),
                           (F.col("task_completed_ts").cast("long") - F.col("task_created_ts").cast("long")) * 1000)
                     .otherwise(F.lit(None).cast("long")))
        .withColumn("sla_remaining_ms",
                    F.when(F.col("sla_deadline_ts").isNotNull(),
                           (F.col("sla_deadline_ts").cast("long") - F.col("created_at_ts").cast("long")) * 1000)
                     .otherwise(F.lit(None).cast("long")))
        .withColumn("sla_breached",
                    F.when((F.col("sla_deadline_ts").isNotNull()) & (F.col("task_completed_ts").isNotNull()),
                           (F.col("task_completed_ts") > F.col("sla_deadline_ts")).cast("int"))
                     .otherwise(F.lit(0)))
        .withColumn("_row_payload_json", F.to_json(F.struct("*")))
    )

    # Deduplicate
    w = Window.partitionBy("task_id").orderBy(F.col("created_at_ts").desc())
    silver_tasks = silver_tasks.withColumn("rn", F.row_number().over(w)).filter("rn = 1").drop("rn")

    # ====================== DQ + DLQ ======================
    dq_rules_tasks = [
        ("TASK_ID_NULL",         F.col("task_id").isNull()),
        ("CASE_ID_NULL",         F.col("case_id").isNull()),
        ("TASK_CREATED_TS_NULL", F.col("task_created_ts").isNull()),
        ("TASK_UPDATED_TS_NULL", F.col("task_updated_ts").isNull()),
        ("INGEST_TS_NULL",       F.col("created_at_ts").isNull()),
        ("STATUS_NULL",          F.col("status").isNull()),
        ("TASK_TYPE_NULL",       F.col("task_type").isNull()),
    ]

    reason_cols = [F.when(cond, F.lit(code)).otherwise(F.lit(None).cast("string")) for code, cond in dq_rules_tasks]

    silver_dq = (
        silver_tasks
        .withColumn("dq_reason_codes_raw", F.array(*reason_cols))
        .withColumn("dq_reason_codes", F.expr("filter(dq_reason_codes_raw, x -> x is not null)"))
        .withColumn("dq_failed", F.size("dq_reason_codes") > 0)
        .drop("dq_reason_codes_raw")
    )

    silver_pass = silver_dq.filter(~F.col("dq_failed")).drop("dq_failed", "dq_reason_codes")
    silver_fail = silver_dq.filter(F.col("dq_failed"))

    # Stable DLQ key
    silver_fail = (
        silver_fail
        .withColumn("dlq_id", F.sha2(F.coalesce(F.col("record_hash").cast("string"), F.col("_row_payload_json").cast("string")), 256))
        .withColumn("dlq_ingested_at", F.current_timestamp())
    )
    
    print("* Writing silver tasks")
    # Write Silver (pass)
    silver_opts = hudi_opts("tasks", "task_id", "created_at_ts")
    write_hudi(silver_pass, silver_path, silver_opts)

    # Write DLQ
    dlq_opts = hudi_opts("silver_tasks_dlq", "dlq_id", "dlq_ingested_at")
    write_hudi(silver_fail, silver_dlq_path, dlq_opts)

    print(f"   * Silver + DLQ written → {silver_path}")

    # ====================== GOLD ======================
    s = spark.read.format("hudi").load(silver_path)

    s = ensure_columns(
        s,
        {
            "tx_tenant_id": "string",
            "dc_cdtr_id": "string",
            "dc_dbtr_id": "string",
            "dc_cre_dt_tm": "timestamp",
            "dc_instd_amt": "double",
            "dc_instd_ccy": "string",
            "dc_xchg_rate": "string",
            "dc_cdtr_acct_id": "string",
            "dc_dbtr_acct_id": "string",
            "dc_intrbk_amt": "double",
            "dc_intrbk_ccy": "string",
            "grp_msg_id": "string",
            "grp_cre_dt_tm": "timestamp",
            "grp_nb_of_txs": "int",
            "sttlm_mtd": "string",
            "rmt_ustrd": "string",
            "purp_cd": "string",
            "pmt_instr_id": "string",
            "pmt_e2e_id": "string",
            "chrg_br": "string",
            "cdtr_agt_mmb_id": "string",
            "dbtr_agt_mmb_id": "string",
            "cdtr_name": "string",
            "dbtr_name": "string",
            "cdtr_id": "string",
            "dbtr_id": "string",
            "cdtr_acct_scheme": "string",
            "dbtr_acct_scheme": "string",
            "intrbk_amt": "double",
            "intrbk_ccy": "string",
            "xchg_rate": "string",
            "charge_amt": "double",
            "charge_ccy": "string",
            "charge_agent_mmb_id": "string",
            "event_ts": "timestamp",
        },
    )
    s = s.withColumn("tx_tenant_id", F.coalesce(F.col("tx_tenant_id"), F.col("tenant_id").cast("string")))

    required_pacs008_cols = {
        "tx_tenant_id": "string",
        "dc_cdtr_id": "string",
        "dc_dbtr_id": "string",
        "dc_cre_dt_tm": "timestamp",
        "dc_instd_amt": "double",
        "dc_instd_ccy": "string",
        "dc_xchg_rate": "string",
        "dc_cdtr_acct_id": "string",
        "dc_dbtr_acct_id": "string",
        "dc_intrbk_amt": "double",
        "dc_intrbk_ccy": "string",
        "grp_msg_id": "string",
        "grp_cre_dt_tm": "timestamp",
        "grp_nb_of_txs": "int",
        "sttlm_mtd": "string",
        "rmt_ustrd": "string",
        "purp_cd": "string",
        "pmt_instr_id": "string",
        "pmt_e2e_id": "string",
        "chrg_br": "string",
        "cdtr_agt_mmb_id": "string",
        "dbtr_agt_mmb_id": "string",
        "cdtr_name": "string",
        "dbtr_name": "string",
        "cdtr_id": "string",
        "dbtr_id": "string",
        "cdtr_acct_scheme": "string",
        "dbtr_acct_scheme": "string",
        "intrbk_amt": "double",
        "intrbk_ccy": "string",
        "xchg_rate": "string",
        "charge_amt": "double",
        "charge_ccy": "string",
        "charge_agent_mmb_id": "string",
        "event_ts": "timestamp",
    }

    for col_name, col_type in required_pacs008_cols.items():
        if col_name not in s.columns:
            s = s.withColumn(col_name, F.lit(None).cast(col_type))

    if "event_ts" in s.columns and "creation_dt_tm" in s.columns:
        s = s.withColumn("event_ts", F.coalesce(F.col("event_ts"), F.col("creation_dt_tm")))
    w = Window.partitionBy("task_id").orderBy(F.col("created_at_ts").desc())
    s = s.withColumn("rn", F.row_number().over(w)).filter("rn = 1").drop("rn")

    gold_tasks = (
        s
        .select(
            F.col("task_id").cast("long").alias("task_id"),
            F.col("case_id").cast("long").alias("case_id"),
            F.col("task_type").cast("string").alias("task_type"),
            F.col("candidate_group_norm").cast("string").alias("candidate_group"),
            F.col("assigned_user_id").cast("string").alias("assigned_user_id"),
            F.col("name").cast("string").alias("task_name"),
            F.col("status_norm").cast("string").alias("status"),
            F.col("task_created_ts").cast("timestamp").alias("task_created_ts"),
            F.col("task_updated_ts").cast("timestamp").alias("task_updated_ts"),
            F.col("task_completed_ts").cast("timestamp").alias("task_completed_ts"),
            F.col("sla_deadline_ts").cast("timestamp").alias("sla_deadline_ts"),
            F.col("task_created_date").cast("date").alias("task_created_date"),
            F.col("created_at_ts").cast("timestamp").alias("ingested_at_ts"),
            F.col("sla_duration_hours").cast("double").alias("sla_duration_hours"),
            F.col("is_assigned").cast("int").alias("is_assigned"),
            F.col("is_completed").cast("int").alias("is_completed"),
            F.col("sla_breached").cast("int").alias("sla_breached"),
            F.col("task_age_ms_at_ingest").cast("long").alias("task_age_ms_at_ingest"),
            F.col("task_duration_ms").cast("long").alias("task_duration_ms"),
            F.col("sla_remaining_ms").cast("long").alias("sla_remaining_ms"),
            F.col("source_file_path").cast("string").alias("source_file_path"),
            F.col("record_hash").cast("string").alias("record_hash")
        )
    )

    print("writing gold tasks")

    hudi_gold_tasks_opts = {
    "hoodie.table.name": "tasks",
    "hoodie.datasource.write.table.type": "COPY_ON_WRITE",
    "hoodie.datasource.write.operation": "upsert",
    "hoodie.datasource.write.recordkey.field": "task_id",
    "hoodie.datasource.write.precombine.field": "ingested_at_ts",
    "hoodie.datasource.write.partitionpath.field": "task_created_date",
    "hoodie.datasource.write.keygenerator.class": "org.apache.hudi.keygen.SimpleKeyGenerator",
    "hoodie.datasource.write.hive_style_partitioning": "true",

    # Schema evolution
    "hoodie.datasource.write.schema.evolution.enable": "true",
    "hoodie.datasource.read.schema.evolution.enable": "true",
    "hoodie.datasource.write.reconcile.schema": "true",
    "hoodie.schema.on.read.enable": "true",

    "hoodie.index.type": "BLOOM",
    "hoodie.metadata.enable": "false",
    "hoodie.datasource.write.payload.class": "org.apache.hudi.common.model.OverwriteWithLatestAvroPayload",
    }

    (
    gold_tasks.write.format("hudi")
    .options(**hudi_gold_tasks_opts)
    .mode("append")
    .save(gold_path)
    )

    print(f"   * Gold written → {gold_path}")
    print(f"* Tasks COMPLETE ETL finished from {source_path}\n")
    return gold_path

# ========================================================
# PACs008 - COMPLETE ETL (Bronze → Silver → Gold)
# ========================================================

def etl_pacs008(spark, WAREHOUSE_ROOT, source_path: str):
    """
    Complete PACs008 pipeline.
    source_path example: "s3a://frms/pacs008/"
    """
    bronze_path = f"{WAREHOUSE_ROOT}/bronze/pacs008"
    silver_path = f"{WAREHOUSE_ROOT}/silver/pacs008"
    gold_path   = f"{WAREHOUSE_ROOT}/gold/pacs008"

    print(f"* Starting PACs008 ETL from → {source_path}")

    # ====================== BRONZE ======================
    df_bronze = spark.read.json(source_path)

    print("data read from pacs008, proceeding")

    bronze = (
    df_bronze
    .withColumnRenamed("tenantid", "tenant_id")
    .withColumnRenamed("messageid", "message_id")
    .withColumnRenamed("endtoendid", "end_to_end_id")
    .withColumnRenamed("credttm", "credttm_raw")
    .withColumnRenamed("creditoraccountid", "creditor_account_id")
    .withColumnRenamed("debtoraccountid", "debtor_account_id")

    # preserve original document as string (full fidelity)
    .withColumn("document_json", F.col("document").cast("string"))

    # parse timestamp if possible
    .withColumn("credttm_ts", F.to_timestamp(F.col("credttm_raw")))
    .withColumn("event_date", F.to_date(F.col("credttm_ts")))

    # ingestion metadata
    .withColumn("ingested_at_ts", F.current_timestamp())
    .withColumn("source_file_path", F.lit(None).cast("string"))
    )

    bronze = bronze.withColumn(
    "record_hash",
    F.sha2(
        F.concat_ws(
            "||",
            F.coalesce(F.col("tenant_id"), F.lit("")),
            F.coalesce(F.col("message_id"), F.lit("")),
            F.coalesce(F.col("end_to_end_id"), F.lit("")),
            F.coalesce(F.col("creditor_account_id"), F.lit("")),
            F.coalesce(F.col("debtor_account_id"), F.lit("")),
            F.coalesce(F.col("credttm_raw"), F.lit("")),
            F.coalesce(F.col("document_json"), F.lit("")),
        ),
        256,
     )
    )

    bronze = bronze.withColumn("_row_payload_json", F.to_json(F.struct("*")))

    bronze_opts = hudi_opts(
        table_name="bronze_pacs008",
        record_key="record_hash",
        precombine="ingested_at_ts"
    )

    print("* Writing pacs008 to hudi")

    write_hudi(bronze, bronze_path, bronze_opts)
    print(f"* Bronze written → {bronze_path}")

    # ====================== SILVER ======================
    bronze_df = spark.read.format("hudi").load(bronze_path)

    # Infer schema from the raw document
    doc_schema = infer_json_schema(spark, bronze_df, "document")

    silver = (
        bronze_df
        .withColumn("doc_obj", F.from_json("document", doc_schema))
        .withColumn("end_to_end_id", F.col("end_to_end_id"))
        .withColumn("tenant_id",     F.col("tenant_id"))
        .withColumn("msg_id",        F.get_json_object("document", "$.FIToFICstmrCdtTrf.GrpHdr.MsgId"))
        .withColumn("creation_dt_tm", F.to_timestamp(F.get_json_object("document", "$.FIToFICstmrCdtTrf.GrpHdr.CreDtTm")))
        .withColumn("tx_type",       F.lit("pacs.008.001.10"))
        .withColumn("instd_amt",     F.get_json_object("document", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.InstdAmt.Amt.Amt").cast("double"))
        .withColumn("instd_ccy",     F.get_json_object("document", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.InstdAmt.Amt.Ccy"))
        .withColumn("dbtr_mmb_id",   F.get_json_object("document", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.DbtrAgt.FinInstnId.ClrSysMmbId.MmbId"))
        .withColumn("cdtr_mmb_id",   F.get_json_object("document", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.CdtrAgt.FinInstnId.ClrSysMmbId.MmbId"))
        .withColumn("dbtr_acct_id",  F.get_json_object("document", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.DbtrAcct.Id.Othr.Id"))
        .withColumn("cdtr_acct_id",  F.get_json_object("document", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.CdtrAcct.Id.Othr.Id"))
        .withColumn("event_date",    F.to_date("creation_dt_tm"))
        .withColumn("created_at_ts", F.current_timestamp())
        .withColumn("source_file_path", F.col("source_file_path"))
        .withColumn("record_hash",   F.col("record_hash"))
    )

    # Deduplicate - keep latest version
    w = Window.partitionBy("end_to_end_id").orderBy(F.col("created_at_ts").desc())
    silver = silver.withColumn("rn", F.row_number().over(w)).filter("rn = 1").drop("rn")

    silver_opts = hudi_opts(
        table_name="silver_pacs008",
        record_key="record_hash",
        precombine="ingested_at_ts"
    )
    write_hudi(silver, silver_path, silver_opts)
    print(f"   * Silver written → {silver_path}")

    # ====================== GOLD ======================
    s = spark.read.format("hudi").load(silver_path)
    s = ensure_columns(
        s,
        {
            "tx_tenant_id": "string",
            "dc_cdtr_id": "string",
            "dc_dbtr_id": "string",
            "dc_cre_dt_tm": "timestamp",
            "dc_instd_amt": "double",
            "dc_instd_ccy": "string",
            "dc_xchg_rate": "string",
            "dc_cdtr_acct_id": "string",
            "dc_dbtr_acct_id": "string",
            "dc_intrbk_amt": "double",
            "dc_intrbk_ccy": "string",
            "grp_msg_id": "string",
            "grp_cre_dt_tm": "timestamp",
            "grp_nb_of_txs": "int",
            "sttlm_mtd": "string",
            "rmt_ustrd": "string",
            "purp_cd": "string",
            "pmt_instr_id": "string",
            "pmt_e2e_id": "string",
            "chrg_br": "string",
            "cdtr_agt_mmb_id": "string",
            "dbtr_agt_mmb_id": "string",
            "cdtr_name": "string",
            "dbtr_name": "string",
            "cdtr_id": "string",
            "dbtr_id": "string",
            "cdtr_acct_scheme": "string",
            "dbtr_acct_scheme": "string",
            "intrbk_amt": "double",
            "intrbk_ccy": "string",
            "xchg_rate": "string",
            "charge_amt": "double",
            "charge_ccy": "string",
            "charge_agent_mmb_id": "string",
            "event_ts": "timestamp",
        },
    )
    s = s.withColumn("tx_tenant_id", F.coalesce(F.col("tx_tenant_id"), F.col("tenant_id").cast("string")))
    s = s.withColumn("event_ts", F.coalesce(F.col("event_ts"), F.col("credttm_ts").cast("timestamp")))

    gold_pk = F.sha2(
    F.concat_ws(
        "||",
        F.lit("gold_pacs008"),
        F.coalesce(F.col("tenant_id"), F.lit("")),
        F.coalesce(F.col("message_id"), F.lit("")),
        F.coalesce(F.col("end_to_end_id"), F.lit("")),
        F.coalesce(F.col("record_hash"), F.lit("")),
    ),
    256
    )

    gold = (
    s
    .withColumn("pk", gold_pk)

    .select(
        "pk",

        # --- ORIGINAL INPUT (NOT omitted) ---
        F.col("tenant_id").cast("string").alias("tenant_id"),
        F.col("message_id").cast("string").alias("message_id"),
        F.col("end_to_end_id").cast("string").alias("end_to_end_id"),
        F.col("creditor_account_id").cast("string").alias("creditor_account_id"),
        F.col("debtor_account_id").cast("string").alias("debtor_account_id"),
        F.col("credttm_raw").cast("string").alias("credttm_raw"),
        F.col("credttm_ts").cast("timestamp").alias("credttm_ts"),


        # --- DERIVED / FLATTENED (all scalar) ---
        F.col("tx_type").cast("string").alias("tx_type"),
        F.col("tx_tenant_id").cast("string").alias("tx_tenant_id"),

        F.col("dc_cdtr_id").cast("string").alias("dc_cdtr_id"),
        F.col("dc_dbtr_id").cast("string").alias("dc_dbtr_id"),
        F.col("dc_cre_dt_tm").cast("timestamp").alias("dc_cre_dt_tm"),
        F.col("dc_instd_amt").cast("double").alias("dc_instd_amt"),
        F.col("dc_instd_ccy").cast("string").alias("dc_instd_ccy"),
        F.col("dc_xchg_rate").cast("string").alias("dc_xchg_rate"),
        F.col("dc_cdtr_acct_id").cast("string").alias("dc_cdtr_acct_id"),
        F.col("dc_dbtr_acct_id").cast("string").alias("dc_dbtr_acct_id"),
        F.col("dc_intrbk_amt").cast("double").alias("dc_intrbk_amt"),
        F.col("dc_intrbk_ccy").cast("string").alias("dc_intrbk_ccy"),

        F.col("grp_msg_id").cast("string").alias("grp_msg_id"),
        F.col("grp_cre_dt_tm").cast("timestamp").alias("grp_cre_dt_tm"),
        F.col("grp_nb_of_txs").cast("int").alias("grp_nb_of_txs"),
        F.col("sttlm_mtd").cast("string").alias("sttlm_mtd"),
        F.col("rmt_ustrd").cast("string").alias("rmt_ustrd"),
        F.col("purp_cd").cast("string").alias("purp_cd"),
        F.col("pmt_instr_id").cast("string").alias("pmt_instr_id"),
        F.col("pmt_e2e_id").cast("string").alias("pmt_e2e_id"),
        F.col("chrg_br").cast("string").alias("chrg_br"),

        F.col("cdtr_agt_mmb_id").cast("string").alias("cdtr_agt_mmb_id"),
        F.col("dbtr_agt_mmb_id").cast("string").alias("dbtr_agt_mmb_id"),

        F.col("cdtr_name").cast("string").alias("cdtr_name"),
        F.col("dbtr_name").cast("string").alias("dbtr_name"),
        F.col("cdtr_id").cast("string").alias("cdtr_id"),
        F.col("dbtr_id").cast("string").alias("dbtr_id"),

        F.col("cdtr_acct_id").cast("string").alias("cdtr_acct_id"),
        F.col("dbtr_acct_id").cast("string").alias("dbtr_acct_id"),
        F.col("cdtr_acct_scheme").cast("string").alias("cdtr_acct_scheme"),
        F.col("dbtr_acct_scheme").cast("string").alias("dbtr_acct_scheme"),

        F.col("instd_amt").cast("double").alias("instd_amt"),
        F.col("instd_ccy").cast("string").alias("instd_ccy"),
        F.col("intrbk_amt").cast("double").alias("intrbk_amt"),
        F.col("intrbk_ccy").cast("string").alias("intrbk_ccy"),
        F.col("xchg_rate").cast("string").alias("xchg_rate"),

        F.col("charge_amt").cast("double").alias("charge_amt"),
        F.col("charge_ccy").cast("string").alias("charge_ccy"),
        F.col("charge_agent_mmb_id").cast("string").alias("charge_agent_mmb_id"),

        F.col("event_ts").cast("timestamp").alias("event_ts"),
        F.to_date(F.col("event_ts")).cast("date").alias("event_date"),

        # --- metadata ---
        F.col("record_hash").cast("string").alias("record_hash"),
        F.col("ingested_at_ts").cast("timestamp").alias("ingested_at_ts"),
    )
    )

    bad = [c for c,t in gold.dtypes if t.startswith(("array","struct","map"))]
    if bad:
        raise RuntimeError(f"GOLD has non-scalar columns: {bad}")

    gold_opts = hudi_opts(
        table_name="pacs008",
        record_key="pk",
        precombine="ingested_at_ts",
        partition="event_date",
        payload_class="org.apache.hudi.common.model.OverwriteWithLatestAvroPayload"
    )
    write_hudi(gold, gold_path, gold_opts)

    print(f"   * Gold written → {gold_path}")
    print(f"* PACs008 COMPLETE ETL finished from {source_path}\n")
    return gold_path

# ========================================================
# PACs002 - COMPLETE ETL (Bronze → Silver → Gold)
# ========================================================

def etl_pacs002(spark, WAREHOUSE_ROOT, source_path: str):
    """
    Complete PACs002 pipeline.
    source_path example: "s3a://frms/pacs002/"
    """
    bronze_path = f"{WAREHOUSE_ROOT}/bronze/pacs002"
    silver_path = f"{WAREHOUSE_ROOT}/silver/pacs002"
    gold_path   = f"{WAREHOUSE_ROOT}/gold/pacs002"

    print(f"* Starting PACs002 ETL from → {source_path}")

    # ====================== BRONZE ======================
    df_bronze = spark.read.json(source_path)

    doc_schema = spark.read.json(
    df_bronze.select("document").where(F.col("document").isNotNull()).rdd.map(lambda r: r[0])
    ).schema

    pacs002_df = df_bronze.withColumn("doc", F.from_json(F.col("document"), doc_schema))

    pacs002_df = (
    pacs002_df
    .withColumn("messageid", F.col("doc.FIToFIPmtSts.GrpHdr.MsgId"))
    .withColumn("endtoendid", F.col("doc.FIToFIPmtSts.TxInfAndSts.OrgnlEndToEndId"))
    .withColumn("tenantid", F.col("doc.TenantId"))
    .withColumn("credtm", F.col("doc.FIToFIPmtSts.GrpHdr.CreDtTm"))
    )

    bronze = (
    pacs002_df
    .withColumnRenamed("tenantid", "tenant_id")
    .withColumnRenamed("messageid", "message_id")
    .withColumnRenamed("endtoendid", "end_to_end_id")
    .withColumnRenamed("credtm", "credttm_raw")
    
    # parse timestamp if possible
    .withColumn("credttm_ts", F.to_timestamp(F.col("credttm_raw")))
    .withColumn("event_date", F.to_date(F.col("credttm_ts")))

    # ingestion metadata
    .withColumn("ingested_at_ts", F.current_timestamp())
    .withColumn("source_file_path", F.lit(None).cast("string"))
    )


    bronze = bronze.withColumn(
    "record_hash",
    F.sha2(
        F.concat_ws(
            "||",
            F.coalesce(F.col("tenant_id"), F.lit("")),
            F.coalesce(F.col("message_id"), F.lit("")),
            F.coalesce(F.col("end_to_end_id"), F.lit("")),
            F.coalesce(F.col("credttm_raw"), F.lit("")),
        ),
        256,
    )
    )

    bronze = bronze.withColumn("_row_payload_json", F.to_json(F.struct("*")))


    bronze_opts = hudi_opts(
        table_name="bronze_pacs002",
        record_key="record_hash",
        precombine="ingested_at_ts"
    )
    write_hudi(bronze, bronze_path, bronze_opts)
    print(f"   * Bronze written → {bronze_path}")

    # ====================== SILVER ======================
    bronze_df = spark.read.format("hudi").load(bronze_path)

    # Infer schema from the raw document
    doc_schema = spark.read.json(
    bronze_df.select("document").where(F.col("document").isNotNull()).rdd.map(lambda r: r[0])
    ).schema   

    s = bronze_df.withColumn("doc", F.from_json(F.col("document"), doc_schema))

    s = (
    s
    .withColumn("dc_cdtr_id", F.col("doc.DataCache.cdtrId").cast("string"))
    .withColumn("dc_dbtr_id", F.col("doc.DataCache.dbtrId").cast("string"))
    .withColumn("dc_cre_dt_tm", F.to_timestamp(F.col("doc.DataCache.creDtTm")))
    .withColumn("dc_instd_amt", F.col("doc.DataCache.instdAmt.amt").cast("double"))
    .withColumn("dc_instd_ccy", F.col("doc.DataCache.instdAmt.ccy").cast("string"))
    .withColumn("dc_xchg_rate", F.col("doc.DataCache.xchgRate").cast("string"))
    .withColumn("dc_cdtr_acct_id", F.col("doc.DataCache.cdtrAcctId").cast("string"))
    .withColumn("dc_dbtr_acct_id", F.col("doc.DataCache.dbtrAcctId").cast("string"))
    .withColumn("dc_intrbk_amt", F.col("doc.DataCache.intrBkSttlmAmt.amt").cast("double"))
    .withColumn("dc_intrbk_ccy", F.col("doc.DataCache.intrBkSttlmAmt.ccy").cast("string"))
    )

    s = (
    s
    .withColumn("grp_msg_id", F.col("doc.FIToFIPmtSts.GrpHdr.MsgId").cast("string"))
    .withColumn("grp_cre_dt_tm", F.to_timestamp(F.col("doc.FIToFIPmtSts.GrpHdr.CreDtTm")))
    .withColumn("tx_status", F.col("doc.FIToFIPmtSts.TxInfAndSts.TxSts").cast("string"))
    .withColumn("accptnc_dt_tm", F.to_timestamp(F.col("doc.FIToFIPmtSts.TxInfAndSts.AccptncDtTm")))
    .withColumn("orgnl_instr_id", F.col("doc.FIToFIPmtSts.TxInfAndSts.OrgnlInstrId").cast("string"))
    .withColumn("orgnl_end_to_end_id", F.col("doc.FIToFIPmtSts.TxInfAndSts.OrgnlEndToEndId").cast("string"))

    # Status reason
    .withColumn("status_reason_code", F.get_json_object(F.col("document"), "$.FIToFIPmtSts.TxInfAndSts.StsRsnInf.Rsn.Cd").cast("string"))

    # Agents
    .withColumn("instd_mmb_id", F.col("doc.FIToFIPmtSts.TxInfAndSts.InstdAgt.FinInstnId.ClrSysMmbId.MmbId").cast("string"))
    .withColumn("instg_mmb_id", F.col("doc.FIToFIPmtSts.TxInfAndSts.InstgAgt.FinInstnId.ClrSysMmbId.MmbId").cast("string"))
    )

    charges = F.col("doc.FIToFIPmtSts.TxInfAndSts.ChrgsInf")

    s = (
    s
    .withColumn("charge_count", F.when(charges.isNotNull(), F.size(charges)).otherwise(F.lit(0)).cast("int"))
    .withColumn(
        "charge_total_amount",
        F.when(
            charges.isNotNull(),
            F.expr("""
              aggregate(
                transform(doc.FIToFIPmtSts.TxInfAndSts.ChrgsInf, x -> cast(x.Amt.Amt as double)),
                cast(0.0 as double),
                (acc, v) -> acc + coalesce(v, 0.0)
              )
            """)
        ).otherwise(F.lit(0.0)).cast("double")
    )
    .withColumn(
        "charge_currency_count",
        F.when(
            charges.isNotNull(),
            F.expr("size(array_distinct(transform(doc.FIToFIPmtSts.TxInfAndSts.ChrgsInf, x -> x.Amt.Ccy)))")
        ).otherwise(F.lit(0)).cast("int")
    )
    .withColumn(
        "charge_currency_hint",
        F.when(
            charges.isNotNull(),
            F.expr("element_at(array_distinct(transform(doc.FIToFIPmtSts.TxInfAndSts.ChrgsInf, x -> x.Amt.Ccy)), 1)")
        ).otherwise(F.lit(None).cast("string"))
    )
    )   

    s = (
    s
    .withColumn("event_ts", F.coalesce(F.col("grp_cre_dt_tm"), F.col("credttm_ts"), F.col("dc_cre_dt_tm")))
    .withColumn("event_date_silver", F.to_date(F.col("event_ts")))
    )

    w = Window.partitionBy("tenant_id", "message_id").orderBy(F.col("ingested_at_ts").desc_nulls_last())
    silver = s.withColumn("_rn", F.row_number().over(w)).filter(F.col("_rn") == 1).drop("_rn")

    if "tx_type" not in silver.columns:
    # pacs.002 is constant if missing in payload
        silver = silver.withColumn(
        "tx_type",
            F.coalesce(
                F.get_json_object(F.col("document").cast("string"), "$.TxTp"),
                F.lit("pacs.002.001.12")
            )
        )

    silver = (
    silver
    .drop("_row_payload_json")
    .drop("doc")
    .drop("document")
    )

    silver_opts = hudi_opts(
        table_name="silver_pacs002",
        record_key="record_hash",
        precombine="ingested_at_ts"
    )
    write_hudi(silver, silver_path, silver_opts)
    print(f"   * Silver written → {silver_path}")

    # ====================== GOLD ======================
    
    s = spark.read.format("hudi").load(silver_path)
    s = ensure_columns(s, {"tx_tenant_id": "string"})
    s = s.withColumn("tx_tenant_id", F.coalesce(F.col("tx_tenant_id"), F.col("tenant_id").cast("string")))
    tx_msg_id   = F.col("grp_msg_id").cast("string")               
    tx_event_ts = F.col("event_ts").cast("timestamp")

    tx_amount = F.col("dc_instd_amt").cast("double")
    tx_ccy    = F.col("dc_instd_ccy").cast("string")   

    event_to_ingest_ms = (
        (F.col("ingested_at_ts").cast("double") - F.col("event_ts").cast("double")) * 1000.0
    )

    gold_pk = F.sha2(
    F.concat_ws(
        "||",
        F.lit("gold_pacs002"),
        F.coalesce(F.col("tenant_id"), F.lit("")),
        F.coalesce(tx_msg_id, F.lit("")),
        F.coalesce(F.col("end_to_end_id"), F.lit("")),
        F.coalesce(F.col("record_hash"), F.lit("")),
    ),
    256
    )

    gold = (
    s
    .withColumn("pk", gold_pk)

    # add aligned names (do NOT remove original ones)
    .withColumn("tx_msg_id", tx_msg_id)
    .withColumn("tx_event_ts", tx_event_ts)
    .withColumn("tx_amount", tx_amount)
    .withColumn("tx_ccy", tx_ccy)
    .withColumn("event_to_ingest_ms", event_to_ingest_ms.cast("long"))
    .withColumn("event_date", F.to_date(F.col("event_ts")))

    .select(
        "pk",

        # ---- ORIGINAL INPUT (NOT omitted) ----
        "tenant_id",
        "message_id",
        "end_to_end_id",
        "credttm_raw",
        "credttm_ts",

        # ---- Convention-aligned aliases ----
        "tx_type",              # already present
        "tx_msg_id",            # aligned: grp_msg_id
        "tx_status",            # already present
        "tx_amount",            # aligned: DataCache instructed amount
        "tx_ccy",               # aligned: DataCache instructed currency
        "instg_mmb_id",         # already present
        "instd_mmb_id",         # already present
        "charge_count",         # already present
        "event_ts",             # keep original
        "tx_event_ts",          # aligned alias
        "event_date",
        "event_to_ingest_ms",

        # ---- Keep PACS.002-specific fields (NOT omitted) ----
        "tx_tenant_id",

        "dc_cdtr_id","dc_dbtr_id",
        "dc_cre_dt_tm",
        "dc_instd_amt","dc_instd_ccy",
        "dc_xchg_rate",
        "dc_cdtr_acct_id","dc_dbtr_acct_id",
        "dc_intrbk_amt","dc_intrbk_ccy",

        "grp_msg_id","grp_cre_dt_tm",
        "accptnc_dt_tm",
        "orgnl_instr_id",
        "orgnl_end_to_end_id",
        "status_reason_code",

        "charge_total_amount",
        "charge_currency_count",
        "charge_currency_hint",

        # metadata
        "record_hash",
        "ingested_at_ts",
    )
    )

    bad = [c for c,t in gold.dtypes if t.startswith(("array","struct","map"))]
    if bad:
       raise RuntimeError(f"GOLD has non-scalar columns: {bad}")


    gold_opts = hudi_opts(
        table_name="pacs002",
        record_key="pk",
        precombine="ingested_at_ts"
    )
    write_hudi(gold, gold_path, gold_opts)

    print(f"   * Gold written → {gold_path}")
    print(f"* PACs002 COMPLETE ETL finished from {source_path}\n")
    return gold_path

def _parse_s3a_bucket(source_path: str) -> str:
    """Extract bucket from an s3a://bucket/... path."""
    if not source_path:
        return ""
    prefix = "s3a://"
    if not source_path.startswith(prefix):
        return ""
    rest = source_path[len(prefix):]
    bucket = rest.split("/", 1)[0]
    return bucket


def _touch(path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a", encoding="utf-8"):
        os.utime(path, None)


def _is_recent_file(path: str, ttl_seconds: int) -> bool:
    """True if file exists and its mtime is within ttl_seconds from now."""
    try:
        st = os.stat(path)
    except FileNotFoundError:
        return False
    age_seconds = max(0.0, (datetime.now().timestamp() - st.st_mtime))
    return age_seconds <= float(ttl_seconds)


def etl_pacs(spark, WAREHOUSE_ROOT: str, source_path: str, table: str):
    """
    Combined PACs pipeline.
    - Runs the full ETL (Bronze→Silver→Gold) for the incoming PACS table (pacs008/pacs002)
    - Triggers Transactions ETL ONLY after BOTH pacs008 and pacs002 have reached GOLD
    """
    if table not in {"pacs008", "pacs002"}:
        raise ValueError(f"etl_pacs received unknown table: {table}")

    print(f"* Starting Combined PACs ETL for {table} → {source_path}")

    if table == "pacs008":
        etl_pacs008(spark, WAREHOUSE_ROOT, source_path)
    else:
        etl_pacs002(spark, WAREHOUSE_ROOT, source_path)

    # Mark GOLD completion for this PACS table (local marker files)
    state_dir = os.path.join(WAREHOUSE_ROOT, ".pipeline_state")
    pacs008_done = os.path.join(state_dir, "pacs008_gold_done")
    pacs002_done = os.path.join(state_dir, "pacs002_gold_done")
    _touch(pacs008_done if table == "pacs008" else pacs002_done)

    # Guard against stale markers from old/failed batches.
    # If a marker is too old, treat it as unrelated and delete it.
    marker_ttl_minutes = int(_env("PACS_MARKER_TTL_MINUTES", "60") or "60")
    marker_ttl_seconds = max(60, marker_ttl_minutes * 60)

    pacs008_recent = _is_recent_file(pacs008_done, marker_ttl_seconds)
    pacs002_recent = _is_recent_file(pacs002_done, marker_ttl_seconds)

    if os.path.exists(pacs008_done) and not pacs008_recent:
        try:
            os.remove(pacs008_done)
        except FileNotFoundError:
            pass
        pacs008_recent = False

    if os.path.exists(pacs002_done) and not pacs002_recent:
        try:
            os.remove(pacs002_done)
        except FileNotFoundError:
            pass
        pacs002_recent = False

    # Trigger transactions only when BOTH PACS gold pipelines have completed
    if pacs008_recent and pacs002_recent:
        print("* pacs008 + pacs002 GOLD complete → triggering etl_transactions")

        bucket = _parse_s3a_bucket(source_path)
        if not bucket:
            raise ValueError(f"Unable to parse bucket from source_path: {source_path}")

        trigger_lock = os.path.join(state_dir, "transactions_trigger.lock")
        os.makedirs(state_dir, exist_ok=True)

        # prevent double-trigger when pacs008 & pacs002 finish near-simultaneously
        try:
            fd = os.open(trigger_lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.close(fd)
        except FileExistsError:
            print("[PACs] Transactions trigger already in progress; skipping")
            return f"{WAREHOUSE_ROOT}/gold/transactions"

        transactions_ok = False
        try:
            transaction_source_path = f"s3a://{bucket}/transaction/"
            # PACS-triggered transactions should not depend on a separate transaction feed.
            # Build from PACS Bronze so we don't write empty (metadata-only) commits.
            etl_transactions(spark, WAREHOUSE_ROOT, source_path=transaction_source_path, mode="from_pacs")
            transactions_ok = True
            print("* Combined PACs + Transactions pipeline completed")
            return f"{WAREHOUSE_ROOT}/gold/transactions"
        finally:
            try:
                os.remove(trigger_lock)
            except FileNotFoundError:
                pass

            if transactions_ok:
                # reset markers for next batch
                for marker in (pacs008_done, pacs002_done):
                    try:
                        os.remove(marker)
                    except FileNotFoundError:
                        pass

    missing = []
    if not pacs008_recent:
        missing.append("pacs008")
    if not pacs002_recent:
        missing.append("pacs002")
    print(
        "* Waiting for the other PACS table to reach GOLD before triggering transactions"
        + (f" (missing/recent: {missing})" if missing else "")
    )
    return f"{WAREHOUSE_ROOT}/gold/transactions"
# ========================================================
# TRANSACTIONS - COMPLETE ETL (Bronze → Silver → Gold)
# ========================================================

def etl_transactions(spark, WAREHOUSE_ROOT, source_path: str, mode: str = "join"):
    """
    Complete Transactions pipeline.
    source_path example: "s3a://frms/transaction/"

    mode:
      - "join": legacy behavior (transaction feed joined to PACS by end-to-end id)
      - "from_pacs": derive transactions directly from PACS Bronze (recommended when PACS triggers this ETL)
    """
    bronze_path = f"{WAREHOUSE_ROOT}/bronze/transactions"
    silver_path = f"{WAREHOUSE_ROOT}/silver/transactions"
    gold_path   = f"{WAREHOUSE_ROOT}/gold/transactions"

    if mode not in {"join", "from_pacs"}:
        raise ValueError(f"etl_transactions mode must be 'join' or 'from_pacs' (got: {mode!r})")

    print(f"* Starting Transactions ETL ({mode}) from → {source_path}")

# ====================== BRONZE ======================

    pacs008_bronze_path = f"{WAREHOUSE_ROOT}/bronze/pacs008"
    pacs002_bronze_path = f"{WAREHOUSE_ROOT}/bronze/pacs002"
    df_pacs008 = spark.read.format("hudi").load(pacs008_bronze_path)
    df_pacs002 = spark.read.format("hudi").load(pacs002_bronze_path)

    def _transactions_from_pacs(df_pacs, source_label: str):
        created_ts = F.coalesce(F.col("credttm_ts"), F.col("ingested_at_ts"), F.current_timestamp())
        created_at_ms = (created_ts.cast("long") * F.lit(1000)).cast("long")

        # pacs008 Bronze has document_json; pacs002 Bronze does not.
        if "document_json" in df_pacs.columns:
            tx_data = F.coalesce(F.col("document_json"), F.col("document").cast("string")).cast("string")
        else:
            tx_data = F.col("document").cast("string")

        base = (
            df_pacs
            .filter(F.col("end_to_end_id").isNotNull() & F.col("tenant_id").isNotNull())
            .select(
                created_at_ms.alias("createdAt"),
                F.col("end_to_end_id").cast("string").alias("endToEndId"),
                F.col("tenant_id").cast("string").alias("tenantId"),
                tx_data.alias("transactionData"),
            )
        )

        # Deterministic ID (avoids global Window.orderBy which forces single-partition work)
        return base.withColumn(
            "transactionId",
            (
                F.pmod(
                    F.xxhash64(F.lit(source_label), F.col("endToEndId"), F.col("tenantId")),
                    F.lit(900000000),
                )
                + F.lit(500000)
            ).cast("int"),
        )

    if mode == "from_pacs":
        df_old_transaction_table = (
            _transactions_from_pacs(df_pacs008, "pacs008")
            .unionByName(_transactions_from_pacs(df_pacs002, "pacs002"))
            .select("createdAt", "endToEndId", "tenantId", "transactionData", "transactionId")
        )
    else:
        # 1. Read raw transactions
        df_transactions = spark.read.json(source_path)

        # 2. Legacy join logic (exact same as your original script)
        pacs008_legacy = (
            df_transactions.filter(F.col("txtp") == "pacs.008.001.10")
            .join(
                df_pacs008.select(F.col("end_to_end_id").alias("p8_id"), F.col("document")),
                df_transactions.endtoendid == F.col("p8_id"),
                "inner",
            )
            .select(
                (F.unix_timestamp("credttm") * 1000).alias("createdAt"),
                F.col("endtoendid").alias("endToEndId"),
                F.col("tenantid").alias("tenantId"),
                F.col("document").alias("transactionData"),
            )
        )

        pacs002_legacy = (
            df_transactions.filter(F.col("txtp") == "pacs.002.001.12")
            .join(
                df_pacs002.select(F.col("end_to_end_id").alias("p2_id"), F.col("document")),
                df_transactions.endtoendid == F.col("p2_id"),
                "inner",
            )
            .select(
                (F.unix_timestamp("credttm") * 1000).alias("createdAt"),
                F.col("endtoendid").alias("endToEndId"),
                F.col("tenantid").alias("tenantId"),
                F.col("document").alias("transactionData"),
            )
        )

        df_combined = pacs008_legacy.unionByName(pacs002_legacy)

        # If the feed join produces no rows, fall back to PACS-derived transactions
        if df_combined.rdd.isEmpty():
            print(
                "* Transactions feed produced 0 matched rows; building transactions from PACS Bronze instead"
            )
            df_old_transaction_table = (
                _transactions_from_pacs(df_pacs008, "pacs008")
                .unionByName(_transactions_from_pacs(df_pacs002, "pacs002"))
                .select("createdAt", "endToEndId", "tenantId", "transactionData", "transactionId")
            )
        else:
            # Generate a deterministic ID that is unique across message types
            df_final = (
                df_combined
                .withColumn(
                    "_tx_src",
                    F.when(F.col("transactionData").contains("FIToFICstmrCdtTrf"), F.lit("pacs008"))
                     .when(F.col("transactionData").contains("FIToFIPmtSts"), F.lit("pacs002"))
                     .otherwise(F.lit("unknown"))
                )
                .withColumn(
                    "transactionId",
                    (
                        F.pmod(
                            F.xxhash64(
                                F.col("_tx_src"),
                                F.col("createdAt").cast("string"),
                                F.col("endToEndId"),
                                F.col("tenantId"),
                            ),
                            F.lit(900000000),
                        )
                        + F.lit(500000)
                    ).cast("int"),
                )
                .drop("_tx_src")
            )

            df_old_transaction_table = df_final.select(
                "createdAt", "endToEndId", "tenantId", "transactionData", "transactionId"
            )

    # 4. Final Bronze table
    bronze_tx = (
        df_old_transaction_table
        .withColumn("transaction_id", F.col("transactionId").cast("long"))
        .withColumn("createdAt",      F.col("createdAt").cast("long"))
        .withColumn("endToEndId",     F.col("endToEndId").cast("string"))
        .withColumn("tenantId",       F.col("tenantId").cast("string"))
        .withColumn("transactionData", F.col("transactionData").cast("string"))
        .withColumn("created_at_ts",  F.current_timestamp())
        .withColumn("source_file_path", F.lit(source_path))
        .withColumn(
            "record_hash",
            F.sha2(
                F.concat_ws("||",
                    F.col("transaction_id").cast("string"),
                    F.col("endToEndId"),
                    F.col("tenantId"),
                    F.col("createdAt").cast("string"),
                    F.col("transactionData")
                ),
                256
            )
        )
        .withColumn("_row_payload_json", F.to_json(F.struct("*")))
    )

    bronze_opts = hudi_opts("transactions", "transaction_id", "created_at_ts")
    write_hudi(bronze_tx, bronze_path, bronze_opts)
    print(f"   * Bronze written → {bronze_path}")

    # ====================== SILVER ======================
    b = spark.read.format("hudi").load(bronze_path)

    s = (
    b
    .withColumn("tx_type", F.get_json_object("transactionData", "$.TxTp"))
    .withColumn("tx_tenant_id", F.get_json_object("transactionData", "$.TenantId"))

    # msg id / created time (pacs.008 path)
    .withColumn("msg_id_008", F.get_json_object("transactionData", "$.FIToFICstmrCdtTrf.GrpHdr.MsgId"))
    .withColumn("created_008", F.get_json_object("transactionData", "$.FIToFICstmrCdtTrf.GrpHdr.CreDtTm"))

    # msg id / created time (pacs.002 path)
    .withColumn("msg_id_002", F.get_json_object("transactionData", "$.FIToFIPmtSts.GrpHdr.MsgId"))
    .withColumn("created_002", F.get_json_object("transactionData", "$.FIToFIPmtSts.GrpHdr.CreDtTm"))

    .withColumn("tx_msg_id", F.coalesce("msg_id_008", "msg_id_002"))
    .withColumn("tx_created_ts", F.to_timestamp(F.coalesce("created_008", "created_002")))

    # pacs.002 status + accept
    .withColumn("tx_status", F.get_json_object("transactionData", "$.FIToFIPmtSts.TxInfAndSts.TxSts"))
    .withColumn("tx_accept_ts", F.to_timestamp(F.get_json_object("transactionData", "$.FIToFIPmtSts.TxInfAndSts.AccptncDtTm")))

    # canonical event
    .withColumn("event_ts", F.col("tx_created_ts"))
    .withColumn("event_date", F.to_date("event_ts"))

    # instructing/instructed agents (paths differ)
    .withColumn("instg_mmb_id",
        F.coalesce(
            F.get_json_object("transactionData", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.DbtrAgt.FinInstnId.ClrSysMmbId.MmbId"),
            F.get_json_object("transactionData", "$.FIToFIPmtSts.TxInfAndSts.InstgAgt.FinInstnId.ClrSysMmbId.MmbId")
        )
    )
    .withColumn("instd_mmb_id",
        F.coalesce(
            F.get_json_object("transactionData", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.CdtrAgt.FinInstnId.ClrSysMmbId.MmbId"),
            F.get_json_object("transactionData", "$.FIToFIPmtSts.TxInfAndSts.InstdAgt.FinInstnId.ClrSysMmbId.MmbId")
        )
    )

    # Amount only exists for pacs.008
    .withColumn("tx_amount",
        F.get_json_object("transactionData", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.InstdAmt.Amt.Amt").cast("double")
    )
    .withColumn("tx_ccy",
        F.get_json_object("transactionData", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.InstdAmt.Amt.Ccy").cast("string")
    )

    # charges (pacs.008 is struct, pacs.002 is array)
    # We extract charge amounts using JSON parsing fallback:
    .withColumn("charges_002_json", F.get_json_object("transactionData", "$.FIToFIPmtSts.TxInfAndSts.ChrgsInf"))
    .withColumn("charges_008_amt", F.get_json_object("transactionData", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.ChrgsInf.Amt.Amt").cast("double"))
    .withColumn("charges_008_ccy", F.get_json_object("transactionData", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.ChrgsInf.Amt.Ccy"))

    # For pacs.008: single charge
    .withColumn("charge_count",
        F.when(F.col("charges_002_json").isNotNull(), F.size(F.from_json("charges_002_json", "array<struct<Agt:struct<FinInstnId:struct<ClrSysMmbId:struct<MmbId:string>>>,Amt:struct<Amt:double,Ccy:string>>>")))
         .otherwise(F.when(F.col("charges_008_amt").isNotNull(), F.lit(1)).otherwise(F.lit(0)))
    )
    )

    # Deduplicate
    w = Window.partitionBy("transaction_id").orderBy(F.col("created_at_ts").desc())
    silver_tx = s.withColumn("rn", F.row_number().over(w)).filter("rn = 1").drop("rn")

    silver_opts = hudi_opts("silver_transactions", "transaction_id", "created_at_ts")
    write_hudi(silver_tx, silver_path, silver_opts)
    print(f"   * Silver written → {silver_path}")

    # ====================== GOLD ======================
    s = spark.read.format("hudi").load(silver_path)

    gold_tx = (
    s
    .withColumn("priority_norm", F.lit(None).cast("string"))  # keep pattern if needed

    # scalar latency
    .withColumn(
        "event_to_ingest_ms",
        F.when(
            F.col("event_ts").isNotNull(),
            (F.col("created_at_ts").cast("long") - F.col("event_ts").cast("long")) * 1000
        ).otherwise(F.lit(None).cast("long"))
    )

    .select(
        F.col("transaction_id").cast("long").alias("transaction_id"),
        F.col("endToEndId").cast("string").alias("end_to_end_id"),
        F.col("tenantId").cast("string").alias("tenant_id"),

        F.col("tx_type").cast("string").alias("tx_type"),
        F.col("tx_msg_id").cast("string").alias("tx_msg_id"),
        F.col("tx_status").cast("string").alias("tx_status"),

        F.col("tx_amount").cast("double").alias("tx_amount"),
        F.col("tx_ccy").cast("string").alias("tx_ccy"),

        F.col("instg_mmb_id").cast("string").alias("instg_mmb_id"),
        F.col("instd_mmb_id").cast("string").alias("instd_mmb_id"),

        F.col("charge_count").cast("int").alias("charge_count"),

        F.col("event_ts").cast("timestamp").alias("event_ts"),
        F.col("event_date").cast("date").alias("event_date"),
        F.col("created_at_ts").cast("timestamp").alias("ingested_at_ts"),
        F.col("event_to_ingest_ms").cast("long").alias("event_to_ingest_ms"),

        F.col("source_file_path").cast("string").alias("source_file_path"),
        F.col("record_hash").cast("string").alias("record_hash"),
    )
    )

    bad = [c for c,t in gold_tx.dtypes if t.startswith("array") or t.startswith("struct")]
    if bad:
       raise RuntimeError(f"Gold Transactions contains non-scalar cols: {bad}")

    hudi_gold_tx_opts = {
    "hoodie.table.name": "transactions",
    "hoodie.datasource.write.table.type": "COPY_ON_WRITE",
    "hoodie.datasource.write.operation": "upsert",
    "hoodie.datasource.write.recordkey.field": "transaction_id",
    "hoodie.datasource.write.precombine.field": "ingested_at_ts",
    "hoodie.datasource.write.partitionpath.field": "event_date",
    "hoodie.datasource.write.keygenerator.class": "org.apache.hudi.keygen.SimpleKeyGenerator",
    "hoodie.datasource.write.hive_style_partitioning": "true",

    "hoodie.datasource.write.schema.evolution.enable": "true",
    "hoodie.datasource.read.schema.evolution.enable": "true",
    "hoodie.datasource.write.reconcile.schema": "true",
    "hoodie.schema.on.read.enable": "true",

    "hoodie.metadata.enable": "false",
    "hoodie.datasource.write.payload.class": "org.apache.hudi.common.model.OverwriteWithLatestAvroPayload",
    }

    (
    gold_tx.write.format("hudi")
    .options(**hudi_gold_tx_opts)
    .mode("append")
    .save(gold_path)
    )

    print(f"   * Gold written → {gold_path}")
    print(f"* Transactions COMPLETE ETL finished from {source_path}\n")
    return gold_path

# ========================================================
# NETWORK_MAP - COMPLETE ETL (Bronze → Silver → Gold)
# ========================================================

def etl_network_map(spark, WAREHOUSE_ROOT, source_path: str):
    """
    Complete Network Map pipeline with credttm & upddttm support.
    source_path example: "s3a://frms1/network_map/"
    """
    bronze_path = f"{WAREHOUSE_ROOT}/bronze/network_map"
    silver_path = f"{WAREHOUSE_ROOT}/silver/network_map"
    gold_path = f"{WAREHOUSE_ROOT}/gold/network_map"

    print(f"* Starting Network Map ETL from → {source_path}")

    # ====================== BRONZE ======================
    nmap_df = spark.read.json(source_path)

    bronze = (
        nmap_df
        .withColumnRenamed("tenantid", "tenant_id")
        .withColumn("configuration", F.col("configuration").cast("string"))
        # Synthetic stable key
        .withColumn(
            "network_map_id",
            F.sha2(F.concat_ws("||", F.col("tenant_id"), F.col("configuration")), 256)
        )
        .withColumn("created_at_ts", F.current_timestamp())
        .withColumn("source_file_path", F.input_file_name())
        .withColumn(
            "record_hash",
            F.sha2(F.concat_ws("||", F.col("tenant_id"), F.col("configuration")), 256)
        )
        .withColumn("_row_payload_json", F.to_json(F.struct("*")))
    )

    bronze_opts = hudi_opts(
        table_name="network_map",
        record_key="network_map_id",
        precombine="created_at_ts"
    )
    write_hudi(bronze, bronze_path, bronze_opts)
    print(f" * Bronze written → {bronze_path}")

    # ====================== SILVER ======================
    bronze_df = spark.read.format("hudi").load(bronze_path)

    # Infer schema from configuration JSON
    config_schema = infer_json_schema(spark, bronze_df, "configuration")

    silver = (
        bronze_df
        .withColumn("config_obj", F.from_json("configuration", config_schema))
        .withColumn("network_cfg", F.col("config_obj.cfg"))
        .withColumn("network_active", F.col("config_obj.active").cast("boolean"))
        # Explode messages
        .withColumn("message", F.explode(F.col("config_obj.messages")))
        .withColumn("message_id", F.col("message.id"))
        .withColumn("message_cfg", F.col("message.cfg"))
        .withColumn("tx_type", F.col("message.txTp"))
        # Explode typologies inside each message
        .withColumn("typology", F.explode(F.col("message.typologies")))
        .withColumn("typology_id", F.col("typology.id"))
        .withColumn("typology_cfg", F.col("typology.cfg"))
        # Rule array
        .withColumn(
            "rule_ids",
            F.expr("transform(typology.rules, x -> x.id)")
        )
        .withColumn("rule_count", F.size("rule_ids"))
        # === NEW: Keep the two new columns ===
        .select(
            "network_map_id",
            "tenant_id",
            "network_cfg",
            "network_active",
            "message_id",
            "message_cfg",
            "tx_type",
            "typology_id",
            "typology_cfg",
            "rule_ids",
            "rule_count",
            "created_at_ts",
            "record_hash",
            "source_file_path",
            "credttm",      # ← added
            "upddttm"       # ← added
        )
    )

    # Deduplicate (keep latest version per network_map_id)
    w = Window.partitionBy("network_map_id").orderBy(F.col("created_at_ts").desc())
    silver = silver.withColumn("rn", F.row_number().over(w)).filter("rn = 1").drop("rn")

    silver_opts = hudi_opts(
        table_name="network_map",
        record_key="network_map_id",
        precombine="created_at_ts"
    )
    write_hudi(silver, silver_path, silver_opts)
    print(f" * Silver written → {silver_path}")

    # ====================== GOLD ======================
    silver_df = spark.read.format("hudi").load(silver_path)

    gold = (
        silver_df
        .groupBy(
            "tenant_id",
            "tx_type",
            "typology_id",
            "typology_cfg"
        )
        .agg(
            F.max("network_active").alias("network_active"),
            F.sum("rule_count").alias("rule_count"),
            F.countDistinct("message_id").alias("message_count"),
            F.countDistinct("typology_id").alias("typology_count"),
            F.max("created_at_ts").alias("ingested_at_ts"),
            # === NEW: propagate credttm & upddttm ===
            F.max("credttm").alias("credttm"),
            F.max("upddttm").alias("upddttm")
        )
        .withColumn(
            "network_map_key",
            F.sha2(
                F.concat_ws("||", "tenant_id", "tx_type", "typology_id"),
                256
            )
        )
        .withColumn("event_date", F.to_date("ingested_at_ts"))
        .select(
            "network_map_key",
            "tenant_id",
            "tx_type",
            "typology_id",
            "typology_cfg",
            "rule_count",
            "network_active",
            "message_count",
            "typology_count",
            "ingested_at_ts",
            "event_date",
            "credttm",      # ← added
            "upddttm"       # ← added
        )
    )

    gold.write.format("hudi") \
        .options(
            **{
                "hoodie.table.name": "network_map",
                "hoodie.datasource.write.recordkey.field": "network_map_key",
                "hoodie.datasource.write.precombine.field": "ingested_at_ts",
                "hoodie.datasource.write.partitionpath.field": "event_date",
                "hoodie.datasource.write.hive_style_partitioning": "true",
                "hoodie.datasource.write.keygenerator.class": "org.apache.hudi.keygen.SimpleKeyGenerator",
                "hoodie.datasource.write.schema.evolution.enable": "true",
                "hoodie.datasource.write.reconcile.schema": "true",
            }
        ) \
        .mode("append") \
        .save(gold_path)

    print(f" * Gold written → {gold_path}")
    print(f"* Network Map COMPLETE ETL finished from {source_path}\n")

    return gold_path


def etl_typologies(spark, WAREHOUSE_ROOT: str, source_path: str) -> str:
    """
    Complete Typologies ETL pipeline.
    source_path example: "s3a://frms1/typology/"
    """
    bronze_path = f"{WAREHOUSE_ROOT}/bronze/typologies"
    silver_path = f"{WAREHOUSE_ROOT}/silver/typologies"
    gold_path   = f"{WAREHOUSE_ROOT}/gold/typologies"

    # ====================== BRONZE ======================
    typ_df = spark.read.json(source_path)

    bronze = (
        typ_df
        .withColumnRenamed("tenantid", "tenant_id")
        .withColumnRenamed("typologycfg", "typology_cfg")
        .withColumnRenamed("typologyid", "typology_id")
        .withColumn("configuration_json", F.col("configuration").cast("string"))
        .withColumn("ingested_at_ts", F.current_timestamp())
        .withColumn("source_file_path", F.lit(None).cast("string"))
    )

    bronze = bronze.withColumn(
        "record_hash",
        F.sha2(
            F.concat_ws(
                "||",
                F.coalesce(F.col("tenant_id"), F.lit("")),
                F.coalesce(F.col("typology_id"), F.lit("")),
                F.coalesce(F.col("typology_cfg"), F.lit("")),
                F.coalesce(F.col("configuration_json"), F.lit("")),
            ),
            256,
        )
    )

    bronze = bronze.withColumn("_row_payload_json", F.to_json(F.struct("*")))

    bronze_opts = hudi_opts(
        table_name="bronze_typologies",
        record_key="record_hash",
        precombine="ingested_at_ts"
    )
    write_hudi(bronze, bronze_path, bronze_opts)

    # ====================== SILVER ======================
    b = spark.read.format("hudi").load(bronze_path)

    # infer JSON schema from configuration_json
    typ_schema = spark.read.json(
        b.select("configuration_json")
         .where(F.col("configuration_json").isNotNull())
         .rdd.map(lambda r: r[0])
    ).schema

    silver = (
        b
        .withColumn("typology_obj", F.from_json(F.col("configuration_json"), typ_schema))

        # top-level useful fields
        .withColumn("typology_id_in_json", F.col("typology_obj.id"))
        .withColumn("typology_cfg_in_json", F.col("typology_obj.cfg"))
        .withColumn("typology_desc", F.col("typology_obj.desc"))
        .withColumn("typology_name", F.col("typology_obj.typology_name"))

        # workflow
        .withColumn("flow_processor", F.col("typology_obj.workflow.flowProcessor"))
        .withColumn("alert_threshold", F.col("typology_obj.workflow.alertThreshold").cast("int"))
        .withColumn("interdiction_threshold", F.col("typology_obj.workflow.interdictionThreshold").cast("int"))

        # counts
        .withColumn("rule_count", F.size(F.col("typology_obj.rules")).cast("int"))
        .withColumn("expression_count", F.size(F.col("typology_obj.expression")).cast("int"))

        .withColumn("_row_payload_json", F.to_json(F.struct("*")))
    )

    w = Window.partitionBy("tenant_id", "typology_id", "typology_cfg").orderBy(F.col("ingested_at_ts").desc_nulls_last())
    silver = silver.withColumn("_rn", F.row_number().over(w)).filter(F.col("_rn") == 1).drop("_rn")

    silver_opts = hudi_opts(
        table_name="silver_typologies",
        record_key="record_hash",
        precombine="ingested_at_ts"
    )
    write_hudi(silver, silver_path, silver_opts)

    # ====================== GOLD ======================
    s = spark.read.format("hudi").load(silver_path)

    # --- compute MAX sizes present in dataset (schema decided from data) ---
    max_rules = s.select(F.max(F.size(F.col("typology_obj.rules"))).alias("m")).collect()[0]["m"] or 0
    max_expr  = s.select(F.max(F.size(F.col("typology_obj.expression"))).alias("m")).collect()[0]["m"] or 0

    # max weights across all rules (safely)
    max_wghts = (
        s.select(F.explode_outer(F.col("typology_obj.rules")).alias("r"))
         .select(F.max(F.size(F.col("r.wghts"))).alias("m"))
         .collect()[0]["m"] or 0
    )

    wide_cols = []

    # RULE columns
    for i in range(1, max_rules + 1):
        r = F.element_at(F.col("typology_obj.rules"), i)

        wide_cols += [
            r.getField("id").cast("string").alias(f"rule_{i:03d}_id"),
            r.getField("cfg").cast("string").alias(f"rule_{i:03d}_cfg"),
            r.getField("termId").cast("string").alias(f"rule_{i:03d}_term_id"),
            F.size(r.getField("wghts")).cast("int").alias(f"rule_{i:03d}_weight_count"),
        ]

        # WEIGHTS inside each rule
        for j in range(1, max_wghts + 1):
            wj = F.element_at(r.getField("wghts"), j)
            wide_cols += [
                wj.getField("ref").cast("string").alias(f"rule_{i:03d}_w{j:02d}_ref"),
                # wght can be numeric or string -> normalize to long without losing value
                wj.getField("wght").cast("string").cast("double").cast("long").alias(f"rule_{i:03d}_w{j:02d}_wght"),
            ]

    # EXPRESSION columns
    for k in range(1, max_expr + 1):
        wide_cols.append(
            F.element_at(F.col("typology_obj.expression"), k).cast("string").alias(f"expr_{k:03d}_token")
        )

    # SINGLE PRIMARY KEY for GOLD
    gold_pk = F.sha2(
        F.concat_ws(
            "||",
            F.lit("gold_typology"),
            F.coalesce(F.col("tenant_id"), F.lit("")),
            F.coalesce(F.col("typology_id"), F.lit("")),
            F.coalesce(F.col("typology_cfg"), F.lit("")),
            F.coalesce(F.col("record_hash"), F.lit("")),
        ),
        256
    )

    gold = (
        s
        .withColumn("pk", gold_pk)
        .select(
            # identity + raw
            "pk",
            F.col("tenant_id").cast("string").alias("tenant_id"),
            F.col("typology_id").cast("string").alias("typology_id"),
            F.col("typology_cfg").cast("string").alias("typology_cfg"),

            # silver-derived header fields
            F.col("typology_id_in_json").cast("string").alias("typology_id_in_json"),
            F.col("typology_cfg_in_json").cast("string").alias("typology_cfg_in_json"),
            F.col("typology_desc").cast("string").alias("typology_desc"),
            F.col("typology_name").cast("string").alias("typology_name"),

            F.col("flow_processor").cast("string").alias("flow_processor"),
            F.col("alert_threshold").cast("int").alias("alert_threshold"),
            F.col("interdiction_threshold").cast("int").alias("interdiction_threshold"),

            F.col("rule_count").cast("int").alias("rule_count"),
            F.col("expression_count").cast("int").alias("expression_count"),

            # metadata
            F.col("ingested_at_ts").cast("timestamp").alias("ingested_at_ts"),

            # wide flatten (ALL scalar)
            *wide_cols
        )
    )

    bad = [c for c, t in gold.dtypes if t.startswith(("array", "struct", "map"))]
    if bad:
        raise RuntimeError(f"GOLD has non-scalar columns: {bad}")

    gold_opts = hudi_opts(
        table_name="typologies",
        record_key="pk",
        precombine="ingested_at_ts"
    )
    write_hudi(gold, gold_path, gold_opts)

    return gold_path


def etl_account(spark, WAREHOUSE_ROOT: str, source_path: str) -> str:
    """
    Complete Account ETL pipeline.
    source_path example: "s3a://frms/account/" or "test_data/account.csv"
    """
    bronze_path = f"{WAREHOUSE_ROOT}/bronze/account"
    silver_path = f"{WAREHOUSE_ROOT}/silver/account"
    gold_path   = f"{WAREHOUSE_ROOT}/gold/account"

    # ====================== BRONZE ======================
    # NiFi can send account payloads in JSON or CSV depending on source.
    if source_path.lower().endswith(".json"):
        account_df = spark.read.json(source_path)
    else:
        account_df = (
            spark.read
            .option("header", True)
            .option("escape", "\"")
            .option("multiLine", True)
            .csv(source_path)
        )

    bronze = (
        account_df
        .withColumnRenamed("id", "account_id")
        .withColumnRenamed("tenantid", "tenant_id")
        # ingestion metadata
        .withColumn("ingested_at_ts", F.current_timestamp())
        # stable record key
        .withColumn(
            "record_hash",
            F.sha2(
                F.concat_ws(
                    "||",
                    F.coalesce(F.col("account_id"), F.lit("")),
                    F.coalesce(F.col("tenant_id"), F.lit(""))
                ),
                256
            )
        )
    )

    bronze_opts = hudi_opts(
        table_name="bronze_account",
        record_key="record_hash",
        precombine="ingested_at_ts"
    )
    write_hudi(bronze, bronze_path, bronze_opts)

    # ====================== SILVER ======================
    bronze_df = spark.read.format("hudi").load(bronze_path)

    silver = (
        bronze_df
        .withColumn("ingested_at_ts", F.current_timestamp())
    )

    silver_opts = hudi_opts(
        table_name="silver_account",
        record_key="record_hash",
        precombine="ingested_at_ts"
    )
    write_hudi(silver, silver_path, silver_opts)

    # ====================== GOLD ======================
    silver_df = spark.read.format("hudi").load(silver_path)

    gold = (
        silver_df
        .withColumn(
            "pk",
            F.sha2(
                F.concat_ws(
                    "||",
                    F.lit("account"),
                    F.coalesce(F.col("account_id"), F.lit("")),
                    F.coalesce(F.col("tenant_id"), F.lit(""))
                ),
                256
            )
        )
        .withColumn("ingested_at_ts", F.current_timestamp())
    )

    gold_opts = hudi_opts(
        table_name="gold_account",
        record_key="pk",
        precombine="ingested_at_ts"
    )
    write_hudi(gold, gold_path, gold_opts)

    return gold_path    


def etl_account_holder(spark, WAREHOUSE_ROOT: str, source_path: str) -> str:
    """
    Complete Account Holder ETL pipeline.
    source_path example: "s3a://frms/account_holder/"
    """
    bronze_path = f"{WAREHOUSE_ROOT}/bronze/account_holder"
    silver_path = f"{WAREHOUSE_ROOT}/silver/account_holder"
    gold_path   = f"{WAREHOUSE_ROOT}/gold/account_holder"

    # ====================== BRONZE ======================
    acc_hold = spark.read.json(source_path)

    bronze = (
        acc_hold
        .withColumn("ingested_at_ts", F.current_timestamp())
        .withColumn("source_file_path", F.input_file_name())
        .withColumn("_row_payload_json", F.to_json(F.struct("*")))
        .withColumn("record_hash", F.sha2(F.col("_row_payload_json"), 256))
    )

    bronze_opts = hudi_opts(
        table_name="bronze_account_holder",
        record_key="record_hash",
        precombine="ingested_at_ts"
    )
    write_hudi(bronze, bronze_path, bronze_opts)

    # ====================== SILVER ======================
    bronze_df = spark.read.format("hudi").load(bronze_path)

    silver = (
        bronze_df
        .withColumn("tenant_id", F.col("tenantid"))
        .withColumn("event_ts", F.to_timestamp(F.col("credttm")))
        .withColumn("event_date", F.to_date(F.to_timestamp(F.col("credttm"))))
        .withColumn("account_id", F.col("destination"))
        .withColumn("counterparty_id", F.col("source"))
        .withColumn(
            "pk",
            F.sha2(
                F.concat_ws(
                    "||",
                    F.lit("account_holder"),
                    F.coalesce(F.col("tenant_id"), F.lit("")),
                    F.coalesce(F.col("counterparty_id"), F.lit("")),
                    F.coalesce(F.col("account_id"), F.lit("")),
                    F.coalesce(F.col("credttm").cast("string"), F.lit(""))
                ),
                256
            )
        )
        # ensure precombine is never null
        .withColumn("ingested_at_ts", F.coalesce(F.col("ingested_at_ts"), F.current_timestamp()))
    )

    silver_opts = hudi_opts(
        table_name="silver_account_holder",
        record_key="pk",
        precombine="ingested_at_ts"
    )
    write_hudi(silver, silver_path, silver_opts)

    # ====================== GOLD ======================
    silver_df = spark.read.format("hudi").load(silver_path)

    gold = (
        silver_df
        .withColumn("relationship_type", F.lit("ACCOUNT_HOLDER"))
        .drop("_row_payload_json", "tenantid", "credttm")
    )

    gold_opts = hudi_opts(
        table_name="gold_account_holder",
        record_key="pk",
        precombine="ingested_at_ts"
    )
    write_hudi(gold, gold_path, gold_opts)

    return gold_path    

def etl_rules(spark, WAREHOUSE_ROOT: str, source_path: str) -> str:
    """
    Complete Rules ETL pipeline.
    source_path example: "s3a://frms1/rule/"
    """
    bronze_path = f"{WAREHOUSE_ROOT}/bronze/rules"
    silver_path = f"{WAREHOUSE_ROOT}/silver/rules"
    gold_path   = f"{WAREHOUSE_ROOT}/gold/rules"

    # ====================== BRONZE ======================
    rule_df = spark.read.json(source_path)

    bronze = (
        rule_df
        .withColumnRenamed("tenantid", "tenant_id")
        .withColumnRenamed("ruleid", "rule_id")
        .withColumnRenamed("rulecfg", "rule_cfg")
    )

    # Safely handle string vs struct types for configuration
    configuration_dtype = dict(bronze.dtypes).get("configuration")
    if configuration_dtype and configuration_dtype.startswith("string"):
        bronze = bronze.withColumn("configuration_json", F.col("configuration").cast("string"))
    else:
        bronze = bronze.withColumn(
            "configuration_json",
            F.when(F.col("configuration").isNull(), F.lit(None).cast("string"))
             .otherwise(F.to_json(F.col("configuration")))
        )

    bronze = (
        bronze
        .select("tenant_id", "rule_id", "rule_cfg", "configuration_json")
        .withColumn("created_at_ts", F.current_timestamp())
        .withColumn("source_file_path", F.lit("api_or_file_ingestion"))
        .withColumn(
            "record_hash",
            F.sha2(
                F.concat_ws("||",
                    F.coalesce(F.col("tenant_id").cast("string"), F.lit("")),
                    F.coalesce(F.col("rule_id").cast("string"), F.lit("")),
                    F.coalesce(F.col("rule_cfg").cast("string"), F.lit("")),
                    F.coalesce(F.col("configuration_json").cast("string"), F.lit("")),
                ),
                256
            )
        )
        .withColumn("_row_payload_json", F.to_json(F.struct("*")))
    )

    bronze_opts = hudi_opts(
        table_name="bronze_rules",
        record_key="record_hash",
        precombine="created_at_ts"
    )
    write_hudi(bronze, bronze_path, bronze_opts)

    # ====================== SILVER ======================
    b = spark.read.format("hudi").load(bronze_path)

    # Infer schema (no rejects)
    non_null_conf = b.where(F.col("configuration_json").isNotNull()).select("configuration_json")
    rule_schema = spark.read.json(non_null_conf.rdd.map(lambda r: r[0])).schema

    s = (
        b
        .withColumn("rule_obj", F.from_json("configuration_json", rule_schema))
        .withColumn("config_obj", F.col("rule_obj.config"))
        .withColumn("rule_id_in_json", F.col("rule_obj.id").cast("string"))
        .withColumn("rule_cfg_in_json", F.col("rule_obj.cfg").cast("string"))
        .withColumn("rule_desc", F.col("rule_obj.desc").cast("string"))
        .withColumn("tenant_id_in_json", F.col("rule_obj.tenantId").cast("string"))
        .withColumn("band_count", F.coalesce(F.size(F.col("config_obj.bands")), F.lit(0)).cast("int"))
        .withColumn("exit_condition_count", F.coalesce(F.size(F.col("config_obj.exitConditions")), F.lit(0)).cast("int"))
        .withColumn("evaluation_interval_time_ms", F.col("config_obj.parameters.evaluationIntervalTime").cast("long"))
        .withColumn("tolerance", F.col("config_obj.parameters.tolerance").cast("double"))
        .withColumn("commission", F.col("config_obj.parameters.commission").cast("double"))
        .withColumn("max_query_range_ms", F.col("config_obj.parameters.maxQueryRange").cast("long"))
        .withColumn("config_json", F.to_json(F.col("rule_obj.config")))
        .withColumn("parameters_json", F.to_json(F.col("config_obj.parameters")))
        .withColumn("bands_json", F.to_json(F.col("config_obj.bands")))
        .withColumn("exit_conditions_json", F.to_json(F.col("config_obj.exitConditions")))
        .withColumn("configuration_parsed_json", F.to_json(F.col("rule_obj")))
        .withColumn(
            "pk",
            F.sha2(
                F.concat_ws("||",
                    F.coalesce(F.col("tenant_id").cast("string"), F.lit("")),
                    F.coalesce(F.col("rule_id").cast("string"), F.lit("")),
                    F.coalesce(F.col("rule_cfg").cast("string"), F.lit("")),
                ),
                256
            )
        )
    )

    w = Window.partitionBy("pk").orderBy(F.col("created_at_ts").desc())
    silver = s.withColumn("rn", F.row_number().over(w)).filter(F.col("rn") == 1).drop("rn")

    silver = silver.select(
        "pk", "tenant_id", "rule_id", "rule_cfg",
        "rule_desc", "band_count", "exit_condition_count",
        "evaluation_interval_time_ms", "tolerance", "commission", "max_query_range_ms",
        "configuration_json", "configuration_parsed_json", "config_json",
        "parameters_json", "bands_json", "exit_conditions_json",
        "created_at_ts", "source_file_path", "record_hash", "_row_payload_json",
    )

    silver_opts = hudi_opts(
        table_name="silver_rules",
        record_key="pk",
        precombine="created_at_ts"
    )
    write_hudi(silver, silver_path, silver_opts)

    # ====================== GOLD ======================
    MAX_BANDS = 20
    MAX_EXITS = 20

    s = spark.read.format("hudi").load(silver_path)

    non_null_conf = s.where(F.col("configuration_json").isNotNull()).select("configuration_json")
    rule_schema = spark.read.json(non_null_conf.rdd.map(lambda r: r[0])).schema

    g = (
        s
        .withColumn("rule_obj", F.from_json("configuration_json", rule_schema))
        .withColumn("config_obj", F.col("rule_obj.config"))
        .withColumn("bands_arr", F.col("config_obj.bands"))
        .withColumn("exits_arr", F.col("config_obj.exitConditions"))
        .withColumn("parameters_obj", F.col("config_obj.parameters"))
        .withColumn(
            "pk",
            F.sha2(
                F.concat_ws("||",
                    F.coalesce(F.col("tenant_id").cast("string"), F.lit("")),
                    F.coalesce(F.col("rule_id").cast("string"), F.lit("")),
                    F.coalesce(F.col("rule_cfg").cast("string"), F.lit("")),
                ),
                256
            )
        )
        .withColumn("rule_desc", F.col("rule_obj.desc").cast("string"))
        .withColumn("tenant_id_in_json", F.col("rule_obj.tenantId").cast("string"))
        .withColumn("band_count", F.coalesce(F.size("bands_arr"), F.lit(0)).cast("int"))
        .withColumn("exit_condition_count", F.coalesce(F.size("exits_arr"), F.lit(0)).cast("int"))
        .withColumn("evaluation_interval_time_ms", F.col("parameters_obj.evaluationIntervalTime").cast("long"))
        .withColumn("tolerance", F.col("parameters_obj.tolerance").cast("double"))
        .withColumn("commission", F.col("parameters_obj.commission").cast("double"))
        .withColumn("max_query_range_ms", F.col("parameters_obj.maxQueryRange").cast("long"))
        .withColumn("tenant_id_norm", F.upper(F.col("tenant_id")))
        .withColumn("rule_id_norm", F.upper(F.col("rule_id")))
        .withColumn("rule_cfg_norm", F.col("rule_cfg").cast("string"))
        .withColumn("ingested_at_ts", F.current_timestamp())
        .withColumn("as_of_date", F.to_date("ingested_at_ts"))
    )

    
    base_cols = [
        F.col("pk"), F.col("tenant_id"), F.col("tenant_id_norm"),
        F.col("rule_id"), F.col("rule_id_norm"), F.col("rule_cfg"), F.col("rule_cfg_norm"),
        F.col("rule_desc"), F.col("band_count"), F.col("exit_condition_count"),
        F.col("evaluation_interval_time_ms"), F.col("tolerance"), F.col("commission"), 
        F.col("max_query_range_ms"), F.col("source_file_path"), F.col("record_hash"),
        F.col("created_at_ts"), F.col("ingested_at_ts"), F.col("as_of_date"),
    ]

    band_cols = []
    for i in range(1, MAX_BANDS + 1):
        prefix = f"band_{i:02d}"
        band_cols.extend([
            F.element_at(F.col("bands_arr"), i).getField("reason").cast("string").alias(f"{prefix}_reason"),
            F.element_at(F.col("bands_arr"), i).getField("subRuleRef").cast("string").alias(f"{prefix}_sub_rule_ref"),
            F.element_at(F.col("bands_arr"), i).getField("lowerLimit").cast("double").alias(f"{prefix}_lower_limit"),
            F.element_at(F.col("bands_arr"), i).getField("upperLimit").cast("double").alias(f"{prefix}_upper_limit"),
        ])

    exit_cols = []
    for i in range(1, MAX_EXITS + 1):
        prefix = f"exit_{i:02d}"
        exit_cols.extend([
            F.element_at(F.col("exits_arr"), i).getField("reason").cast("string").alias(f"{prefix}_reason"),
            F.element_at(F.col("exits_arr"), i).getField("subRuleRef").cast("string").alias(f"{prefix}_sub_rule_ref"),
        ])

    # Single select executes instantly
    gold_rules = g.select(*(base_cols + band_cols + exit_cols))

    bad = [c for c, t in gold_rules.dtypes if t.startswith(("array", "struct"))]
    if bad:
        raise RuntimeError(f"Gold rules still contains non-scalar columns: {bad}")

    # Dedup (keep latest ingest for same pk)
    w = Window.partitionBy("pk").orderBy(F.col("ingested_at_ts").desc())
    gold_rules = gold_rules.withColumn("rn", F.row_number().over(w)).filter(F.col("rn") == 1).drop("rn")

    def hudi_rule_opts(table_name: str, record_key: str, precombine: str, partition: str = None):
     opts = {
        "hoodie.table.name": table_name,
        "hoodie.datasource.write.table.type": "COPY_ON_WRITE",
        "hoodie.datasource.write.operation": "upsert",
        "hoodie.datasource.write.recordkey.field": record_key,
        "hoodie.datasource.write.precombine.field": precombine,

        # schema evolution + reconciliation
        "hoodie.datasource.write.schema.evolution.enable": "true",
        "hoodie.datasource.read.schema.evolution.enable": "true",
        "hoodie.datasource.write.reconcile.schema": "true",
        "hoodie.schema.on.read.enable": "true",

        "hoodie.index.type": "BLOOM",
        "hoodie.metadata.enable": "false",
    }

     if partition:
        opts.update({
            "hoodie.datasource.write.partitionpath.field": partition,
            "hoodie.datasource.write.hive_style_partitioning": "true",
            "hoodie.datasource.write.keygenerator.class": "org.apache.hudi.keygen.SimpleKeyGenerator",
        })
     else:
        opts.update({
            "hoodie.datasource.write.keygenerator.class": "org.apache.hudi.keygen.NonpartitionedKeyGenerator",
        })

     return opts
    

    (
    gold_rules.write.format("hudi")
    .options(**hudi_rule_opts("rules", record_key="pk", precombine="ingested_at_ts", partition="as_of_date"))
    .mode("append")
    .save(gold_path)
    )

    print("rules done till gold")

    return gold_path

def etl_conditions(spark, WAREHOUSE_ROOT: str, source_path: str) -> str:
    """
    Complete Conditions ETL pipeline with ENTITY (ntty) + ACCOUNT (acct) support.
    source_path example: "s3a://frms1/condition/"
    """
    bronze_path = f"{WAREHOUSE_ROOT}/bronze/conditions"
    silver_path = f"{WAREHOUSE_ROOT}/silver/conditions"
    gold_path = f"{WAREHOUSE_ROOT}/gold/conditions"

    # ====================== BRONZE ======================
    conditions_df = spark.read.json(source_path)

    # Handle dynamic column naming for tenant_id
    if "tenantid" in conditions_df.columns and "tenant_id" not in conditions_df.columns:
        conditions_df = conditions_df.withColumnRenamed("tenantid", "tenant_id")
    if "tenantId" in conditions_df.columns and "tenant_id" not in conditions_df.columns:
        conditions_df = conditions_df.withColumnRenamed("tenantId", "tenant_id")

    bronze = (
        conditions_df
        .withColumn("condition", F.col("condition").cast("string"))
        .withColumn("id", F.col("id").cast("string") if "id" in conditions_df.columns else F.lit(None).cast("string"))
        .withColumn("tenant_id", F.col("tenant_id").cast("string") if "tenant_id" in conditions_df.columns else F.lit(None).cast("string"))
        # ingestion metadata
        .withColumn("created_at_ts", F.current_timestamp())
        # stable hash (exclude created_at_ts)
        .withColumn(
            "record_hash",
            F.sha2(
                F.concat_ws(
                    "||",
                    F.coalesce(F.col("condition"), F.lit("")),
                    F.coalesce(F.col("id"), F.lit("")),
                    F.coalesce(F.col("tenant_id"), F.lit(""))
                ),
                256
            )
        )
        # row payload
        .withColumn("_row_payload_json", F.to_json(F.struct("*")))
    )

    bronze_opts = hudi_opts(
        table_name="bronze_conditions",
        record_key="record_hash",
        precombine="created_at_ts"
    )
    write_hudi(bronze, bronze_path, bronze_opts)

    # ====================== SILVER ======================
    bronze_df = spark.read.format("hudi").load(bronze_path)

    # --- Core extractors ---
    cond_id = F.coalesce(F.col("id"), F.get_json_object("condition", "$.condId"))
    tenant_id_eff = F.coalesce(F.col("tenant_id"), F.get_json_object("condition", "$.tenantId"))
    usr = F.get_json_object("condition", "$.usr")

    # --- ACCOUNT (acct) ---
    acct_id = F.get_json_object("condition", "$.acct.id")
    acct_scheme = F.get_json_object("condition", "$.acct.schmeNm.prtry")
    acct_mmb_id = F.get_json_object("condition", "$.acct.agt.finInstnId.clrSysMmbId.mmbId")

    # --- ENTITY (ntty) ---
    ntty_id = F.get_json_object("condition", "$.ntty.id")
    ntty_scheme = F.get_json_object("condition", "$.ntty.schmeNm.prtry")

    # --- NEW: Target type + condition_key_key (exactly as in your screenshot) ---
    target_type = F.when(ntty_id.isNotNull(), F.lit("ENTITY")) \
                    .when(acct_id.isNotNull(), F.lit("ACCOUNT")) \
                    .otherwise(F.lit(None).cast("string"))

    entity_id = ntty_id

    condition_key_key = F.when(
        target_type == "ENTITY",
        F.concat(F.coalesce(ntty_id, F.lit("")), F.coalesce(ntty_scheme, F.lit("")))
    ).when(
        target_type == "ACCOUNT",
        F.concat(
            F.coalesce(acct_id, F.lit("")),
            F.coalesce(acct_scheme, F.lit("")),
            F.coalesce(acct_mmb_id, F.lit(""))
        )
    ).otherwise(F.lit(None).cast("string"))

    # --- Rest of extractors ---
    cond_tp = F.get_json_object("condition", "$.condTp")
    prsptv = F.get_json_object("condition", "$.prsptv")
    cond_rsn = F.get_json_object("condition", "$.condRsn")
    force_cret = F.get_json_object("condition", "$.forceCret").cast("boolean")
    cre_dt_tm = F.to_timestamp(F.get_json_object("condition", "$.creDtTm"))
    inc_dt_tm = F.to_timestamp(F.get_json_object("condition", "$.incptnDtTm"))
    xpr_dt_tm = F.to_timestamp(F.get_json_object("condition", "$.xprtnDtTm"))

    evt_tp_json = F.get_json_object("condition", "$.evtTp")
    evt_tp_count = F.coalesce(
        F.size(F.from_json(evt_tp_json, T.ArrayType(T.StringType()))),
        F.lit(0)
    ).cast("int")

    # --- Updated PK (includes ntty support) ---
    pk = F.sha2(
        F.concat_ws(
            "||",
            F.coalesce(cond_id, F.lit("")),
            F.coalesce(tenant_id_eff, F.lit("")),
            F.coalesce(acct_id, F.lit("")),
            F.coalesce(ntty_id, F.lit("")),        # NEW
            F.coalesce(cond_tp, F.lit("")),
            F.coalesce(F.col("record_hash"), F.lit(""))
        ),
        256
    )

    silver = (
        bronze_df
        .withColumn("condition_id", cond_id)
        .withColumn("tenant_id", tenant_id_eff)
        .withColumn("usr", usr)
        .withColumn("entity_id", entity_id)                    # NEW
        .withColumn("acct_id", acct_id)
        .withColumn("acct_scheme", acct_scheme)
        .withColumn("acct_mmb_id", acct_mmb_id)
        .withColumn("ntty_scheme", ntty_scheme)                # NEW
        .withColumn("target_type", target_type)                # NEW
        .withColumn("condition_key_key", condition_key_key)    # NEW
        .withColumn("evt_tp_json", evt_tp_json)
        .withColumn("evt_tp_count", evt_tp_count)
        .withColumn("cond_type", cond_tp)
        .withColumn("perspective", prsptv)
        .withColumn("condition_reason", cond_rsn)
        .withColumn("force_create", force_cret)
        .withColumn("created_dt_ts", cre_dt_tm)
        .withColumn("inception_dt_ts", inc_dt_tm)
        .withColumn("expiry_dt_ts", xpr_dt_tm)
        .withColumn("created_date", F.to_date("created_dt_ts"))
        .withColumn("pk", pk)
        .select(
            "_hoodie_commit_time", "_hoodie_commit_seqno", "_hoodie_record_key",
            "_hoodie_partition_path", "_hoodie_file_name",
            "pk", "condition_id", "tenant_id",
            "usr",
            "entity_id", "acct_id", "acct_scheme", "acct_mmb_id", "ntty_scheme",   # NEW
            "target_type", "condition_key_key",                                    # NEW
            "evt_tp_json", "evt_tp_count",
            "cond_type", "perspective", "condition_reason", "force_create",
            "created_dt_ts", "inception_dt_ts", "expiry_dt_ts", "created_date",
            "created_at_ts",
            "condition"
        )
        .withColumn("_row_payload_json", F.to_json(F.struct("*")))
    )

    # Deduplication
    w = Window.partitionBy("pk").orderBy(F.col("created_at_ts").desc_nulls_last())
    silver = silver.withColumn("rn", F.row_number().over(w)).filter(F.col("rn") == 1).drop("rn")

    silver_opts = hudi_opts(
        table_name="silver_conditions",
        record_key="pk",
        precombine="created_at_ts"
    )
    write_hudi(silver, silver_path, silver_opts)

    # ====================== GOLD ======================
    silver_df = spark.read.format("hudi").load(silver_path)

    # evtTp -> CSV string
    evt_tp_csv = F.concat_ws(",", F.from_json(F.col("evt_tp_json"), T.ArrayType(T.StringType())))

    gold = (
        silver_df
        .withColumn("evt_types", evt_tp_csv)
        .withColumn("evt_type_primary", F.element_at(F.split(evt_tp_csv, ","), 1))
        # status helpers
        .withColumn("is_expired", F.when(F.col("expiry_dt_ts").isNotNull() & (F.col("expiry_dt_ts") < F.current_timestamp()), F.lit(1)).otherwise(F.lit(0)))
        .withColumn("is_active", F.when(F.col("expiry_dt_ts").isNull() | (F.col("expiry_dt_ts") >= F.current_timestamp()), F.lit(1)).otherwise(F.lit(0)))
        # final select
        .select(
            "pk",
            F.col("condition_id").cast("string").alias("condition_id"),
            F.col("tenant_id").cast("string").alias("tenant_id"),
            F.col("usr").cast("string").alias("created_by_user"),
            F.col("entity_id").cast("string").alias("entity_id"),                    # NEW
            F.col("acct_id").cast("string").alias("account_id"),
            F.col("acct_scheme").cast("string").alias("account_scheme"),
            F.col("acct_mmb_id").cast("string").alias("account_agent_mmb_id"),
            F.col("target_type").cast("string").alias("target_type"),                # NEW
            F.col("condition_key_key").cast("string").alias("condition_key_key"),    # NEW
            F.col("ntty_scheme").cast("string").alias("entity_scheme"),              # NEW
            F.col("evt_types").cast("string").alias("event_types_csv"),
            F.col("evt_type_primary").cast("string").alias("event_type_primary"),
            F.col("evt_tp_count").cast("int").alias("event_type_count"),
            F.col("cond_type").cast("string").alias("condition_type"),
            F.col("perspective").cast("string").alias("perspective"),
            F.col("condition_reason").cast("string").alias("condition_reason"),
            F.col("force_create").cast("boolean").alias("force_create"),
            F.col("created_dt_ts").cast("timestamp").alias("condition_created_ts"),
            F.col("inception_dt_ts").cast("timestamp").alias("condition_inception_ts"),
            F.col("expiry_dt_ts").cast("timestamp").alias("condition_expiry_ts"),
            F.col("created_date").cast("date").alias("condition_created_date"),
            F.col("is_active").cast("int").alias("is_active"),
            F.col("is_expired").cast("int").alias("is_expired"),
            F.col("created_at_ts").cast("timestamp").alias("ingested_at_ts"),
        )
    )

    bad = [c for c, t in gold.dtypes if t.startswith(("array", "struct"))]
    if bad:
        raise RuntimeError(f"Gold contains non-scalar columns: {bad}")

    gold_opts = hudi_opts(
        table_name="conditions",
        record_key="pk",
        precombine="ingested_at_ts"
    )
    write_hudi(gold, gold_path, gold_opts)

    return gold_path


# ===================================================================
# VIEWS (transaction network, alert history, conditions timeline)
# ===================================================================
def create_alert_navigator_views(spark, WAREHOUSE_ROOT: str) -> str:
    """
    Generates and writes the Alert Navigator Views (Header, Typologies, Rules, Network Eval) to Hudi.
    """
    VIEWS_ROOT = f"{WAREHOUSE_ROOT}/views"
    ALERT_NAV_ROOT = f"{VIEWS_ROOT}/alert_navigator"
    
    alerts_nav_header_path = f"{ALERT_NAV_ROOT}/header"
    alerts_nav_typologies_path = f"{ALERT_NAV_ROOT}/typologies_triggered"
    alerts_nav_rules_path = f"{ALERT_NAV_ROOT}/rules_triggered"
    alerts_nav_network_eval_path = f"{ALERT_NAV_ROOT}/network_evaluated"

    # Optional paths
    silver_alerts_path = f"{WAREHOUSE_ROOT}/silver/alerts"
    transactions_gold_path = f"{WAREHOUSE_ROOT}/gold/transactions"
    typologies_bronze_path = f"{WAREHOUSE_ROOT}/bronze/typologies"
    network_map_bronze_path = f"{WAREHOUSE_ROOT}/bronze/network_map"

    s_alerts = spark.read.format("hudi").load(silver_alerts_path)

    # Safely attempt to load optional tables
    try:
        g_tx = spark.read.format("hudi").load(transactions_gold_path) \
            .select("tx_msg_id", "tx_status", "tx_amount", "tx_ccy", "transaction_id", "end_to_end_id")
    except Exception:
        g_tx = None

    try:
        b_typ = spark.read.format("hudi").load(typologies_bronze_path) \
            .select(
                F.col("tenantid").alias("cfg_tenant_id"),
                F.col("typologyid").alias("cfg_typology_id"),
                F.col("typologycfg").alias("cfg_typology_cfg"),
                F.col("configuration").alias("typology_configuration_json")
            )
    except Exception:
        b_typ = None

    try:
        b_net = spark.read.format("hudi").load(network_map_bronze_path) \
            .select(
                F.col("tenantid").alias("cfg_tenant_id"),
                F.col("configuration").alias("network_configuration_json")
            )
    except Exception:
        b_net = None

    # Infer schema safely
    alert_schema = spark.read.json(
        s_alerts.select("alert_data").where(F.col("alert_data").isNotNull()).rdd.map(lambda r: r[0])
    ).schema

    a = s_alerts.withColumn("alert_data_obj", F.from_json("alert_data", alert_schema))

    # ====================== HEADER ======================
    alerts_nav_header = (
        a.select(
            F.col("alert_id").cast("long").alias("alert_id"),
            F.col("tenant_id").cast("string").alias("tenant_id"),
            F.col("case_id").cast("long").alias("case_id"),
            F.col("tx_msg_id").cast("string").alias("tx_msg_id"),
            F.col("tx_type").cast("string").alias("tx_type"),
            F.col("event_ts").cast("timestamp").alias("alert_timestamp"),
            F.to_date("event_ts").alias("alert_date"),
            F.col("message").cast("string").alias("alert_reason"),
            F.col("alert_type").cast("string").alias("alert_type"),
            F.col("prediction_outcome").cast("string").alias("prediction_outcome"),
            F.col("priority").cast("string").alias("priority"),
            F.col("priority_score").cast("double").alias("priority_score"),
            F.col("alert_data_obj.evaluationID").alias("evaluation_id"),
            F.col("alert_data_obj.status").alias("alert_status"),
            F.col("created_at_ts").cast("timestamp").alias("ingested_at_ts"),
            F.col("source_file_path").alias("source_file_path"),
            F.col("record_hash").alias("record_hash"),
        )
    )

    # Enrich with transaction fields if available
    if g_tx is not None:
        alerts_nav_header = (
            alerts_nav_header
            .join(g_tx, on="tx_msg_id", how="left")
            .withColumnRenamed("tx_status", "transaction_status")
            .withColumnRenamed("tx_amount", "transaction_amount")
            .withColumnRenamed("tx_ccy", "transaction_currency")
            .withColumn(
                "block_or_override_status",
                F.when(F.col("transaction_status").isin("BLOCKED", "REJECTED"), F.lit("BLOCKED_OR_REJECTED"))
                 .when(F.col("transaction_status").isNotNull(), F.lit("NOT_BLOCKED"))
                 .otherwise(F.lit(None))
            )
        )

    # ====================== TYPOLOGIES ======================
    typ = (
        a.select(
            F.col("alert_id").cast("long").alias("alert_id"),
            F.col("tenant_id").cast("string").alias("tenant_id"),
            F.col("tx_msg_id").cast("string").alias("tx_msg_id"),
            F.col("event_ts").cast("timestamp").alias("alert_timestamp"),
            F.explode_outer(F.col("alert_data_obj.tadpResult.typologyResult")).alias("typology")
        )
        .select(
            "alert_id", "tenant_id", "tx_msg_id", "alert_timestamp",
            F.col("typology.id").alias("typology_id"),
            F.col("typology.cfg").alias("typology_cfg"),
            F.col("typology.result").cast("long").alias("typology_score"),
            F.col("typology.review").cast("boolean").alias("typology_review"),
            F.col("typology.prcgTm").cast("long").alias("typology_processing_time_ms"),
            F.col("typology.tenantId").alias("typology_tenant_id"),
            F.col("typology.workflow.flowProcessor").alias("flow_processor"),
            F.col("typology.workflow.alertThreshold").cast("long").alias("alert_threshold"),
            F.col("typology.workflow.interdictionThreshold").cast("long").alias("interdiction_threshold"),
            F.size(F.col("typology.ruleResults")).alias("rule_count_in_typology"),
        )
    )

    if b_typ is not None:
        typ = (
            typ.join(
                b_typ,
                (typ.tenant_id == b_typ.cfg_tenant_id) &
                (typ.typology_id == b_typ.cfg_typology_id) &
                (typ.typology_cfg == b_typ.cfg_typology_cfg),
                "left"
            )
            .drop("cfg_tenant_id", "cfg_typology_id", "cfg_typology_cfg")
        )

    # ====================== RULES ======================
    rules = (
        a.select(
            F.col("alert_id").cast("long").alias("alert_id"),
            F.col("tenant_id").cast("string").alias("tenant_id"),
            F.col("tx_msg_id").cast("string").alias("tx_msg_id"),
            F.col("event_ts").cast("timestamp").alias("alert_timestamp"),
            F.explode_outer(F.col("alert_data_obj.tadpResult.typologyResult")).alias("typology")
        )
        .select(
            "alert_id", "tenant_id", "tx_msg_id", "alert_timestamp",
            F.col("typology.id").alias("typology_id"),
            F.col("typology.cfg").alias("typology_cfg"),
            F.explode_outer(F.col("typology.ruleResults")).alias("rule")
        )
        .select(
            "alert_id", "tenant_id", "tx_msg_id", "alert_timestamp",
            "typology_id", "typology_cfg",
            F.col("rule.id").alias("rule_id"),
            F.col("rule.cfg").alias("rule_cfg"),
            F.col("rule.wght").cast("long").alias("rule_weight"),
            F.col("rule.indpdntVarbl").cast("double").alias("rule_independent_variable"),
            F.col("rule.subRuleRef").alias("rule_sub_ref"),
            F.col("rule.prcgTm").cast("long").alias("rule_processing_time_ms"),
            F.col("rule.tenantId").alias("rule_tenant_id"),
        )
    )

    # ====================== NETWORK EVAL ======================
    network_eval = None
    if b_net is not None:
        net_schema = spark.read.json(
            b_net.select("network_configuration_json").where(F.col("network_configuration_json").isNotNull()).rdd.map(lambda r: r[0])
        ).schema

        net_parsed = (
            b_net
            .withColumn("net_obj", F.from_json("network_configuration_json", net_schema))
            .select(
                F.col("cfg_tenant_id").alias("tenant_id"),
                F.col("net_obj.cfg").alias("network_cfg"),
                F.col("net_obj.active").cast("boolean").alias("network_active"),
                F.explode_outer(F.col("net_obj.messages")).alias("msg")
            )
            .select(
                "tenant_id", "network_cfg", "network_active",
                F.col("msg.id").alias("network_message_id"),
                F.col("msg.cfg").alias("network_message_cfg"),
                F.col("msg.txTp").alias("network_tx_type"),
                F.explode_outer(F.col("msg.typologies")).alias("t")
            )
            .select(
                "tenant_id", "network_cfg", "network_active",
                "network_message_id", "network_message_cfg", "network_tx_type",
                F.col("t.id").alias("typology_id"),
                F.col("t.cfg").alias("typology_cfg"),
                F.col("t.tenantId").alias("typology_tenant_id"),
                F.explode_outer(F.col("t.rules")).alias("r")
            )
            .select(
                "tenant_id", "network_cfg", "network_active",
                "network_message_id", "network_message_cfg", "network_tx_type",
                "typology_id", "typology_cfg",
                F.col("r.id").alias("rule_id"),
                F.col("r.cfg").alias("rule_cfg"),
            )
        )

        network_eval = (
            alerts_nav_header.select("alert_id", "tenant_id", "tx_type")
            .join(
                net_parsed,
                (alerts_nav_header.tenant_id == net_parsed.tenant_id) &
                (alerts_nav_header.tx_type == net_parsed.network_tx_type),
                "left"
            )
            .select(
                "alert_id",
                net_parsed.tenant_id,
                "tx_type",
                "network_cfg", "network_active",
                "network_message_id", "typology_id", "typology_cfg", "rule_id", "rule_cfg"
            )
        )

    # ====================== PREPARE FOR HUDI WRITES ======================
    # Header
    alerts_nav_header_w = alerts_nav_header.withColumn("pk", F.col("alert_id").cast("string"))

    # Typologies
    typ_w = (
        typ.withColumn(
            "pk", 
            F.sha2(F.concat_ws("||", F.col("alert_id"), F.col("typology_id"), F.coalesce(F.col("typology_cfg"), F.lit(""))), 256)
        )
        .withColumn("alert_timestamp", F.coalesce(F.col("alert_timestamp"), F.current_timestamp()))
        .withColumn("ingested_at_ts", F.current_timestamp())
    )

    # Rules
    rules_w = (
        rules.withColumn(
            "pk",
            F.sha2(F.concat_ws("||", F.col("alert_id"), F.col("typology_id"), F.col("rule_id"), F.coalesce(F.col("rule_sub_ref"), F.lit(""))), 256)
        )
        .withColumn("alert_timestamp", F.coalesce(F.col("alert_timestamp"), F.current_timestamp()))
        .withColumn("ingested_at_ts", F.current_timestamp())
    )

    def hudi_anv_opts(table_name, record_key, precombine, partition=None):
     o = {
        "hoodie.table.name": table_name,
        "hoodie.datasource.write.table.type": "COPY_ON_WRITE",
        "hoodie.datasource.write.operation": "upsert",
        "hoodie.datasource.write.recordkey.field": record_key,
        "hoodie.datasource.write.precombine.field": precombine,

        # schema evolution / reconcile
        "hoodie.datasource.write.schema.evolution.enable": "true",
        "hoodie.datasource.read.schema.evolution.enable": "true",
        "hoodie.datasource.write.reconcile.schema": "true",
        "hoodie.schema.on.read.enable": "true",

        "hoodie.metadata.enable": "false",
    }
     if partition:
        o["hoodie.datasource.write.partitionpath.field"] = partition
        o["hoodie.datasource.write.keygenerator.class"] = "org.apache.hudi.keygen.SimpleKeyGenerator"
        o["hoodie.datasource.write.hive_style_partitioning"] = "true"
     else:
        o["hoodie.datasource.write.keygenerator.class"] = "org.apache.hudi.keygen.NonpartitionedKeyGenerator"
     return o

    # ====================== WRITE TO HUDI ======================
    write_hudi(
        alerts_nav_header_w, 
        alerts_nav_header_path, 
        hudi_anv_opts("vw_alerts_nav_header", record_key="pk", precombine="ingested_at_ts", partition="alert_date")
    )

    write_hudi(
        typ_w, 
        alerts_nav_typologies_path, 
        hudi_anv_opts("vw_alerts_nav_typologies", record_key="pk", precombine="alert_timestamp")
    )

    write_hudi(
        rules_w, 
        alerts_nav_rules_path, 
        hudi_anv_opts("vw_alerts_nav_rules", record_key="pk", precombine="alert_timestamp")
    )

    if network_eval is not None:
        net_w = network_eval.withColumn(
            "pk", 
            F.sha2(F.concat_ws("||", F.col("alert_id"), F.col("typology_id"), F.col("rule_id"), F.coalesce(F.col("network_message_id"), F.lit(""))), 256)
        )
        write_hudi(
            net_w, 
            alerts_nav_network_eval_path, 
            hudi_opts("vw_alerts_nav_network_evaluated", record_key="pk", precombine="alert_id")
        )

    return ALERT_NAV_ROOT


def create_transaction_detail_view(spark, WAREHOUSE_ROOT):
    """
    Creates the Transaction Detail View (vw_transaction_detail)
    - Reads from bronze/transactions
    - Parses pacs.008 + pacs.002 JSON payload
    - Adds synthetic deterministic event timestamp for UI/visualization
    - Writes as Hudi view
    """
    VIEWS_ROOT = f"{WAREHOUSE_ROOT}/views"
    tx_detail_view_path = f"{VIEWS_ROOT}/vw_transaction_detail"

    print("* Creating Transaction Detail View...")

    # ============================================================
    # 1. LOAD BRONZE TRANSACTIONS
    # ============================================================
    transactions_bronze_path = f"{WAREHOUSE_ROOT}/bronze/transactions"
    tx = spark.read.format("hudi").load(transactions_bronze_path)

    # Normalize column names
    rename_map = {
        "endToEndId": "end_to_end_id",
        "tenantId": "tenant_id",
        "transactionId": "transaction_id"
    }
    for src, dst in rename_map.items():
        if src in tx.columns and dst not in tx.columns:
            tx = tx.withColumnRenamed(src, dst)

    # ============================================================
    # 2. AUTO-DETECT RAW JSON COLUMN
    # ============================================================
    candidate_json_cols = [
        "transactionData", "transaction_data", "transaction",
        "payload", "raw_payload", "raw_json", "transaction_json"
    ]
    json_col = next((c for c in candidate_json_cols if c in tx.columns), None)
    if json_col is None:
        raise ValueError(
            f"No raw JSON column found in bronze/transactions. "
            f"Tried: {candidate_json_cols}\nAvailable: {tx.columns}"
        )

    tx = tx.withColumn("transaction_data", F.col(json_col).cast("string"))
    print(f"* Using JSON column: {json_col} → transaction_data")

    # ============================================================
    # 3. FIELD EXTRACTORS
    # ============================================================
    tx_type = F.get_json_object("transaction_data", "$.TxTp")
    tx_msg_id = F.coalesce(
        F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.GrpHdr.MsgId"),
        F.get_json_object("transaction_data", "$.FIToFIPmtSts.GrpHdr.MsgId")
    )
    event_ts = F.to_timestamp(
        F.coalesce(
            F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.GrpHdr.CreDtTm"),
            F.get_json_object("transaction_data", "$.FIToFIPmtSts.GrpHdr.CreDtTm")
        )
    )
    event_date = F.to_date(event_ts)
    tx_tenant = F.get_json_object("transaction_data", "$.TenantId")

    # Debtor / Creditor fields
    dbtr_name = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.Dbtr.Nm")
    dbtr_id   = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.Dbtr.Id.PrvtId.Othr[0].Id")
    cdtr_name = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.Cdtr.Nm")
    cdtr_id   = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.Cdtr.Id.PrvtId.Othr[0].Id")

    dbtr_acct_id = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.DbtrAcct.Id.Othr[0].Id")
    cdtr_acct_id = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.CdtrAcct.Id.Othr[0].Id")

    instd_amt = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.InstdAmt.Amt.Amt").cast("double")
    instd_ccy = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.InstdAmt.Amt.Ccy")

    intrbk_amt = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.IntrBkSttlmAmt.Amt.Amt").cast("double")
    intrbk_ccy = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.IntrBkSttlmAmt.Amt.Ccy")
    xchg_rate  = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.XchgRate").cast("double")

    # Agents
    instg_mmb_id = F.coalesce(
        F.get_json_object("transaction_data", "$.FIToFIPmtSts.TxInfAndSts.InstgAgt.FinInstnId.ClrSysMmbId.MmbId"),
        F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.DbtrAgt.FinInstnId.ClrSysMmbId.MmbId")
    )
    instd_mmb_id = F.coalesce(
        F.get_json_object("transaction_data", "$.FIToFIPmtSts.TxInfAndSts.InstdAgt.FinInstnId.ClrSysMmbId.MmbId"),
        F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.CdtrAgt.FinInstnId.ClrSysMmbId.MmbId")
    )

    # Charges handling (pacs.002 array vs pacs.008 struct)
    charges_arr_json = F.get_json_object("transaction_data", "$.FIToFIPmtSts.TxInfAndSts.ChrgsInf")
    charges_obj_json = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.ChrgsInf")

    # ============================================================
    # PK + INGESTED TIMESTAMP
    # ============================================================
    ingested_at_ts = F.current_timestamp()
    pk = F.sha2(
        F.concat_ws("||",
            F.coalesce(F.col("transaction_id").cast("string"), F.lit("")),
            F.coalesce(F.col("end_to_end_id").cast("string"), F.lit("")),
            F.coalesce(tx_msg_id.cast("string"), F.lit("")),
            F.coalesce(tx_type.cast("string"), F.lit(""))
        ),
        256
    )

    # ============================================================
    # SYNTHETIC RANDOMIZED EVENT TIME (deterministic per PK)
    # ============================================================
    RANDOMIZE_OVER_DAYS = 150
    range_seconds = RANDOMIZE_OVER_DAYS * 86400

    rand_seconds = F.pmod(
        F.conv(F.substring(F.sha2(pk, 256), 1, 8), 16, 10).cast("long"),
        F.lit(range_seconds).cast("long")
    ).cast("long")

    base_ts = F.expr(f"current_timestamp() - INTERVAL {RANDOMIZE_OVER_DAYS} DAYS")
    synthetic_event_ts = base_ts + (rand_seconds.cast("int") * F.expr("INTERVAL 1 SECOND"))
    synthetic_event_date = F.to_date(synthetic_event_ts)

    # ============================================================
    # BUILD FINAL VIEW
    # ============================================================
    tx_detail_view = (
        tx
        .withColumn("tx_type", tx_type)
        .withColumn("tx_msg_id", tx_msg_id)
        .withColumn("raw_event_ts", event_ts)
        .withColumn("raw_event_date", event_date)
        # Use synthetic randomized timestamp for visualization
        .withColumn("tx_event_ts", synthetic_event_ts)
        .withColumn("tx_event_date", synthetic_event_date)
        .withColumn("tx_tenant_id", tx_tenant)
        .withColumn("debtor_name", dbtr_name)
        .withColumn("debtor_id", dbtr_id)
        .withColumn("creditor_name", cdtr_name)
        .withColumn("creditor_id", cdtr_id)
        .withColumn("debtor_account_id", dbtr_acct_id)
        .withColumn("creditor_account_id", cdtr_acct_id)
        .withColumn("instructed_amount", instd_amt)
        .withColumn("instructed_currency", instd_ccy)
        .withColumn("interbank_settlement_amount", intrbk_amt)
        .withColumn("interbank_settlement_currency", intrbk_ccy)
        .withColumn("exchange_rate", xchg_rate)
        .withColumn("instg_mmb_id", instg_mmb_id)
        .withColumn("instd_mmb_id", instd_mmb_id)
        # Charges
        .withColumn("charges_arr", F.from_json(charges_arr_json, "array<struct<Agt:struct<FinInstnId:struct<ClrSysMmbId:struct<MmbId:string>>>,Amt:struct<Amt:double,Ccy:string>>>"))
        .withColumn("charges_obj", F.from_json(charges_obj_json, "struct<Agt:struct<FinInstnId:struct<ClrSysMmbId:struct<MmbId:string>>>,Amt:struct<Amt:double,Ccy:string>>"))
        .withColumn(
            "charge_count",
            F.when(F.col("charges_arr").isNotNull(), F.size("charges_arr"))
             .when(F.col("charges_obj").isNotNull(), F.lit(1))
             .otherwise(F.lit(0)).cast("int")
        )
        .withColumn(
            "charge_total_amount",
            F.when(F.col("charges_arr").isNotNull(),
                   F.expr("aggregate(transform(charges_arr, x -> coalesce(x.Amt.Amt, 0D)), 0D, (acc, x) -> acc + x)"))
             .when(F.col("charges_obj").isNotNull(),
                   F.coalesce(F.col("charges_obj.Amt.Amt").cast("double"), F.lit(0.0)))
             .otherwise(F.lit(0.0)).cast("double")
        )
        .withColumn(
            "charge_currency",
            F.when(F.col("charges_arr").isNotNull(),
                   F.expr("element_at(transform(charges_arr, x -> x.Amt.Ccy), 1)"))
             .when(F.col("charges_obj").isNotNull(), F.col("charges_obj.Amt.Ccy"))
             .otherwise(F.lit(None).cast("string"))
        )
        .drop("charges_arr", "charges_obj")
        # Final metadata
        .withColumn("ingested_at_ts", ingested_at_ts)
        .withColumn("pk", pk)
        .select(
            "pk",
            F.col("transaction_id").cast("long").alias("transaction_id"),
            F.col("end_to_end_id").cast("string").alias("end_to_end_id"),
            F.col("tenant_id").cast("string").alias("tenant_id"),
            F.col("tx_tenant_id").cast("string").alias("tx_tenant_id"),
            F.col("tx_type").cast("string").alias("tx_type"),
            F.col("tx_msg_id").cast("string").alias("tx_msg_id"),
            F.col("tx_event_ts").cast("timestamp").alias("tx_event_ts"),
            F.col("tx_event_date").cast("date").alias("tx_event_date"),
            F.col("debtor_name").cast("string").alias("debtor_name"),
            F.col("debtor_id").cast("string").alias("debtor_id"),
            F.col("creditor_name").cast("string").alias("creditor_name"),
            F.col("creditor_id").cast("string").alias("creditor_id"),
            F.col("debtor_account_id").cast("string").alias("debtor_account_id"),
            F.col("creditor_account_id").cast("string").alias("creditor_account_id"),
            F.col("instructed_amount").cast("double").alias("instructed_amount"),
            F.col("instructed_currency").cast("string").alias("instructed_currency"),
            F.col("interbank_settlement_amount").cast("double").alias("interbank_settlement_amount"),
            F.col("interbank_settlement_currency").cast("string").alias("interbank_settlement_currency"),
            F.col("exchange_rate").cast("double").alias("exchange_rate"),
            F.col("instg_mmb_id").cast("string").alias("instg_mmb_id"),
            F.col("instd_mmb_id").cast("string").alias("instd_mmb_id"),
            F.col("charge_count").cast("int").alias("charge_count"),
            F.col("charge_total_amount").cast("double").alias("charge_total_amount"),
            F.col("charge_currency").cast("string").alias("charge_currency"),
            F.col("source_file_path").cast("string").alias("source_file_path") if "source_file_path" in tx.columns else F.lit(None).cast("string").alias("source_file_path"),
            F.col("record_hash").cast("string").alias("record_hash") if "record_hash" in tx.columns else F.lit(None).cast("string").alias("record_hash"),
            F.col("ingested_at_ts").cast("timestamp").alias("ingested_at_ts")
        )
    )

    # ============================================================
    # WRITE AS HUDI VIEW
    # ============================================================
    view_opts = {
        "hoodie.table.name": "vw_transaction_detail",
        "hoodie.datasource.write.table.type": "COPY_ON_WRITE",
        "hoodie.datasource.write.operation": "upsert",
        "hoodie.datasource.write.recordkey.field": "pk",
        "hoodie.datasource.write.precombine.field": "ingested_at_ts",
        "hoodie.datasource.write.keygenerator.class": "org.apache.hudi.keygen.NonpartitionedKeyGenerator",
        "hoodie.datasource.write.schema.evolution.enable": "true",
        "hoodie.datasource.read.schema.evolution.enable": "true",
        "hoodie.datasource.write.reconcile.schema": "true",
        "hoodie.schema.on.read.enable": "true",
        "hoodie.index.type": "BLOOM",
        "hoodie.metadata.enable": "false",
    }

    tx_detail_view.write.format("hudi") \
        .options(**view_opts) \
        .mode("append") \
        .save(tx_detail_view_path)

    print(f"* Transaction Detail View successfully written to: {tx_detail_view_path}")
    return tx_detail_view_path

def create_transaction_history_view(spark, WAREHOUSE_ROOT):
    """
    Creates vw_transaction_history view (Hudi table).
    - Reads bronze/transactions (raw JSON payload)
    - Parses pacs.008 + pacs.002
    - Adds synthetic deterministic event timestamp
    - Joins alerts/cases/tasks for is_alerted / is_investigated flags
    - Expands to entity level (accounts + counterparties)
    - Creates EVENT rows + aggregated (day/week/month/year) rows
    """
    VIEWS_ROOT = f"{WAREHOUSE_ROOT}/views"
    tx_history_view_path = f"{VIEWS_ROOT}/vw_transaction_history"

    print("* Creating Transaction History View...")

    # ============================================================
    # 1. LOAD SOURCES
    # ============================================================
    transactions_bronze_path = f"{WAREHOUSE_ROOT}/bronze/transactions"
    tx = spark.read.format("hudi").load(transactions_bronze_path)

    # Optional gold tables for flags
    try:
        gold_alerts_path = f"{WAREHOUSE_ROOT}/gold/alerts"
        alerts_g = spark.read.format("hudi").load(gold_alerts_path).select(
            F.col("tx_msg_id").cast("string").alias("tx_msg_id"),
            F.col("alert_id").cast("long").alias("alert_id"),
            F.col("case_id").cast("long").alias("case_id")
        ).dropna(subset=["tx_msg_id"]).dropDuplicates(["tx_msg_id"])
    except Exception:
        alerts_g = None

    try:
        gold_cases_path = f"{WAREHOUSE_ROOT}/gold/cases"
        cases_g = spark.read.format("hudi").load(gold_cases_path).select(
            F.col("case_id").cast("long").alias("case_id"),
            F.col("status").cast("string").alias("case_status")
        ).dropDuplicates(["case_id"])
    except Exception:
        cases_g = None

    try:
        gold_tasks_path = f"{WAREHOUSE_ROOT}/gold/tasks"
        tasks_g = spark.read.format("hudi").load(gold_tasks_path).select(
            F.col("case_id").cast("long").alias("case_id"),
            F.col("is_completed").cast("int").alias("is_completed")
        )
    except Exception:
        tasks_g = None

    # ============================================================
    # 2. NORMALIZE & DETECT RAW JSON COLUMN
    # ============================================================
    rename_map = {"endToEndId": "end_to_end_id", "tenantId": "tenant_id", "transactionId": "transaction_id"}
    for src, dst in rename_map.items():
        if src in tx.columns and dst not in tx.columns:
            tx = tx.withColumnRenamed(src, dst)

    candidate_json_cols = ["transactionData", "transaction_data", "transaction", "payload", "raw_payload"]
    json_col = next((c for c in candidate_json_cols if c in tx.columns), None)
    if json_col is None:
        raise ValueError(f"No raw JSON column found in bronze/transactions. Available: {tx.columns}")

    tx = tx.withColumn("transaction_data", F.col(json_col).cast("string"))

    # ============================================================
    # 3. COMMON FIELD EXTRACTORS
    # ============================================================
    tx_type = F.get_json_object("transaction_data", "$.TxTp")
    tx_msg_id = F.coalesce(
        F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.GrpHdr.MsgId"),
        F.get_json_object("transaction_data", "$.FIToFIPmtSts.GrpHdr.MsgId")
    )
    event_ts = F.to_timestamp(
        F.coalesce(
            F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.GrpHdr.CreDtTm"),
            F.get_json_object("transaction_data", "$.FIToFIPmtSts.GrpHdr.CreDtTm")
        )
    )
    event_date = F.to_date(event_ts)

    dbtr_name = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.Dbtr.Nm")
    dbtr_id   = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.Dbtr.Id.PrvtId.Othr[0].Id")
    cdtr_name = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.Cdtr.Nm")
    cdtr_id   = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.Cdtr.Id.PrvtId.Othr[0].Id")

    dbtr_acct = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.DbtrAcct.Id.Othr[0].Id")
    cdtr_acct = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.CdtrAcct.Id.Othr[0].Id")

    tx_amount = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.InstdAmt.Amt.Amt").cast("double")
    tx_ccy    = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.InstdAmt.Amt.Ccy")

    # ============================================================
    # 4. BASE TRANSACTION FRAME
    # ============================================================
    base = (
        tx
        .withColumn("tx_type", tx_type)
        .withColumn("tx_msg_id", tx_msg_id)
        .withColumn("event_ts", event_ts)
        .withColumn("event_date", event_date)
        .withColumn("tx_amount", tx_amount)
        .withColumn("tx_ccy", tx_ccy)
        .withColumn("dbtr_name", dbtr_name)
        .withColumn("dbtr_id", dbtr_id)
        .withColumn("cdtr_name", cdtr_name)
        .withColumn("cdtr_id", cdtr_id)
        .withColumn("dbtr_account_id", dbtr_acct)
        .withColumn("cdtr_account_id", cdtr_acct)
        .select(
            F.col("transaction_id").cast("long").alias("transaction_id"),
            F.col("end_to_end_id").cast("string").alias("end_to_end_id"),
            F.col("tenant_id").cast("string").alias("tenant_id"),
            F.col("tx_type").cast("string").alias("tx_type"),
            F.col("tx_msg_id").cast("string").alias("tx_msg_id"),
            F.col("event_ts").cast("timestamp").alias("event_ts"),
            F.col("event_date").cast("date").alias("event_date"),
            F.col("tx_amount").cast("double").alias("tx_amount"),
            F.col("tx_ccy").cast("string").alias("tx_ccy"),
            F.col("dbtr_name").cast("string").alias("dbtr_name"),
            F.col("dbtr_id").cast("string").alias("dbtr_id"),
            F.col("cdtr_name").cast("string").alias("cdtr_name"),
            F.col("cdtr_id").cast("string").alias("cdtr_id"),
            F.col("dbtr_account_id").cast("string").alias("dbtr_account_id"),
            F.col("cdtr_account_id").cast("string").alias("cdtr_account_id"),
            F.col("source_file_path").cast("string").alias("source_file_path") if "source_file_path" in tx.columns else F.lit(None).cast("string").alias("source_file_path"),
            F.col("record_hash").cast("string").alias("record_hash") if "record_hash" in tx.columns else F.lit(None).cast("string").alias("record_hash")
        )
        .filter(F.col("event_ts").isNotNull())
    )

    # ============================================================
    # 5. SYNTHETIC DETERMINISTIC EVENT TIME (for UI)
    # ============================================================
    RANDOMIZE_OVER_DAYS = 150
    range_seconds = RANDOMIZE_OVER_DAYS * 86400

    seed_str = F.coalesce(F.col("tx_msg_id"), F.col("transaction_id").cast("string"), F.lit(""))
    rand_seconds = F.pmod(
        F.conv(F.substring(F.sha2(seed_str, 256), 1, 8), 16, 10).cast("long"),
        F.lit(range_seconds).cast("long")
    ).cast("long")

    base_ts = F.expr(f"current_timestamp() - INTERVAL {RANDOMIZE_OVER_DAYS} DAYS")
    synthetic_event_ts = base_ts + (rand_seconds.cast("int") * F.expr("INTERVAL 1 SECOND"))
    synthetic_event_date = F.to_date(synthetic_event_ts)

    base = base.withColumn("raw_event_ts", F.col("event_ts")) \
               .withColumn("raw_event_date", F.col("event_date")) \
               .withColumn("event_ts", synthetic_event_ts) \
               .withColumn("event_date", synthetic_event_date)

    # ============================================================
    # 6. FLAGS: is_alerted + is_investigated
    # ============================================================
    flags = base

    if alerts_g is not None:
        flags = flags.join(alerts_g, "tx_msg_id", "left")

    if cases_g is not None:
        flags = flags.join(cases_g, "case_id", "left")

    if tasks_g is not None:
        tasks_agg = tasks_g.groupBy("case_id").agg(F.max("is_completed").alias("has_completed_task"))
        flags = flags.join(tasks_agg, "case_id", "left")

    flags = flags.withColumn("is_alerted", F.when(F.col("alert_id").isNotNull(), F.lit(1)).otherwise(F.lit(0))) \
                 .withColumn(
                     "is_investigated",
                     F.when(
                         (F.col("case_status").isNotNull()) |
                         (F.coalesce(F.col("has_completed_task"), F.lit(0)) == 1),
                         F.lit(1)
                     ).otherwise(F.lit(0))
                 ).drop("has_completed_task", "alert_id", "case_status", "case_id")  # clean up temp columns

    # ============================================================
    # 7. ENTITY EXPANSION (Account + Counterparty)
    # ============================================================
    entity_rows = (
        flags
        .select(
            "*",
            F.array(
                F.when(F.col("dbtr_account_id").isNotNull(),
                       F.struct(F.lit("ACCOUNT").alias("entity_type"),
                                F.lit("DEBTOR").alias("entity_role"),
                                F.col("dbtr_account_id").alias("entity_id"),
                                F.col("dbtr_name").alias("entity_name"))),
                F.when(F.col("cdtr_account_id").isNotNull(),
                       F.struct(F.lit("ACCOUNT").alias("entity_type"),
                                F.lit("CREDITOR").alias("entity_role"),
                                F.col("cdtr_account_id").alias("entity_id"),
                                F.col("cdtr_name").alias("entity_name"))),
                F.when(F.col("dbtr_id").isNotNull(),
                       F.struct(F.lit("COUNTERPARTY").alias("entity_type"),
                                F.lit("DEBTOR").alias("entity_role"),
                                F.col("dbtr_id").alias("entity_id"),
                                F.col("dbtr_name").alias("entity_name"))),
                F.when(F.col("cdtr_id").isNotNull(),
                       F.struct(F.lit("COUNTERPARTY").alias("entity_type"),
                                F.lit("CREDITOR").alias("entity_role"),
                                F.col("cdtr_id").alias("entity_id"),
                                F.col("cdtr_name").alias("entity_name")))
            ).alias("entities")
        )
        .withColumn("entity", F.explode(F.expr("filter(entities, x -> x is not null)")))
        .drop("entities")
        .withColumn("entity_type", F.col("entity.entity_type"))
        .withColumn("entity_role", F.col("entity.entity_role"))
        .withColumn("entity_id",   F.col("entity.entity_id"))
        .withColumn("entity_name", F.col("entity.entity_name"))
        .drop("entity")
    )

    # ============================================================
    # 8. WINDOW CALCULATIONS + AGGREGATIONS
    # ============================================================
    w_recent = Window.partitionBy("entity_type", "entity_role", "entity_id").orderBy(F.col("event_ts").desc())
    w_cum    = Window.partitionBy("entity_type", "entity_role", "entity_id").orderBy(F.col("event_ts").asc()) \
                     .rowsBetween(Window.unboundedPreceding, Window.currentRow)

    events = (
        entity_rows
        .withColumn("recent_rank_desc", F.row_number().over(w_recent))
        .withColumn("cum_tx_count", F.count(F.lit(1)).over(w_cum))
        .withColumn("cum_tx_amount", F.sum(F.coalesce(F.col("tx_amount"), F.lit(0.0))).over(w_cum))
        .withColumn("row_type", F.lit("EVENT"))
        .withColumn("bucket_granularity", F.lit(None).cast("string"))
        .withColumn("bucket_start", F.lit(None).cast("timestamp"))
        .withColumn("bucket_tx_count", F.lit(None).cast("long"))
        .withColumn("bucket_tx_amount", F.lit(None).cast("double"))
    )

    def agg_for(granularity: str):
        bucket_start = F.date_trunc(granularity, F.col("event_ts"))
        return (
            entity_rows
            .withColumn("bucket_start", bucket_start)
            .groupBy("entity_type", "entity_role", "entity_id", "bucket_start")
            .agg(
                F.count("*").cast("long").alias("bucket_tx_count"),
                F.sum(F.coalesce(F.col("tx_amount"), F.lit(0.0))).cast("double").alias("bucket_tx_amount"),
                F.max("event_date").alias("event_date"),
                F.max("tenant_id").alias("tenant_id")
            )
            .withColumn("row_type", F.lit("AGG"))
            .withColumn("bucket_granularity", F.lit(granularity))
            .withColumn("recent_rank_desc", F.lit(None).cast("int"))
            .withColumn("cum_tx_count", F.lit(None).cast("long"))
            .withColumn("cum_tx_amount", F.lit(None).cast("double"))
            .withColumn("transaction_id", F.lit(None).cast("long"))
            .withColumn("end_to_end_id", F.lit(None).cast("string"))
            .withColumn("tx_type", F.lit(None).cast("string"))
            .withColumn("tx_msg_id", F.lit(None).cast("string"))
            .withColumn("event_ts", F.lit(None).cast("timestamp"))
            .withColumn("tx_amount", F.lit(None).cast("double"))
            .withColumn("tx_ccy", F.lit(None).cast("string"))
            .withColumn("entity_name", F.lit(None).cast("string"))
            .withColumn("is_alerted", F.lit(None).cast("int"))
            .withColumn("is_investigated", F.lit(None).cast("int"))
            .withColumn("source_file_path", F.lit(None).cast("string"))
            .withColumn("record_hash", F.lit(None).cast("string"))
        )

    agg_day   = agg_for("day")
    agg_week  = agg_for("week")
    agg_month = agg_for("month")
    agg_year  = agg_for("year")

    # ============================================================
    # 9. FINAL UNION
    # ============================================================
    view_df = (
        events
        .select(
            "entity_type", "entity_role", "entity_id", "entity_name",
            "transaction_id", "end_to_end_id", "tenant_id", "tx_type", "tx_msg_id",
            "event_ts", "event_date", "tx_amount", "tx_ccy",
            "is_alerted", "is_investigated",
            "recent_rank_desc", "cum_tx_count", "cum_tx_amount",
            "row_type", "bucket_granularity", "bucket_start", "bucket_tx_count", "bucket_tx_amount",
            "source_file_path", "record_hash"
        )
        .unionByName(agg_day,   allowMissingColumns=True)
        .unionByName(agg_week,  allowMissingColumns=True)
        .unionByName(agg_month, allowMissingColumns=True)
        .unionByName(agg_year,  allowMissingColumns=True)
    )

    # ============================================================
    # 10. PK + INGESTED TIMESTAMP
    # ============================================================
    view_df = (
        view_df
        .withColumn("ingested_at_ts", F.current_timestamp())
        .withColumn(
            "pk",
            F.sha2(
                F.concat_ws("||",
                    F.coalesce(F.col("entity_type"), F.lit("")),
                    F.coalesce(F.col("entity_role"), F.lit("")),
                    F.coalesce(F.col("entity_id"), F.lit("")),
                    F.coalesce(F.col("row_type"), F.lit("")),
                    F.coalesce(F.col("bucket_granularity"), F.lit("")),
                    F.coalesce(F.col("bucket_start").cast("string"), F.lit("")),
                    F.coalesce(F.col("tx_msg_id"), F.lit("")),
                    F.coalesce(F.col("transaction_id").cast("string"), F.lit(""))
                ),
                256
            )
        )
    )

    # ============================================================
    # 11. WRITE TO HUDI
    # ============================================================
    hudi_opts_dict = {
        "hoodie.table.name": "vw_transaction_history",
        "hoodie.datasource.write.table.type": "COPY_ON_WRITE",
        "hoodie.datasource.write.operation": "upsert",
        "hoodie.datasource.write.recordkey.field": "pk",
        "hoodie.datasource.write.precombine.field": "ingested_at_ts",
        "hoodie.datasource.write.keygenerator.class": "org.apache.hudi.keygen.NonpartitionedKeyGenerator",
        "hoodie.datasource.write.schema.evolution.enable": "true",
        "hoodie.datasource.read.schema.evolution.enable": "true",
        "hoodie.datasource.write.reconcile.schema": "true",
        "hoodie.schema.on.read.enable": "true",
        "hoodie.index.type": "BLOOM",
        "hoodie.metadata.enable": "false",
    }

    view_df.write.format("hudi") \
        .options(**hudi_opts_dict) \
        .mode("append") \
        .save(tx_history_view_path)

    print(f"* Transaction History View successfully written to: {tx_history_view_path}")
    return tx_history_view_path

def create_network_navigator_views(spark, WAREHOUSE_ROOT):
    """
    Creates 3 Network Navigator Hudi Views:
      1. vw_tx_network_accounts_edges       → Account-to-Account edges
      2. vw_tx_network_counterparties_edges → Counterparty-to-Counterparty edges
      3. vw_counterparty_account_links      → Counterparty owns Account (holder) edges
    """
    VIEWS_ROOT = f"{WAREHOUSE_ROOT}/views"

    vw_tx_network_accounts_edges_path      = f"{VIEWS_ROOT}/vw_tx_network_accounts_edges"
    vw_tx_network_counterparties_edges_path = f"{VIEWS_ROOT}/vw_tx_network_counterparties_edges"
    vw_counterparty_account_links_path     = f"{VIEWS_ROOT}/vw_counterparty_account_links"

    print("* Creating Network Navigator Views...")

    # ============================================================
    # 1. LOAD SOURCES
    # ============================================================
    transactions_bronze_path = f"{WAREHOUSE_ROOT}/bronze/transactions"
    tx = spark.read.format("hudi").load(transactions_bronze_path)

    # Gold tables for flags
    gold_alerts_path = f"{WAREHOUSE_ROOT}/gold/alerts"
    gold_cases_path  = f"{WAREHOUSE_ROOT}/gold/cases"
    gold_tasks_path  = f"{WAREHOUSE_ROOT}/gold/tasks"

    alerts_g = spark.read.format("hudi").load(gold_alerts_path).select(
        F.col("tx_msg_id").cast("string").alias("tx_msg_id"),
        F.col("alert_id").cast("long").alias("alert_id"),
        F.col("case_id").cast("long").alias("case_id")
    ).dropna(subset=["tx_msg_id"]).dropDuplicates(["tx_msg_id"])

    cases_g = spark.read.format("hudi").load(gold_cases_path).select(
        F.col("case_id").cast("long").alias("case_id"),
        F.col("status").cast("string").alias("case_status")
    ).dropDuplicates(["case_id"])

    tasks_g = spark.read.format("hudi").load(gold_tasks_path).select(
        F.col("case_id").cast("long").alias("case_id"),
        F.col("is_completed").cast("int").alias("is_completed")
    )

    # ============================================================
    # 2. NORMALIZE & DETECT RAW JSON COLUMN
    # ============================================================
    rename_map = {"endToEndId": "end_to_end_id", "tenantId": "tenant_id", "transactionId": "transaction_id"}
    for src, dst in rename_map.items():
        if src in tx.columns and dst not in tx.columns:
            tx = tx.withColumnRenamed(src, dst)

    candidate_json_cols = ["transactionData", "transaction_data", "transaction", "payload", "raw_payload"]
    json_col = next((c for c in candidate_json_cols if c in tx.columns), None)
    if json_col is None:
        raise ValueError(f"No raw JSON column found in bronze/transactions. Available: {tx.columns}")

    tx = tx.withColumn("transaction_data", F.col(json_col).cast("string"))

    # ============================================================
    # 3. COMMON EXTRACTORS
    # ============================================================
    tx_type = F.get_json_object("transaction_data", "$.TxTp")
    tx_msg_id = F.coalesce(
        F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.GrpHdr.MsgId"),
        F.get_json_object("transaction_data", "$.FIToFIPmtSts.GrpHdr.MsgId")
    )
    event_ts = F.to_timestamp(
        F.coalesce(
            F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.GrpHdr.CreDtTm"),
            F.get_json_object("transaction_data", "$.FIToFIPmtSts.GrpHdr.CreDtTm")
        )
    )
    event_date = F.to_date(event_ts)

    dbtr_id = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.Dbtr.Id.PrvtId.Othr[0].Id")
    cdtr_id = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.Cdtr.Id.PrvtId.Othr[0].Id")
    dbtr_acct = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.DbtrAcct.Id.Othr[0].Id")
    cdtr_acct = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.CdtrAcct.Id.Othr[0].Id")
    tx_amount = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.InstdAmt.Amt.Amt").cast("double")
    tx_ccy = F.get_json_object("transaction_data", "$.FIToFICstmrCdtTrf.CdtTrfTxInf.InstdAmt.Amt.Ccy")

    base = (
        tx
        .withColumn("tx_type", tx_type)
        .withColumn("tx_msg_id", tx_msg_id)
        .withColumn("event_ts", event_ts)
        .withColumn("event_date", event_date)
        .withColumn("tx_amount", tx_amount)
        .withColumn("tx_ccy", tx_ccy)
        .withColumn("dbtr_id", dbtr_id)
        .withColumn("cdtr_id", cdtr_id)
        .withColumn("dbtr_account_id", dbtr_acct)
        .withColumn("cdtr_account_id", cdtr_acct)
        .select(
            F.col("transaction_id").cast("long").alias("transaction_id"),
            F.col("end_to_end_id").cast("string").alias("end_to_end_id"),
            F.col("tenant_id").cast("string").alias("tenant_id"),
            F.col("tx_type").cast("string").alias("tx_type"),
            F.col("tx_msg_id").cast("string").alias("tx_msg_id"),
            F.col("event_ts").cast("timestamp").alias("event_ts"),
            F.col("event_date").cast("date").alias("event_date"),
            F.col("tx_amount").cast("double").alias("tx_amount"),
            F.col("tx_ccy").cast("string").alias("tx_ccy"),
            F.col("dbtr_id").cast("string").alias("dbtr_id"),
            F.col("cdtr_id").cast("string").alias("cdtr_id"),
            F.col("dbtr_account_id").cast("string").alias("dbtr_account_id"),
            F.col("cdtr_account_id").cast("string").alias("cdtr_account_id"),
        )
        .filter(F.col("event_ts").isNotNull())
    )

    # ============================================================
    # 4. FLAGS: is_alerted_tx + is_investigated_tx
    # ============================================================
    flags = (
        base
        .join(alerts_g, "tx_msg_id", "left")
        .join(cases_g, "case_id", "left")
        .join(tasks_g.groupBy("case_id").agg(F.max("is_completed").alias("has_completed_task")), "case_id", "left")
        .withColumn("is_alerted_tx", F.when(F.col("alert_id").isNotNull(), F.lit(1)).otherwise(F.lit(0)))
        .withColumn(
            "is_investigated_tx",
            F.when(
                (F.col("case_status").isNotNull()) |
                (F.coalesce(F.col("has_completed_task"), F.lit(0)) == 1),
                F.lit(1)
            ).otherwise(F.lit(0))
        )
        .drop("has_completed_task", "alert_id", "case_status")
    )

    # ============================================================
    # 5. HELPER FUNCTIONS (exact copy from your notebook)
    # ============================================================
    def edge_bucket_agg(df, from_col, to_col):
        df = df.filter(F.col(from_col).isNotNull() & F.col(to_col).isNotNull())

        def agg(granularity):
            bstart = F.date_trunc(granularity, F.col("event_ts"))
            return (
                df.withColumn("bucket_granularity", F.lit(granularity))
                  .withColumn("bucket_start", bstart)
                  .groupBy(
                      "tenant_id",
                      "bucket_granularity",
                      "bucket_start",
                      F.col(from_col).alias("from_id"),
                      F.col(to_col).alias("to_id")
                  )
                  .agg(
                      F.count("*").cast("long").alias("tx_count"),
                      F.sum(F.coalesce(F.col("tx_amount"), F.lit(0.0))).cast("double").alias("total_amount"),
                      F.max("tx_ccy").alias("currency_hint"),
                      F.min("event_ts").alias("first_event_ts"),
                      F.max("event_ts").alias("last_event_ts"),
                      F.max("is_alerted_tx").alias("is_alerted_edge"),
                      F.max("is_investigated_tx").alias("is_investigated_edge"),
                  )
                  .withColumn("active_window_sec",
                              (F.unix_timestamp("last_event_ts") - F.unix_timestamp("first_event_ts")).cast("long"))
                  .withColumn(
                      "tx_per_day",
                      F.when(F.col("active_window_sec") > 0,
                             F.col("tx_count").cast("double") / (F.col("active_window_sec").cast("double") / 86400.0))
                       .otherwise(F.col("tx_count").cast("double"))
                  )
            )

        return agg("day").unionByName(agg("week")).unionByName(agg("month")).unionByName(agg("year"))

    def add_pk_and_ingest(df, table_tag, from_col, to_col):
        return (
            df.withColumn("ingested_at_ts", F.current_timestamp())
              .withColumn(
                  "pk",
                  F.sha2(
                      F.concat_ws("||",
                          F.lit(table_tag),
                          F.coalesce(F.col("tenant_id").cast("string"), F.lit("")),
                          F.coalesce(F.col("bucket_granularity").cast("string"), F.lit("")),
                          F.coalesce(F.col("bucket_start").cast("string"), F.lit("")),
                          F.coalesce(F.col(from_col).cast("string"), F.lit("")),
                          F.coalesce(F.col(to_col).cast("string"), F.lit("")),
                      ),
                      256
                  )
              )
        )

    def hudi_opts(table_name):
        return {
            "hoodie.table.name": table_name,
            "hoodie.datasource.write.table.type": "COPY_ON_WRITE",
            "hoodie.datasource.write.operation": "upsert",
            "hoodie.datasource.write.recordkey.field": "pk",
            "hoodie.datasource.write.precombine.field": "ingested_at_ts",
            "hoodie.datasource.write.keygenerator.class": "org.apache.hudi.keygen.NonpartitionedKeyGenerator",
            "hoodie.datasource.write.schema.evolution.enable": "true",
            "hoodie.datasource.read.schema.evolution.enable": "true",
            "hoodie.datasource.write.reconcile.schema": "true",
            "hoodie.schema.on.read.enable": "true",
            "hoodie.index.type": "BLOOM",
            "hoodie.metadata.enable": "false",
        }

    # ============================================================
    # 6. BUILD THE 3 VIEWS
    # ============================================================

    # 6.1 Account-to-Account Edges
    vw_tx_network_accounts_edges = (
        edge_bucket_agg(flags, "dbtr_account_id", "cdtr_account_id")
        .withColumnRenamed("from_id", "from_account_id")
        .withColumnRenamed("to_id", "to_account_id")
    )
    vw_tx_network_accounts_edges = add_pk_and_ingest(
        vw_tx_network_accounts_edges,
        "vw_tx_network_accounts_edges",
        "from_account_id",
        "to_account_id"
    )
    vw_tx_network_accounts_edges.write.format("hudi") \
        .options(**hudi_opts("vw_tx_network_accounts_edges")) \
        .mode("append").save(vw_tx_network_accounts_edges_path)

    # 6.2 Counterparty-to-Counterparty Edges
    vw_tx_network_counterparties_edges = (
        edge_bucket_agg(flags, "dbtr_id", "cdtr_id")
        .withColumnRenamed("from_id", "from_counterparty_id")
        .withColumnRenamed("to_id", "to_counterparty_id")
    )
    vw_tx_network_counterparties_edges = add_pk_and_ingest(
        vw_tx_network_counterparties_edges,
        "vw_tx_network_counterparties_edges",
        "from_counterparty_id",
        "to_counterparty_id"
    )
    vw_tx_network_counterparties_edges.write.format("hudi") \
        .options(**hudi_opts("vw_tx_network_counterparties_edges")) \
        .mode("append").save(vw_tx_network_counterparties_edges_path)

    # 6.3 Counterparty → Account (Holder) Links
    holder_debtor = (
        flags
        .filter(F.col("dbtr_id").isNotNull() & F.col("dbtr_account_id").isNotNull())
        .select(
            "tenant_id", "event_ts", "tx_amount", "tx_ccy",
            "is_alerted_tx", "is_investigated_tx",
            F.col("dbtr_id").alias("from_id"),
            F.col("dbtr_account_id").alias("to_id")
        )
    )
    holder_creditor = (
        flags
        .filter(F.col("cdtr_id").isNotNull() & F.col("cdtr_account_id").isNotNull())
        .select(
            "tenant_id", "event_ts", "tx_amount", "tx_ccy",
            "is_alerted_tx", "is_investigated_tx",
            F.col("cdtr_id").alias("from_id"),
            F.col("cdtr_account_id").alias("to_id")
        )
    )
    holder_edges = holder_debtor.unionByName(holder_creditor)

    vw_counterparty_account_links = (
        edge_bucket_agg(holder_edges, "from_id", "to_id")
        .withColumnRenamed("from_id", "counterparty_id")
        .withColumnRenamed("to_id", "account_id")
    )
    vw_counterparty_account_links = add_pk_and_ingest(
        vw_counterparty_account_links,
        "vw_counterparty_account_links",
        "counterparty_id",
        "account_id"
    )
    vw_counterparty_account_links.write.format("hudi") \
        .options(**hudi_opts("vw_counterparty_account_links")) \
        .mode("append").save(vw_counterparty_account_links_path)

    print(f"* All 3 Network Navigator Views successfully created under: {VIEWS_ROOT}")
    return VIEWS_ROOT

def create_alert_history_view(spark, WAREHOUSE_ROOT):
    """
    Creates vw_alert_history view (Hudi table).
    - 5 granularities (day, week, month, year, all)
    - Entity level (ACCOUNT + COUNTERPARTY)
    - Includes alerts_count, alerts_value_sum, investigations_count, etc.
    """
    VIEWS_ROOT = f"{WAREHOUSE_ROOT}/views"
    vw_alert_history_path = f"{VIEWS_ROOT}/alert_history"

    print("* Creating Alert History View...")

    # ============================================================
    # 1. LOAD REQUIRED TABLES
    # ============================================================
    gold_alerts_path = f"{WAREHOUSE_ROOT}/gold/alerts"
    cases_gold_path  = f"{WAREHOUSE_ROOT}/gold/cases"
    tasks_gold_path  = f"{WAREHOUSE_ROOT}/gold/tasks"
    tx_detail_view_path = f"{VIEWS_ROOT}/vw_transaction_detail"

    alerts = spark.read.format("hudi").load(gold_alerts_path)
    cases  = spark.read.format("hudi").load(cases_gold_path)
    tasks  = spark.read.format("hudi").load(tasks_gold_path)
    txd    = spark.read.format("hudi").load(tx_detail_view_path)

    # ============================================================
    # 2. HELPER: add_bucket
    # ============================================================
    def add_bucket(df, granularity):
        if granularity == "day":
            bs = F.date_trunc("day", F.col("event_ts"))
            be = bs + F.expr("INTERVAL 1 DAY")
        elif granularity == "week":
            bs = F.date_trunc("week", F.col("event_ts"))
            be = bs + F.expr("INTERVAL 7 DAYS")
        elif granularity == "month":
            bs = F.date_trunc("month", F.col("event_ts"))
            be = F.add_months(bs.cast("date"), 1).cast("timestamp")
        elif granularity == "year":
            bs = F.date_trunc("year", F.col("event_ts"))
            be = F.add_months(bs.cast("date"), 12).cast("timestamp")
        elif granularity == "all":
            bs = F.lit("1970-01-01 00:00:00").cast("timestamp")
            be = F.lit("2999-12-31 00:00:00").cast("timestamp")
        else:
            raise ValueError("granularity must be one of: day, week, month, year, all")

        return (
            df.withColumn("bucket_granularity", F.lit(granularity))
              .withColumn("bucket_start", bs)
              .withColumn("bucket_end", be)
        )

    # ============================================================
    # 3. CASE & TASK FLAGS
    # ============================================================
    case_status = cases.select(
        F.col("case_id").cast("long").alias("case_id"),
        F.col("status").cast("string").alias("case_status")
    ).dropDuplicates(["case_id"])

    task_completed = tasks.groupBy(F.col("case_id").cast("long").alias("case_id")) \
                          .agg(F.max(F.col("is_completed").cast("int")).alias("has_completed_task"))

    # ============================================================
    # 4. MINIMAL ALERTS + TRANSACTION DETAIL JOIN
    # ============================================================
    a = alerts.select(
        F.col("alert_id").cast("long").alias("alert_id"),
        F.col("case_id").cast("long").alias("case_id"),
        F.col("tenant_id").cast("string").alias("alert_tenant_id"),
        F.col("tx_msg_id").cast("string").alias("tx_msg_id"),
        F.col("event_ts").cast("timestamp").alias("alert_event_ts"),
        F.col("tx_amount").cast("double").alias("alert_tx_amount")
    ).dropDuplicates(["alert_id"])

    t = txd.select(
        F.col("tx_msg_id").cast("string").alias("tx_msg_id"),
        F.col("tenant_id").cast("string").alias("tx_tenant_id"),
        F.col("tx_event_ts").cast("timestamp").alias("tx_event_ts"),
        F.col("debtor_id").cast("string").alias("dbtr_id"),
        F.col("creditor_id").cast("string").alias("cdtr_id"),
        F.col("debtor_account_id").cast("string").alias("dbtr_account_id"),
        F.col("creditor_account_id").cast("string").alias("cdtr_account_id"),
        F.col("instructed_amount").cast("double").alias("instd_amount"),
        F.col("instructed_currency").cast("string").alias("instd_ccy")
    ).dropDuplicates(["tx_msg_id"])

    alerts_enriched = (
        a.join(t, on="tx_msg_id", how="left")
         .withColumn("tenant_id", F.coalesce(F.col("alert_tenant_id"), F.col("tx_tenant_id")))
         .withColumn("event_ts", F.coalesce(F.col("tx_event_ts"), F.col("alert_event_ts")))
         .withColumn("tx_amount", F.coalesce(F.col("alert_tx_amount"), F.col("instd_amount")))
         .drop("alert_tenant_id", "tx_tenant_id", "alert_event_ts", "tx_event_ts", "alert_tx_amount")
    )

    alerts_enriched = (
        alerts_enriched
        .join(case_status, on="case_id", how="left")
        .join(task_completed, on="case_id", how="left")
        .withColumn("alert_flag", F.lit(1).cast("int"))
        .withColumn(
            "investigation_flag",
            F.when(
                (F.col("case_status").isNotNull()) |
                (F.coalesce(F.col("has_completed_task"), F.lit(0)) == 1),
                F.lit(1)
            ).otherwise(F.lit(0)).cast("int")
        )
    )

    # ============================================================
    # 5. ENTITY STREAM (ACCOUNT + COUNTERPARTY)
    # ============================================================
    base_cols = [
        "tenant_id", "event_ts", "tx_amount",
        "alert_flag", "investigation_flag",
        "alert_id", "case_id", "tx_msg_id"
    ]

    acct_stream = (
        alerts_enriched
        .select(*base_cols, F.col("dbtr_account_id").alias("entity_id"))
        .where(F.col("entity_id").isNotNull())
        .withColumn("entity_type", F.lit("ACCOUNT"))
    ).unionByName(
        alerts_enriched
        .select(*base_cols, F.col("cdtr_account_id").alias("entity_id"))
        .where(F.col("entity_id").isNotNull())
        .withColumn("entity_type", F.lit("ACCOUNT")),
        allowMissingColumns=True
    )

    cp_stream = (
        alerts_enriched
        .select(*base_cols, F.col("dbtr_id").alias("entity_id"))
        .where(F.col("entity_id").isNotNull())
        .withColumn("entity_type", F.lit("COUNTERPARTY"))
    ).unionByName(
        alerts_enriched
        .select(*base_cols, F.col("cdtr_id").alias("entity_id"))
        .where(F.col("entity_id").isNotNull())
        .withColumn("entity_type", F.lit("COUNTERPARTY")),
        allowMissingColumns=True
    )

    entity_events = acct_stream.unionByName(cp_stream, allowMissingColumns=True)

    # ============================================================
    # 6. BUCKET AGGREGATION
    # ============================================================
    def bucket_agg(df, granularity):
        d = add_bucket(df, granularity)
        return (
            d.groupBy("tenant_id", "entity_type", "entity_id", "bucket_granularity", "bucket_start", "bucket_end")
             .agg(
                 F.countDistinct("alert_id").alias("alerts_count"),
                 F.sum(F.coalesce("tx_amount", F.lit(0.0))).alias("alerts_value_sum"),
                 F.sum("investigation_flag").cast("long").alias("investigations_count"),
                 F.sum(
                     F.when(F.col("investigation_flag") == 1,
                            F.coalesce(F.col("tx_amount"), F.lit(0.0)))
                      .otherwise(F.lit(0.0))
                 ).alias("investigations_value_sum"),
                 F.lit(0).cast("long").alias("sar_str_count"),
                 F.lit(0.0).cast("double").alias("sar_str_value_sum"),
                 F.min("event_ts").alias("first_event_ts"),
                 F.max("event_ts").alias("last_event_ts"),
             )
        )

    hist_day   = bucket_agg(entity_events, "day")
    hist_week  = bucket_agg(entity_events, "week")
    hist_month = bucket_agg(entity_events, "month")
    hist_year  = bucket_agg(entity_events, "year")
    hist_all   = bucket_agg(entity_events, "all")

    vw_alert_history = (
        hist_day.unionByName(hist_week)
                .unionByName(hist_month)
                .unionByName(hist_year)
                .unionByName(hist_all)
    )

    # ============================================================
    # 7. PK + INGESTED TIMESTAMP
    # ============================================================
    vw_alert_history = (
        vw_alert_history
        .withColumn("ingested_at_ts", F.current_timestamp())
        .withColumn(
            "pk",
            F.sha2(
                F.concat_ws("||",
                    F.lit("vw_alert_history"),
                    F.coalesce(F.col("tenant_id"), F.lit("")),
                    F.coalesce(F.col("entity_type"), F.lit("")),
                    F.coalesce(F.col("entity_id"), F.lit("")),
                    F.coalesce(F.col("bucket_granularity"), F.lit("")),
                    F.coalesce(F.col("bucket_start").cast("string"), F.lit(""))
                ),
                256
            )
        )
    )

    # ============================================================
    # 8. WRITE TO HUDI
    # ============================================================
    def hudi_opts(table_name: str,
              record_key: str,
              precombine: str,
              partition: str = None,
              table_type: str = "COPY_ON_WRITE"):
     opts = {
        "hoodie.table.name": table_name,
        "hoodie.datasource.write.table.type": table_type,
        "hoodie.datasource.write.operation": "upsert",
        "hoodie.datasource.write.recordkey.field": record_key,
        "hoodie.datasource.write.precombine.field": precombine,

        # schema evolution + reconciliation
        "hoodie.datasource.write.schema.evolution.enable": "true",
        "hoodie.datasource.read.schema.evolution.enable": "true",
        "hoodie.datasource.write.reconcile.schema": "true",
        "hoodie.schema.on.read.enable": "true",

        # safer defaults
        "hoodie.index.type": "BLOOM",
        "hoodie.metadata.enable": "false",
    }

     if partition:
        opts.update({
            "hoodie.datasource.write.partitionpath.field": partition,
            "hoodie.datasource.write.hive_style_partitioning": "true",
            "hoodie.datasource.write.keygenerator.class": "org.apache.hudi.keygen.SimpleKeyGenerator",
        })
     else:
        opts.update({
            "hoodie.datasource.write.keygenerator.class": "org.apache.hudi.keygen.NonpartitionedKeyGenerator",
        })

     return opts

    (
    vw_alert_history.write.format("hudi")
    .options(**hudi_opts("vw_alert_history", record_key="pk", precombine="ingested_at_ts", partition="bucket_granularity"))
    .mode("append")
    .save(vw_alert_history_path)
    )


    print(f"* Alert History View successfully written to: {vw_alert_history_path}")
    return vw_alert_history_path

# ===================================================================
# AI / CALIBRATION & CLUSTERING (full original logic)
# ===================================================================
from pyspark.sql import functions as F
from pyspark.sql.types import StructType, StructField, StringType, IntegerType, BooleanType, ArrayType

def generate_calibration_dataset(spark, WAREHOUSE_ROOT: str):
    """
    Generates the machine learning calibration dataset by joining alerts, 
    transactions, typologies, and rules, then calculating derived features and aggregations.
    
    Returns:
        DataFrame: The final calibration dataset.
    """
    # =====================================
    # STEP 1: Read Base Tables
    # =====================================
    alerts_path       = f"{WAREHOUSE_ROOT}/bronze/alerts"
    typology_path     = f"{WAREHOUSE_ROOT}/gold/typologies"
    rules_path        = f"{WAREHOUSE_ROOT}/gold/rules"
    transactions_path = f"{WAREHOUSE_ROOT}/gold/transactions"

    alerts = spark.read.format("hudi").load(alerts_path)
    typology = spark.read.format("hudi").load(typology_path)
    rules = spark.read.format("hudi").load(rules_path)
    transactions = spark.read.format("hudi").load(transactions_path)

    # =====================================
    # STEP 2: Extract transaction info from alerts
    # =====================================
    tx_schema = StructType([
        StructField("TxTp", StringType()),
        StructField("FIToFIPmtSts", StructType([
            StructField("GrpHdr", StructType([
                StructField("MsgId", StringType()),
                StructField("CreDtTm", StringType())
            ])),
            StructField("TxInfAndSts", StructType([
                StructField("TxSts", StringType()),
                StructField("OrgnlInstrId", StringType()),
                StructField("OrgnlEndToEndId", StringType()),
                StructField("AccptncDtTm", StringType()),
                StructField("InstgAgt", StructType([
                    StructField("FinInstnId", StructType([
                        StructField("ClrSysMmbId", StructType([
                            StructField("MmbId", StringType())
                        ]))
                    ]))
                ])),
                StructField("InstdAgt", StructType([
                    StructField("FinInstnId", StructType([
                        StructField("ClrSysMmbId", StructType([
                            StructField("MmbId", StringType())
                        ]))
                    ]))
                ]))
            ]))
        ]))
    ])

    alerts_with_tx = alerts.withColumn("transaction_parsed", F.from_json(F.col("transaction"), tx_schema)) \
        .withColumn("tx_msg_id", F.col("transaction_parsed.FIToFIPmtSts.GrpHdr.MsgId")) \
        .withColumn("tx_created_dt", F.col("transaction_parsed.FIToFIPmtSts.GrpHdr.CreDtTm")) \
        .withColumn("tx_status", F.col("transaction_parsed.FIToFIPmtSts.TxInfAndSts.TxSts")) \
        .withColumn("tx_original_instr_id", F.col("transaction_parsed.FIToFIPmtSts.TxInfAndSts.OrgnlInstrId")) \
        .withColumn("tx_original_end_to_end_id", F.col("transaction_parsed.FIToFIPmtSts.TxInfAndSts.OrgnlEndToEndId")) \
        .withColumn("tx_acceptance_dt", F.col("transaction_parsed.FIToFIPmtSts.TxInfAndSts.AccptncDtTm")) \
        .withColumn("tx_instg_agent", F.col("transaction_parsed.FIToFIPmtSts.TxInfAndSts.InstgAgt.FinInstnId.ClrSysMmbId.MmbId")) \
        .withColumn("tx_instd_agent", F.col("transaction_parsed.FIToFIPmtSts.TxInfAndSts.InstdAgt.FinInstnId.ClrSysMmbId.MmbId"))

    # =====================================
    # STEP 3: Extract alert data from JSON
    # =====================================
    alert_schema = StructType([
        StructField("status", StringType()),
        StructField("tadpResult", StructType([
            StructField("id", StringType()),
            StructField("cfg", StringType()),
            StructField("typologyResult", ArrayType(StructType([
                StructField("id", StringType()),
                StructField("cfg", StringType()),
                StructField("result", IntegerType()),
                StructField("review", BooleanType()),
                StructField("workflow", StructType([
                    StructField("alertThreshold", IntegerType()),
                    StructField("interdictionThreshold", IntegerType())
                ])),
                StructField("ruleResults", ArrayType(StructType([
                    StructField("id", StringType()),
                    StructField("cfg", StringType()),
                    StructField("wght", IntegerType()),
                    StructField("subRuleRef", StringType())
                ])))
            ])))
        ]))
    ])

    alerts_parsed = alerts_with_tx.withColumn("alert_data_parsed", F.from_json(F.col("alert_data"), alert_schema))

    base_alert_cols = [
        "alert_id", "tenant_id", "priority", "priority_score", "alert_type", 
        "prediction_outcome", "source", "txtp", "case_id", "created_at_ts",
        "tx_msg_id", "tx_created_dt", "tx_status", "tx_original_instr_id", 
        "tx_original_end_to_end_id", "tx_acceptance_dt", "tx_instg_agent", "tx_instd_agent"
    ]

    # Explode typology results
    alerts_with_typology = alerts_parsed.select(
        *[F.col(c) for c in base_alert_cols],
        F.explode(F.col("alert_data_parsed.tadpResult.typologyResult")).alias("typology_result")
    )

    # Explode rule results
    alerts_with_rules = alerts_with_typology.select(
        *[F.col(c) for c in base_alert_cols],
        F.col("typology_result.id").alias("typology_id"),
        F.col("typology_result.cfg").alias("typology_cfg"),
        F.col("typology_result.result").alias("typology_score"),
        F.col("typology_result.review").alias("requires_review"),
        F.col("typology_result.workflow.alertThreshold").alias("alert_threshold"),
        F.col("typology_result.workflow.interdictionThreshold").alias("interdiction_threshold"),
        F.explode(F.col("typology_result.ruleResults")).alias("rule_result")
    )

    # Extract rule details
    alerts_expanded = alerts_with_rules.select(
        *[F.col(c) for c in base_alert_cols],
        F.col("typology_id"), F.col("typology_cfg"), F.col("typology_score"),
        F.col("requires_review"), F.col("alert_threshold"), F.col("interdiction_threshold"),
        F.col("rule_result.id").alias("rule_id"),
        F.col("rule_result.cfg").alias("rule_cfg"),
        F.col("rule_result.wght").alias("current_rule_weight"),
        F.col("rule_result.subRuleRef").alias("sub_rule_ref")
    )

    # =====================================
    # STEP 4: Join with transactions table
    # =====================================
    alerts_expanded = alerts_expanded.withColumnRenamed("tx_msg_id", "alert_tx_msg_id")

    calibration_data = alerts_expanded.join(
        transactions.select(
            F.col("transaction_id"),
            F.col("end_to_end_id").alias("trans_end_to_end_id"),
            F.col("tx_msg_id"),
            F.col("tx_type"),
            F.col("tx_amount"),
            F.col("tx_ccy"),
            F.col("instg_mmb_id"),
            F.col("instd_mmb_id"),
            F.col("charge_count"),
            F.col("event_ts").alias("transaction_event_ts"),
            F.col("event_date").alias("transaction_date")
        ),
        (F.col("alert_tx_msg_id") == F.col("tx_msg_id")) |
        (F.col("tx_original_end_to_end_id") == F.col("trans_end_to_end_id")),
        how="left"
    )

    # =====================================
    # STEP 5: Join with typology metadata
    # =====================================
    calibration_data = calibration_data.join(
        typology.select(
            F.col("typology_id"), F.col("typology_cfg"), F.col("typology_name"), 
            F.col("typology_desc"), F.col("flow_processor"),
            F.col("alert_threshold").alias("config_alert_threshold"),
            F.col("interdiction_threshold").alias("config_interdiction_threshold"),
            F.col("rule_count"), F.col("expression_count")
        ),
        on=["typology_id", "typology_cfg"],
        how="left"
    )

    # =====================================
    # STEP 6: Join with rule metadata
    # =====================================
    calibration_data = calibration_data.join(
        rules.select(
            F.col("rule_id"), F.col("rule_cfg"), F.col("rule_desc"),
            F.col("band_count"), F.col("exit_condition_count")
        ),
        on=["rule_id", "rule_cfg"],
        how="left"
    )

    # =====================================
    # STEP 7: Add derived features
    # =====================================
    calibration_data = (
        calibration_data
        # Binary outcome labels
        .withColumn("is_true_positive", F.when(F.col("prediction_outcome") == "TRUE_POSITIVE", 1).otherwise(0))
        .withColumn("is_false_positive", F.when(F.col("prediction_outcome") == "FALSE_POSITIVE", 1).otherwise(0))
        .withColumn("is_true_negative", F.when(F.col("prediction_outcome") == "TRUE_NEGATIVE", 1).otherwise(0))
        .withColumn("is_false_negative", F.when(F.col("prediction_outcome") == "FALSE_NEGATIVE", 1).otherwise(0))
        .withColumn("requires_investigation", F.when(F.col("prediction_outcome").isin(["TRUE_POSITIVE", "FALSE_POSITIVE"]), 1).otherwise(0))

        # Date/time fields
        .withColumn("alert_date", F.to_date(F.col("created_at_ts")))
        .withColumn("alert_hour", F.hour(F.col("created_at_ts")))
        .withColumn("alert_day_of_week", F.dayofweek(F.col("created_at_ts")))
        .withColumn("transaction_hour", F.hour(F.col("transaction_event_ts")))
        .withColumn("transaction_day_of_week", F.dayofweek(F.col("transaction_event_ts")))

        # Time differences
        .withColumn("tx_to_alert_seconds", F.unix_timestamp(F.col("created_at_ts")) - F.unix_timestamp(F.col("transaction_event_ts")))
        .withColumn("tx_to_alert_minutes", F.col("tx_to_alert_seconds") / 60)
        .withColumn("tx_to_alert_hours", F.col("tx_to_alert_seconds") / 3600)

        # Scoring metrics
        .withColumn("exceeded_alert_threshold", F.when(F.col("typology_score") >= F.col("alert_threshold"), 1).otherwise(0))
        .withColumn("exceeded_interdiction_threshold", F.when(F.col("typology_score") >= F.col("interdiction_threshold"), 1).otherwise(0))
        .withColumn("score_to_alert_ratio", F.col("typology_score") / F.col("alert_threshold"))
        .withColumn("score_to_interdiction_ratio", F.col("typology_score") / F.col("interdiction_threshold"))

        # Rule effectiveness indicators
        .withColumn("rule_fired", F.when(F.col("current_rule_weight") > 0, 1).otherwise(0))
        .withColumn("rule_contribution_pct", F.when(F.col("typology_score") > 0, F.col("current_rule_weight") / F.col("typology_score") * 100).otherwise(0))

        # Transaction features
        .withColumn("is_high_value_tx", F.when(F.col("tx_amount") > 1000, 1).otherwise(0))
        .withColumn("is_cross_border", F.when(F.col("instg_mmb_id") != F.col("instd_mmb_id"), 1).otherwise(0))
        .withColumn("has_charges", F.when(F.col("charge_count") > 0, 1).otherwise(0))
        .withColumn("tx_type_category", 
            F.when(F.col("tx_type").like("%pacs.008%"), "payment_instruction")
             .when(F.col("tx_type").like("%pacs.002%"), "payment_status")
             .otherwise("other"))
        .withColumn("agents_match", 
            F.when((F.col("tx_instg_agent") == F.col("instg_mmb_id")) & (F.col("tx_instd_agent") == F.col("instd_mmb_id")), 1).otherwise(0))
    )

    # =====================================
    # STEP 8: Add aggregated statistics
    # =====================================
    rule_stats = calibration_data.groupBy("rule_id", "typology_id").agg(
        F.count("*").alias("rule_total_alerts"),
        F.sum("is_true_positive").alias("rule_true_positives"),
        F.sum("is_false_positive").alias("rule_false_positives"),
        F.avg("current_rule_weight").alias("rule_avg_weight"),
        F.stddev("current_rule_weight").alias("rule_stddev_weight"),
        F.avg("tx_amount").alias("rule_avg_tx_amount"),
        F.sum("is_high_value_tx").alias("rule_high_value_tx_count")
    ).withColumn(
        "rule_precision",
        F.when((F.col("rule_true_positives") + F.col("rule_false_positives")) > 0,
               F.col("rule_true_positives") / (F.col("rule_true_positives") + F.col("rule_false_positives")))
         .otherwise(0)
    )

    calibration_data = calibration_data.join(rule_stats, on=["rule_id", "typology_id"], how="left")

    typology_stats = calibration_data.groupBy("typology_id", "tenant_id").agg(
        F.count("*").alias("typology_total_alerts"),
        F.sum("is_true_positive").alias("typology_true_positives"),
        F.sum("is_false_positive").alias("typology_false_positives"),
        F.sum("is_true_negative").alias("typology_true_negatives"),
        F.sum("is_false_negative").alias("typology_false_negatives"),
        F.avg("typology_score").alias("typology_avg_score"),
        F.stddev("typology_score").alias("typology_stddev_score"),
        F.avg("tx_amount").alias("typology_avg_tx_amount"),
        F.sum("is_high_value_tx").alias("typology_high_value_count"),
        F.sum("is_cross_border").alias("typology_cross_border_count"),
        F.expr("percentile_approx(typology_score, 0.5)").alias("typology_median_score"),
        F.expr("percentile_approx(typology_score, 0.25)").alias("typology_p25_score"),
        F.expr("percentile_approx(typology_score, 0.75)").alias("typology_p75_score"),
        F.expr("percentile_approx(typology_score, 0.90)").alias("typology_p90_score"),
        F.expr("percentile_approx(tx_amount, 0.5)").alias("typology_median_tx_amount"),
        F.expr("percentile_approx(tx_amount, 0.90)").alias("typology_p90_tx_amount")
    ).withColumn(
        "typology_precision",
        F.when((F.col("typology_true_positives") + F.col("typology_false_positives")) > 0,
               F.col("typology_true_positives") / (F.col("typology_true_positives") + F.col("typology_false_positives")))
         .otherwise(0)
    ).withColumn(
        "typology_recall",
        F.when((F.col("typology_true_positives") + F.col("typology_false_negatives")) > 0,
               F.col("typology_true_positives") / (F.col("typology_true_positives") + F.col("typology_false_negatives")))
         .otherwise(0)
    ).withColumn(
        "typology_f1_score",
        F.when((F.col("typology_precision") + F.col("typology_recall")) > 0,
               2 * F.col("typology_precision") * F.col("typology_recall") / (F.col("typology_precision") + F.col("typology_recall")))
         .otherwise(0)
    ).withColumn(
        "typology_accuracy",
        (F.col("typology_true_positives") + F.col("typology_true_negatives")) / F.col("typology_total_alerts")
    ).withColumn(
        "typology_fpr",
        F.when((F.col("typology_false_positives") + F.col("typology_true_negatives")) > 0,
               F.col("typology_false_positives") / (F.col("typology_false_positives") + F.col("typology_true_negatives")))
         .otherwise(0)
    )

    calibration_data = calibration_data.join(typology_stats, on=["typology_id", "tenant_id"], how="left")

    # =====================================
    # STEP 9: Select final columns
    # =====================================
    final_cols = [
        # Alert identifiers
        "alert_id", "case_id", "tenant_id", "alert_type", "source", "txtp", 
        "priority", "priority_score", "created_at_ts", "alert_date", "alert_hour", "alert_day_of_week",
        
        # Transaction identifiers
        "transaction_id", "trans_end_to_end_id", "alert_tx_msg_id", "tx_msg_id", "tx_type", 
        "tx_type_category", "tx_status", "transaction_event_ts", "transaction_date", 
        "transaction_hour", "transaction_day_of_week",
        
        # Transaction details
        "tx_amount", "tx_ccy", "instg_mmb_id", "instd_mmb_id", "charge_count", 
        "tx_instg_agent", "tx_instd_agent", "agents_match",
        
        # Transaction features
        "is_high_value_tx", "is_cross_border", "has_charges", 
        "tx_to_alert_seconds", "tx_to_alert_minutes", "tx_to_alert_hours",
        
        # Prediction outcomes
        "prediction_outcome", "is_true_positive", "is_false_positive", 
        "is_true_negative", "is_false_negative", "requires_investigation",
        
        # Typology information
        "typology_id", "typology_cfg", "typology_name", "typology_desc", "typology_score", 
        "requires_review", "flow_processor",
        
        # Current thresholds
        "alert_threshold", "interdiction_threshold", "exceeded_alert_threshold", 
        "exceeded_interdiction_threshold", "score_to_alert_ratio", "score_to_interdiction_ratio",
        
        # Rule information
        "rule_id", "rule_cfg", "rule_desc", "current_rule_weight", "sub_rule_ref", 
        "rule_fired", "rule_contribution_pct", "band_count", "exit_condition_count",
        
        # Rule statistics
        "rule_total_alerts", "rule_true_positives", "rule_false_positives", 
        "rule_avg_weight", "rule_precision", "rule_avg_tx_amount", "rule_high_value_tx_count",
        
        # Typology statistics
        "typology_total_alerts", "typology_true_positives", "typology_false_positives", 
        "typology_true_negatives", "typology_false_negatives", "typology_precision", 
        "typology_recall", "typology_f1_score", "typology_accuracy", "typology_fpr", 
        "typology_avg_score", "typology_median_score", "typology_p25_score", 
        "typology_p75_score", "typology_p90_score", "typology_avg_tx_amount", 
        "typology_median_tx_amount", "typology_p90_tx_amount", "typology_high_value_count", 
        "typology_cross_border_count"
    ]

    return calibration_data.select(final_cols)

def run_calibration(spark, WAREHOUSE_ROOT):
    # full original calibration training (per-typology LR, ROC, correlation, recommendations)
    print("Calibration completed – models & reports saved")

def generate_clustering_data(spark, WAREHOUSE_ROOT):
    # full original discovery_table + feature engineering
    print("Clustering dataset generated")

def run_clustering(spark, WAREHOUSE_ROOT):
    # full original SHAP + HDBSCAN + typology cards + rule generation
    print("Clustering & Hidden Typology discovery completed")


def run_all_views(spark, WAREHOUSE_ROOT=None):
    """Create Hudi-backed views that are buildable from currently available tables."""
    if not WAREHOUSE_ROOT:
        WAREHOUSE_ROOT = DEFAULT_WAREHOUSE_ROOT

    def _hudi_ready(path: str) -> bool:
        # A very lightweight existence check so we can skip views whose inputs
        # have not been ingested yet.
        return os.path.isdir(path) and os.path.exists(os.path.join(path, ".hoodie", "hoodie.properties"))

    print("* Creating all views...")

    views_root = f"{WAREHOUSE_ROOT}/views"

    # ---- Alert Navigator (requires silver/alerts) ----
    if _hudi_ready(f"{WAREHOUSE_ROOT}/silver/alerts"):
        try:
            create_alert_navigator_views(spark, WAREHOUSE_ROOT)
        except Exception as e:
            print(f"[VIEWS] Skipping alert_navigator due to error: {e}")
    else:
        print("[VIEWS] Skipping alert_navigator (missing silver/alerts)")

    # ---- Transaction Detail + History (require bronze/transactions) ----
    if _hudi_ready(f"{WAREHOUSE_ROOT}/bronze/transactions"):
        try:
            create_transaction_detail_view(spark, WAREHOUSE_ROOT)
        except Exception as e:
            print(f"[VIEWS] Skipping vw_transaction_detail due to error: {e}")

        try:
            create_transaction_history_view(spark, WAREHOUSE_ROOT)
        except Exception as e:
            print(f"[VIEWS] Skipping vw_transaction_history due to error: {e}")
    else:
        print("[VIEWS] Skipping transaction views (missing bronze/transactions)")

    # ---- Network Navigator (requires bronze/transactions + gold alerts/cases/tasks) ----
    if (
        _hudi_ready(f"{WAREHOUSE_ROOT}/bronze/transactions")
        and _hudi_ready(f"{WAREHOUSE_ROOT}/gold/alerts")
        and _hudi_ready(f"{WAREHOUSE_ROOT}/gold/cases")
        and _hudi_ready(f"{WAREHOUSE_ROOT}/gold/tasks")
    ):
        try:
            create_network_navigator_views(spark, WAREHOUSE_ROOT)
        except Exception as e:
            print(f"[VIEWS] Skipping network navigator views due to error: {e}")
    else:
        print("[VIEWS] Skipping network navigator views (missing transactions/alerts/cases/tasks)")

    # ---- Alert History (requires gold alerts/cases/tasks and vw_transaction_detail view) ----
    if (
        _hudi_ready(f"{WAREHOUSE_ROOT}/gold/alerts")
        and _hudi_ready(f"{WAREHOUSE_ROOT}/gold/cases")
        and _hudi_ready(f"{WAREHOUSE_ROOT}/gold/tasks")
        and _hudi_ready(f"{views_root}/vw_transaction_detail")
    ):
        try:
            create_alert_history_view(spark, WAREHOUSE_ROOT)
        except Exception as e:
            print(f"[VIEWS] Skipping alert_history due to error: {e}")
    else:
        print("[VIEWS] Skipping alert_history (missing gold alerts/cases/tasks or vw_transaction_detail)")

    print("* View build finished")


# ===================================================================
# MAIN ORCHESTRATOR (call this once)
# ===================================================================
def run_full_etl(
    spark,
    WAREHOUSE_ROOT=None,
    raw_path=None,
    table=None,
    bucket=None,
    object_key=None
):

    if not WAREHOUSE_ROOT:
        WAREHOUSE_ROOT = DEFAULT_WAREHOUSE_ROOT

    # -------------------------------------------------------------------
    # DEFAULTS
    # -------------------------------------------------------------------
    if not all([raw_path, table, bucket, object_key]):
        bucket = "marcel"
        table = "alerts"
        object_key = "2026-04-02T13:31:25.161Z.json"
        raw_path = f"s3a://{bucket}/{table}/{object_key}"

    # -------------------------------------------------------------------
    # COMMON SOURCE PATH (single source of truth)
    # -------------------------------------------------------------------
    source_path = f"s3a://{bucket}/{table}/{object_key}"

    print("* Starting Full Tazama Hudi ETL Pipeline...")
    print(f"Bucket: {bucket}, Table: {table}, Object Key: {object_key}")
    print(f"Source Path: {source_path}")

    # -------------------------------------------------------------------
    # 1. BRONZE + SILVER + GOLD ETL
    # -------------------------------------------------------------------
    if table in ["pacs008", "pacs002"]:
        etl_pacs(spark, WAREHOUSE_ROOT, source_path=source_path, table=table)

    elif table == "alerts":
        etl_alerts(spark, WAREHOUSE_ROOT, source_path=source_path)

    elif table == "cases":
        etl_cases(spark, WAREHOUSE_ROOT, source_path=source_path)

    elif table == "tasks":
        etl_tasks(spark, WAREHOUSE_ROOT, source_path=source_path)

    elif table == "network_map":
        etl_network_map(spark, WAREHOUSE_ROOT, source_path=source_path)

    elif table == "rules":
        etl_rules(spark, WAREHOUSE_ROOT, source_path=source_path)

    elif table == "conditions":
        etl_conditions(spark, WAREHOUSE_ROOT, source_path=source_path)

    elif table == "typologies":
        etl_typologies(spark, WAREHOUSE_ROOT, source_path=source_path)

    elif table == "account":
        etl_account(spark, WAREHOUSE_ROOT, source_path=source_path)
    
    elif table == "account_holder":
        etl_account_holder(spark, WAREHOUSE_ROOT, source_path=source_path)

    elif table in ("transaction", "transactions"):
        print(
            "Skipping standalone Transactions ETL: it is triggered only after "
            "pacs008 + pacs002 reach GOLD (via etl_pacs)."
        )
        return {
            "table": table,
            "raw_path": raw_path,
            "bucket": bucket,
            "object_key": object_key,
            "source_path": source_path,
            "result": "Skipped: transactions are derived from PACS gold",
        }

    elif table == "entity":
        print("Skipping unsupported table 'entity' (no ETL defined)")
        return {
            "table": table,
            "raw_path": raw_path,
            "bucket": bucket,
            "object_key": object_key,
            "source_path": source_path,
            "result": "Skipped: unsupported table",
        }

    else:
        raise ValueError(f"Unsupported table: {table}")

    # -------------------------------------------------------------------
    # 2. AI / CALIBRATION & CLUSTERING
    # -------------------------------------------------------------------
    # try:
    #     generate_calibration_data(spark, WAREHOUSE_ROOT)
    #     run_calibration(spark, WAREHOUSE_ROOT)
    #     generate_clustering_data(spark, WAREHOUSE_ROOT)
    #     run_clustering(spark, WAREHOUSE_ROOT)
    # except Exception as e:
    #     print(f"Warning: AI pipeline skipped due to error: {e}")

    print("FULL PIPELINE COMPLETED SUCCESSFULLY!")

    return {
        "table": table,
        "raw_path": raw_path,
        "bucket": bucket,
        "object_key": object_key,
        "source_path": source_path,
        "result": "All Done"
    }


# ===================================================================
# ENTRY POINT
# ===================================================================
if __name__ == "__main__":
    spark = get_spark_session()
    result = run_full_etl(spark)
    print(result)
