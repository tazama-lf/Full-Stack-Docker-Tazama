from fastapi import FastAPI, HTTPException, status, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import List, Optional, Dict, Any, Union
import uvicorn
import asyncio
from concurrent.futures import ThreadPoolExecutor
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql import types as T
from pyspark.sql.window import Window
import os
import threading
import findspark
import tempfile
import json
import time
import logging

# NOTE: nest_asyncio REMOVED — it is incompatible with uvicorn's production event loop
# and can cause deadlocks under concurrent load. All blocking Spark calls are now
# dispatched to a thread-pool executor instead.

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("pipeline")

# -----------------------------
# Spark init  (with recovery)
# -----------------------------
project_path = os.getcwd()
spark_path = os.getenv("SPARK_HOME", f"{project_path}/spark-3.4.2-bin-hadoop3")
os.environ["SPARK_HOME"] = spark_path
os.environ["PATH"] = f"{spark_path}/bin:{os.environ['PATH']}"
findspark.init(spark_path)

_spark_lock = threading.Lock()
_spark: Optional[SparkSession] = None


def _build_spark() -> SparkSession:
    spark_jars = os.getenv("SPARK_JARS", "").strip()
    builder = (
        SparkSession.builder
        .appName("ozone-alerts-pipeline")
        .master("local[*]")
        .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
        .config("spark.driver.memory", "4g")
        .config("spark.executor.memory", "4g")
        .config("spark.sql.shuffle.partitions", "8")
        .config("spark.default.parallelism", "8")
        #job-level timeout so a runaway query never hangs forever
        .config("spark.network.timeout", "300s")
        .config("spark.executor.heartbeatInterval", "60s")
    )

    if spark_jars:
        builder = (
            builder
            .config("spark.sql.extensions", "org.apache.spark.sql.hudi.HoodieSparkSessionExtension")
            .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.hudi.catalog.HoodieCatalog")
            .config("spark.jars", spark_jars)
        )

    return builder.getOrCreate()


def get_spark() -> SparkSession:
    """
    Return the global Spark session, recreating it if the driver has died.
    Thread-safe via a module-level lock.
    """
    global _spark
    with _spark_lock:
        if _spark is None or _spark._sc._jvm is None:
            logger.warning("Spark session missing or dead — recreating.")
            try:
                _spark = _build_spark()
                _spark.sparkContext.setLogLevel("WARN")
                _spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")
                _spark.conf.set("spark.sql.session.timeZone", "UTC")
                logger.info("Spark session created successfully.")
            except Exception as exc:
                logger.error(f"Failed to create Spark session: {exc}")
                raise RuntimeError(f"Spark session unavailable: {exc}") from exc
        return _spark


# Warm up Spark at import time so the first API call is not slow.
try:
    get_spark()
except Exception as e:
    logger.error(f"Spark warm-up failed at startup: {e}")


# -----------------------------
# FastAPI
# -----------------------------
app = FastAPI(
    title="Lakehouse Pipeline API (Ozone Alerts - Bronze/Silver/Gold)",
    description="REST API to ingest JSONL into Hudi Bronze->Silver->Gold (Scalar) and query Gold",
    version="2.0.0"
)

# Thread pool for all blocking Spark calls so the async event loop is never stalled
_executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="spark-worker")

# Request timeout (seconds)
SPARK_JOB_TIMEOUT = 120


async def run_in_executor(fn, *args, timeout: float = SPARK_JOB_TIMEOUT):
    """Run a blocking function in the thread pool with an optional timeout."""
    loop = asyncio.get_event_loop()
    future = loop.run_in_executor(_executor, fn, *args)
    try:
        return await asyncio.wait_for(future, timeout=timeout)
    except asyncio.TimeoutError:
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail={"status": "error", "code": 504,
                    "message": f"Spark job exceeded timeout of {timeout}s"}
        )

# Custom exception handler for validation errors
@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    errors = []
    for error in exc.errors():
        field = ".".join(str(loc) for loc in error["loc"] if loc != "body")
        errors.append({"field": field, "message": error["msg"], "type": error["type"]})
    return JSONResponse(
        status_code=422,
        content={"status": "error", "code": 422, "message": "Validation error", "errors": errors}
    )


# ---------------------------
# PATHS
# ---------------------------
WAREHOUSE_ROOT = os.getenv("WAREHOUSE_ROOT", "/opt/Tazama_Warehouse")

alerts_bronze_path      = f"{WAREHOUSE_ROOT}/bronze/alerts"
alerts_silver_path      = f"{WAREHOUSE_ROOT}/silver/alerts"
alerts_gold_path        = f"{WAREHOUSE_ROOT}/gold/alerts"
cases_gold_path         = f"{WAREHOUSE_ROOT}/gold/cases"
tasks_gold_path         = f"{WAREHOUSE_ROOT}/gold/tasks"
transactions_gold_path  = f"{WAREHOUSE_ROOT}/gold/transactions"
nmap_gold_path          = f"{WAREHOUSE_ROOT}/gold/network_map"
rules_gold_path         = f"{WAREHOUSE_ROOT}/gold/rules"
conditions_gold_path    = f"{WAREHOUSE_ROOT}/gold/conditions"
pacs008_gold_path       = f"{WAREHOUSE_ROOT}/gold/pacs008"
account_holder          = f"{WAREHOUSE_ROOT}/gold/account_holder"

VIEWS_ROOT                            = f"{WAREHOUSE_ROOT}/views"
ALERT_NAV_ROOT                        = f"{VIEWS_ROOT}/alert_navigator"
alerts_nav_header_path                = f"{ALERT_NAV_ROOT}/header"
alerts_nav_typologies_path            = f"{ALERT_NAV_ROOT}/typologies_triggered"
alerts_nav_rules_path                 = f"{ALERT_NAV_ROOT}/rules_triggered"
tx_detail_view_path                   = f"{VIEWS_ROOT}/vw_transaction_detail"
tx_history_view_path                  = f"{VIEWS_ROOT}/vw_transaction_history"
conditions_view_path                  = f"{VIEWS_ROOT}/conditions_timeline"
vw_tx_network_accounts_edges_path     = f"{VIEWS_ROOT}/vw_tx_network_accounts_edges"
vw_tx_network_counterparties_edges_path = f"{VIEWS_ROOT}/vw_tx_network_counterparties_edges"
vw_counterparty_account_links_path    = f"{VIEWS_ROOT}/vw_counterparty_account_links"

GOLD_PATHS = {
    "alerts":                          alerts_gold_path,
    "cases":                           cases_gold_path,
    "tasks":                           tasks_gold_path,
    "transactions":                    transactions_gold_path,
    "pacs008":                         pacs008_gold_path,
    "network_map":                     nmap_gold_path,
    "rules":                           rules_gold_path,
    "conditions":                      conditions_gold_path,
    "account_holder":                  account_holder,
    "alert_navigator_header":          alerts_nav_header_path,
    "alert_navigator_typologies":      alerts_nav_typologies_path,
    "alert_navigator_rules":           alerts_nav_rules_path,
    "transaction_detail":              tx_detail_view_path,
    "transaction_history":             tx_history_view_path,
    "conditions_timeline":             conditions_view_path,
    "tx_network_accounts_edges":       vw_tx_network_accounts_edges_path,
    "tx_network_counterparties_edges": vw_tx_network_counterparties_edges_path,
    "counterparty_account_links":      vw_counterparty_account_links_path,
}

# ---------------------------
# Schema cache 
# ---------------------------
# Schema inference is a full Spark job. Cache inferred schemas so it runs only once
# per process lifetime (invalidated explicitly if schemas change).
_schema_cache: Dict[str, T.StructType] = {}
_schema_cache_lock = threading.Lock()


def infer_json_schema_cached(df, col_name: str) -> T.StructType:
    """
    Cache inferred schemas to avoid triggering a full Spark job on every
    pipeline execution. Uses col_name as cache key.
    """
    spark = get_spark()
    with _schema_cache_lock:
        if col_name not in _schema_cache:
            logger.info(f"Inferring schema for column '{col_name}' (first time).")
            _schema_cache[col_name] = spark.read.json(
                df.select(col_name).where(F.col(col_name).isNotNull()).rdd.map(lambda r: r[0])
            ).schema
        return _schema_cache[col_name]


def invalidate_schema_cache():
    """Call this if the underlying JSON schema changes (e.g., after a schema migration)."""
    with _schema_cache_lock:
        _schema_cache.clear()
    logger.info("Schema cache invalidated.")


_sql_lock = threading.Lock()   # serialises temp-view registration + SQL execution


# ============================================================
# Helpers
# ============================================================

def ensure_columns(df, col_type_map: dict):
    out = df
    for c, t in col_type_map.items():
        if c in out.columns:
            out = out.withColumn(c, F.col(c).cast(t))
        else:
            out = out.withColumn(c, F.lit(None).cast(t))
    return out


def compute_record_hash(df, exclude_cols=None):
    exclude_cols = exclude_cols or []
    cols = [c for c in df.columns if c not in exclude_cols]
    return df.withColumn(
        "record_hash",
        F.sha2(
            F.concat_ws("||", *[F.coalesce(F.col(c).cast("string"), F.lit("")) for c in cols]),
            256
        )
    )


# ============================================================
# 1) JSONL -> BRONZE (Hudi)
# ============================================================

def jsonl_to_bronze_alerts(jsonl_path: str, source_file_path: str = None):
    spark = get_spark()

    raw = (
        spark.read
             .option("multiLine", "false")
             .option("mode", "PERMISSIVE")
             .json(jsonl_path)
    )

    bronze_contract = {
        "alert_id": "long",
        "tenant_id": "string",
        "priority": "string",
        "priority_score": "double",
        "alert_type": "string",
        "prediction_outcome": "string",
        "source": "string",
        "txtp": "string",
        "message": "string",
        "alert_data": "string",
        "transaction": "string",
        "network_map": "string",
        "confidence_per": "int",
        "case_id": "long",
        "created_at": "string",
    }

    bronze = ensure_columns(raw, bronze_contract)
    bronze = (
        bronze
        .withColumn("created_at_ts", F.current_timestamp())
        .withColumn("source_file_path", F.lit(source_file_path or jsonl_path))
    )
    bronze = compute_record_hash(bronze, exclude_cols=["created_at_ts"])
    bronze = bronze.withColumn("_row_payload_json", F.to_json(F.struct(*[F.col(c) for c in bronze.columns])))

    hudi_bronze_opts = {
        "hoodie.table.name": "bronze_alerts",
        "hoodie.datasource.write.table.type": "COPY_ON_WRITE",
        "hoodie.datasource.write.operation": "upsert",
        "hoodie.datasource.write.recordkey.field": "alert_id",
        "hoodie.datasource.write.precombine.field": "created_at_ts",
        "hoodie.datasource.write.keygenerator.class": "org.apache.hudi.keygen.NonpartitionedKeyGenerator",
        "hoodie.datasource.write.schema.evolution.enable": "true",
        "hoodie.datasource.read.schema.evolution.enable": "true",
        "hoodie.datasource.write.reconcile.schema": "true",
        "hoodie.schema.on.read.enable": "true",
        "hoodie.index.type": "BLOOM",
        "hoodie.metadata.enable": "false",
    }

    (
        bronze.write.format("hudi")
        .options(**hudi_bronze_opts)
        .mode("append")
        .save(alerts_bronze_path)
    )

    return bronze


# ============================================================
# 2) BRONZE -> SILVER (Hudi)
# ============================================================

def bronze_to_silver_alerts():
    spark = get_spark()
    bronze = spark.read.format("hudi").load(alerts_bronze_path)

    # use cached schema inference
    alert_schema = infer_json_schema_cached(bronze, "alert_data")
    tx_schema    = infer_json_schema_cached(bronze, "transaction")
    net_schema   = infer_json_schema_cached(bronze, "network_map")

    b = (
        bronze
        .withColumn("alert_data_obj", F.from_json("alert_data", alert_schema))
        .withColumn("transaction_obj", F.from_json("transaction", tx_schema))
        .withColumn("network_map_obj", F.from_json("network_map", net_schema))
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
        .withColumn(
            "rule_pairs",
            F.flatten(F.expr("""
                transform(alert_data_obj.tadpResult.typologyResult, t ->
                  transform(t.ruleResults, r ->
                    named_struct('rule_id', r.id, 'weight', cast(r.wght as long))))
            """))
        )
        .withColumn("rule_pairs", F.expr("filter(rule_pairs, x -> x.rule_id is not null)"))
        .withColumn("rule_pairs", F.expr("""
            aggregate(rule_pairs, cast(array() as array<struct<rule_id:string, weight:bigint>>),
              (acc, x) -> IF(array_contains(transform(acc, y -> y.rule_id), x.rule_id), acc, concat(acc, array(x))))
        """))
        .withColumn("rule_weights_json", F.to_json(F.col("rule_pairs")))
        .withColumn("rule_id_count_distinct", F.size(F.expr("transform(rule_pairs, x -> x.rule_id)")).cast("int"))
        .withColumn("rule_weight_sum",
            F.expr("aggregate(transform(rule_pairs, x -> x.weight), cast(0 as long), (acc,x) -> acc + coalesce(x, cast(0 as long)))").cast("long"))
        .withColumn("rule_weight_max",
            F.when(F.size("rule_pairs") > 0, F.array_max(F.expr("transform(rule_pairs, x -> x.weight)"))).otherwise(F.lit(0)).cast("long"))
        .withColumn("rule_weight_min",
            F.when(F.size("rule_pairs") > 0, F.array_min(F.expr("transform(rule_pairs, x -> x.weight)"))).otherwise(F.lit(0)).cast("long"))
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
            "alert_id","case_id","tenant_id",
            "priority","priority_score","alert_type","prediction_outcome","source","txtp","message","confidence_per",
            "event_ts","event_date","tx_created_ts","tx_accept_ts","created_at","created_at_ts",
            "alert_status","evaluation_id",
            "processing_time_dp","processing_time_ed",
            "tadp_id","tadp_cfg","tadp_processing_time",
            "typology_count","typology_ids","typology_results","typology_reviews",
            "workflow_processors","alert_thresholds","interdiction_thresholds",
            "rule_count_total",
            "rule_weights_json","rule_id_count_distinct","rule_weight_sum","rule_weight_max","rule_weight_min",
            "tx_type","tx_tenant_id","tx_msg_id","tx_status","tx_original_instr_id","tx_original_e2e_id",
            "instg_mmb_id","instd_mmb_id",
            "charge_count","charge_agent_mmb_ids","charge_amounts","charge_ccys",
            "network_cfg","network_active","network_tenant_id","network_message_count","network_message_ids",
            "source_file_path","record_hash",
            "alert_data","transaction","network_map",
        )
        .withColumn("_row_payload_json", F.to_json(F.struct("*")))
    )

    w = Window.partitionBy("alert_id").orderBy(F.col("created_at_ts").desc())
    silver = silver.withColumn("rn", F.row_number().over(w)).filter("rn=1").drop("rn")

    hudi_silver_opts = {
        "hoodie.table.name": "silver_alerts",
        "hoodie.datasource.write.table.type": "COPY_ON_WRITE",
        "hoodie.datasource.write.operation": "upsert",
        "hoodie.datasource.write.recordkey.field": "alert_id",
        "hoodie.datasource.write.precombine.field": "created_at_ts",
        "hoodie.datasource.write.keygenerator.class": "org.apache.hudi.keygen.NonpartitionedKeyGenerator",
        "hoodie.datasource.write.schema.evolution.enable": "true",
        "hoodie.datasource.read.schema.evolution.enable": "true",
        "hoodie.datasource.write.reconcile.schema": "true",
        "hoodie.schema.on.read.enable": "true",
        "hoodie.index.type": "BLOOM",
        "hoodie.metadata.enable": "false",
    }

    (
        silver.write.format("hudi")
        .options(**hudi_silver_opts)
        .mode("append")
        .save(alerts_silver_path)
    )

    return silver


# ============================================================
# 3) SILVER -> GOLD (Hudi, scalar-only)
# ============================================================

def silver_to_gold_alerts_scalar_only():
    spark = get_spark()
    silver = spark.read.format("hudi").load(alerts_silver_path)
    silver = silver.drop(*[c for c in silver.columns if c.startswith("hoodie")])

    w = Window.partitionBy("alert_id").orderBy(F.col("created_at_ts").desc())
    s = silver.withColumn("rn", F.row_number().over(w)).filter("rn=1").drop("rn")

    # use cached schema inference
    alert_schema = infer_json_schema_cached(s, "alert_data")
    g = s.withColumn("alert_data_obj", F.from_json("alert_data", alert_schema))

    g = (
        g
        .withColumn(
            "rule_pairs",
            F.flatten(F.expr("""
                transform(alert_data_obj.tadpResult.typologyResult, t ->
                  transform(t.ruleResults, r ->
                    named_struct('rule_id', r.id, 'weight', cast(r.wght as long))))
            """))
        )
        .withColumn("rule_pairs", F.expr("filter(rule_pairs, x -> x.rule_id is not null)"))
        .withColumn("rule_pairs", F.expr("""
            aggregate(rule_pairs, cast(array() as array<struct<rule_id:string, weight:bigint>>),
              (acc, x) -> IF(array_contains(transform(acc, y -> y.rule_id), x.rule_id), acc, concat(acc, array(x))))
        """))
        .withColumn("rule_weights", F.expr("transform(rule_pairs, x -> x.weight)"))
    )

    g = (
        g
        .withColumn("rule_id_count_distinct",
            F.size(F.array_distinct(F.expr("transform(rule_pairs, x -> x.rule_id)"))).cast("int"))
        .withColumn("rule_weight_sum",
            F.expr("aggregate(rule_weights, cast(0 as long), (acc,x) -> acc + coalesce(x, cast(0 as long)))").cast("long"))
        .withColumn("rule_weight_max",
            F.when(F.size("rule_weights") > 0, F.array_max("rule_weights")).otherwise(F.lit(0)).cast("long"))
        .withColumn("rule_weight_min",
            F.when(F.size("rule_weights") > 0, F.array_min("rule_weights")).otherwise(F.lit(0)).cast("long"))
        .withColumn("rule_weight_avg",
            F.when(F.size("rule_weights") > 0,
                   F.col("rule_weight_sum").cast("double") / F.size("rule_weights").cast("double")
            ).otherwise(F.lit(0.0)).cast("double"))
        .withColumn("rule_weight_p95",
            F.when(F.size("rule_weights") > 0,
                F.expr("""
                    element_at(array_sort(rule_weights),
                               cast(ceil(size(rule_weights) * 0.95) as int))
                """).cast("double")
            ).otherwise(F.lit(0.0)))
        .withColumn("top_rule_id",
            F.expr("""
                element_at(
                  transform(filter(rule_pairs, x -> x.weight = rule_weight_max), x -> x.rule_id),
                  1)
            """))
        .withColumn("top_rule_weight", F.col("rule_weight_max").cast("long"))
    )

    g = (
        g
        .withColumn("tx_amount",
            F.coalesce(
                F.get_json_object(F.col("transaction"), "$.FIToFIPmtSts.TxInfAndSts.OrgnlTxRef.Amt.InstdAmt.Amt").cast("double"),
                F.get_json_object(F.col("transaction"), "$.FIToFIPmtSts.TxInfAndSts.OrgnlTxRef.Amt.EqvtAmt.Amt").cast("double"),
                F.lit(None).cast("double")
            ))
        .withColumn("tx_ccy",
            F.coalesce(
                F.get_json_object(F.col("transaction"), "$.FIToFIPmtSts.TxInfAndSts.OrgnlTxRef.Amt.InstdAmt.Ccy"),
                F.get_json_object(F.col("transaction"), "$.FIToFIPmtSts.TxInfAndSts.OrgnlTxRef.Amt.EqvtAmt.Ccy"),
                F.lit(None).cast("string")
            ))
    )

    g = (
        g
        .withColumn("charge_total_amount",
            F.when(F.col("charge_amounts").isNotNull(),
                F.expr("aggregate(charge_amounts, cast(0.0 as double), (acc,x) -> acc + coalesce(x, 0.0))")
            ).otherwise(F.lit(0.0)))
        .withColumn("charge_currency_count",
            F.when(F.col("charge_ccys").isNotNull(), F.size(F.array_distinct("charge_ccys"))).otherwise(F.lit(0)))
        .withColumn("has_multi_currency_charges", (F.col("charge_currency_count") > 1).cast("int"))
    )

    g = (
        g
        .withColumn("total_processing_time_ms",
            (
                F.coalesce(F.col("processing_time_dp").cast("long"), F.lit(0)) +
                F.coalesce(F.col("processing_time_ed").cast("long"), F.lit(0)) +
                F.coalesce(F.col("tadp_processing_time").cast("long"), F.lit(0))
            ).cast("long"))
        .withColumn("event_to_ingest_ms",
            F.when(F.col("event_ts").isNotNull(),
                (F.col("created_at_ts").cast("long") - F.col("event_ts").cast("long")) * 1000
            ).otherwise(F.lit(None).cast("long")))
    )

    g = (
        g
        .withColumn("priority_norm", F.upper("priority"))
        .withColumn("alert_type_norm", F.upper("alert_type"))
        .withColumn("prediction_outcome_norm", F.upper("prediction_outcome"))
        .withColumn("security_tag", F.concat(F.lit("TENANT:"), F.col("tenant_id")))
    )

    gold = g.select(
        "alert_id","case_id","tenant_id",
        "priority_norm","priority_score",
        "alert_type_norm","prediction_outcome_norm",
        "source","txtp",
        "event_ts","created_at_ts","event_date",
        "alert_status","evaluation_id",
        "tx_type","tx_msg_id","tx_status","tx_amount","tx_ccy",
        "typology_count","rule_count_total",
        "rule_id_count_distinct","rule_weight_sum","rule_weight_max","rule_weight_min","rule_weight_avg","rule_weight_p95",
        "top_rule_id","top_rule_weight",
        "charge_count","charge_total_amount","charge_currency_count","has_multi_currency_charges",
        "network_message_count",
        "event_to_ingest_ms","total_processing_time_ms",
        "security_tag","source_file_path","record_hash"
    )

    bad = [c for c, t in gold.dtypes if t.startswith("array") or t.startswith("struct")]
    if bad:
        raise RuntimeError(f"Gold still contains non-scalar columns: {bad}")

    hudi_gold_opts = {
        "hoodie.table.name": "alerts",
        "hoodie.datasource.write.table.type": "COPY_ON_WRITE",
        "hoodie.datasource.write.operation": "upsert",
        "hoodie.datasource.write.recordkey.field": "alert_id",
        "hoodie.datasource.write.precombine.field": "created_at_ts",
        "hoodie.datasource.write.partitionpath.field": "event_date",
        "hoodie.datasource.write.keygenerator.class": "org.apache.hudi.keygen.SimpleKeyGenerator",
        "hoodie.datasource.write.hive_style_partitioning": "true",
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
        .save(alerts_gold_path)
    )

    return gold


# ============================================================
# Orchestrator
# ============================================================

def _run_alerts_pipeline_sync(jsonl_path: str):
    """Synchronous pipeline — called from thread pool by the async endpoint."""
    logger.info("Step 1/3: JSONL -> Bronze")
    bronze_df = jsonl_to_bronze_alerts(jsonl_path=jsonl_path, source_file_path=f"file://{jsonl_path}")
    bronze_count = bronze_df.count()
    logger.info(f"  Bronze rows: {bronze_count}")

    logger.info("Step 2/3: Bronze -> Silver")
    silver_df = bronze_to_silver_alerts()
    silver_count = silver_df.count()
    logger.info(f"  Silver rows: {silver_count}")

    logger.info("Step 3/3: Silver -> Gold (scalar-only)")
    gold_df = silver_to_gold_alerts_scalar_only()
    gold_count = gold_df.count()
    logger.info(f"  Gold rows: {gold_count}")

    return bronze_count, silver_count, gold_count


# ============================================================
# Helper: Query Hudi data (Gold registry)
# ============================================================

def _get_hudi_data_sync(table_name: str, filters: dict = None, columns: list = None, limit: int = None):
    """Synchronous query — called from thread pool."""
    if table_name not in GOLD_PATHS:
        raise ValueError(f"Table '{table_name}' not found in Gold registry")

    spark = get_spark()
    path = GOLD_PATHS[table_name]
    df = spark.read.format("hudi").load(path)
    valid_columns = set(df.columns)

    if filters:
        for col_name, value in filters.items():
            if col_name not in valid_columns or value is None:
                continue
            if isinstance(value, list):
                if value:
                    df = df.filter(F.col(col_name).isin(value))
            else:
                df = df.filter(F.col(col_name) == value)

    if columns:
        valid_select_cols = [c for c in columns if c in valid_columns]
        if valid_select_cols:
            df = df.select(*valid_select_cols)

    if limit:
        df = df.limit(limit)

    return [row.asDict(recursive=True) for row in df.collect()]


import re

def _execute_sql_sync(sql_query: str, limit: int = None):
    """
    Serialised temp-view registration + SQL execution.
    Uses a module-level lock to prevent concurrent requests from corrupting each
    other's view registrations.
    """
    spark = get_spark()
    with _sql_lock:
        for tname, path in GOLD_PATHS.items():
            spark.read.format("hudi").load(path).createOrReplaceTempView(tname)
        df = spark.sql(sql_query)
        if limit:
            df = df.limit(limit)
        return [row.asDict(recursive=True) for row in df.collect()]


# ============================================================
# Request Models
# ============================================================

class QueryRequest(BaseModel):
    table_name: str
    filters: Optional[Dict[str, Union[str, int, float, List[str], List[int], List[float]]]] = None
    columns: Optional[List[str]] = None
    limit: Optional[int] = 100


class SQLQueryRequest(BaseModel):
    sql_query: str
    limit: Optional[int] = 1000


class JSONLPathRequest(BaseModel):
    jsonl_path: str
    run_silver: bool = True
    run_gold: bool = True


class JSONToHudiRequest(BaseModel):
    payload: str
    table_name: str
    run_silver: bool = True
    run_gold: bool = True


# ============================================================
# API ENDPOINTS
# ============================================================

@app.get("/")
def read_root():
    return {
        "status": "online",
        "message": "Ozone Alerts Pipeline API",
        "warehouse_root": WAREHOUSE_ROOT,
        "endpoints": ["/health", "/tables", "/query", "/execute_sql", "/json_to_hudi_pipeline"]
    }


# FIX: Real health check — verifies Spark is alive and the warehouse root is accessible
@app.get("/health", status_code=status.HTTP_200_OK)
async def health_check():
    checks: Dict[str, Any] = {}
    overall_ok = True

    # 1. Spark session liveness
    try:
        spark = get_spark()
        # A trivial Spark action to confirm the driver is responsive
        spark.range(1).count()
        checks["spark"] = "ok"
    except Exception as e:
        checks["spark"] = f"error: {e}"
        overall_ok = False

    # 2. Warehouse root on disk
    checks["warehouse_root_exists"] = os.path.isdir(WAREHOUSE_ROOT)
    if not checks["warehouse_root_exists"]:
        overall_ok = False

    # 3. At least one gold table directory exists
    gold_dirs_found = [t for t, p in GOLD_PATHS.items() if os.path.isdir(p)]
    checks["gold_tables_found"] = len(gold_dirs_found)

    if not overall_ok:
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"status": "unhealthy", "checks": checks}
        )

    return {"status": "healthy", "checks": checks, "timestamp": time.time()}


@app.get("/tables")
def list_tables():
    return {"available_tables": list(GOLD_PATHS.keys())}


# FIX: async endpoint now dispatches blocking Spark work to the thread pool
@app.post("/query", status_code=status.HTTP_200_OK)
async def query_table(request: QueryRequest):
    try:
        data = await run_in_executor(
            _get_hudi_data_sync,
            request.table_name,
            request.filters,
            request.columns,
            request.limit,
        )
        return {
            "status": "success",
            "code": 200,
            "table": request.table_name,
            "row_count": len(data),
            "data": data
        }
    except HTTPException:
        raise
    except ValueError as ve:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "code": 404, "message": str(ve)[:120], "error_type": "ValueError"}
        )
    except Exception as e:
        logger.exception("query_table error")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={"status": "error", "code": 500, "message": "Internal server error", "error_details": str(e)[:120]}
        )


# FIX: async + serialised temp-view registration
@app.post("/execute_sql", status_code=status.HTTP_200_OK)
async def execute_sql(request: SQLQueryRequest):
    sql_query = request.sql_query.strip()

    # Sanitise escapes from some HTTP clients
    sql_query = re.sub(r"(\\')+(\\')+(\\')+'", "'", sql_query)
    sql_query = re.sub(r"\\'\\'\\'", "'", sql_query)
    sql_query = re.sub(r"\\'", "'", sql_query)
    sql_query = re.sub(r'\s+', ' ', sql_query).strip()

    forbidden_patterns = [
        r'\bINSERT\s+INTO\b', r'\bUPDATE\s+', r'\bDELETE\s+FROM\b', r'\bDROP\s+',
        r'\bCREATE\s+', r'\bALTER\s+', r'\bTRUNCATE\s+', r'\bMERGE\s+INTO\b', r'\bREPLACE\s+INTO\b'
    ]
    q_upper = sql_query.upper()

    for pattern in forbidden_patterns:
        if re.search(pattern, q_upper):
            raise HTTPException(
                status_code=403,
                detail={"status": "error", "code": 403, "message": "Only SELECT allowed"}
            )

    if not (q_upper.startswith("SELECT") or q_upper.startswith("WITH")):
        raise HTTPException(
            status_code=400,
            detail={"status": "error", "code": 400, "message": "Only SELECT/WITH allowed"}
        )

    try:
        data = await run_in_executor(_execute_sql_sync, sql_query, request.limit)
        return {"status": "success", "code": 200, "query": sql_query, "row_count": len(data), "data": data}
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("execute_sql error")
        raise HTTPException(
            status_code=500,
            detail={"status": "error", "code": 500, "message": "SQL Query error", "error_details": str(e)[:120]}
        )


# FIX: async, thread-pool dispatch, safe temp-file handling
@app.post("/json_to_hudi_pipeline", status_code=status.HTTP_201_CREATED)
async def json_to_hudi_pipeline(request: JSONToHudiRequest):
    # Parse JSON eagerly in the async thread so we fail fast before touching Spark
    try:
        payload_data = json.loads(request.payload)
    except json.JSONDecodeError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"status": "error", "code": 400, "message": "Invalid JSON payload"}
        )

    # FIX: write the temp file and keep its path; Spark reads it synchronously inside the thread-pool job, so the file is guaranteed to exist for the entire duration of the Spark read. We only delete it AFTER the pipeline returns.
    
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.jsonl') as tmp:
            tmp.write(json.dumps(payload_data) + '\n')
            tmp_path = tmp.name

        def _pipeline():
            bronze_df = jsonl_to_bronze_alerts(jsonl_path=tmp_path, source_file_path="api_ingestion")
            bronze_count = bronze_df.count()
            silver_count = None
            gold_count = None

            if request.run_silver:
                silver_df = bronze_to_silver_alerts()
                silver_count = silver_df.count()

            if request.run_gold and request.run_silver:
                gold_df = silver_to_gold_alerts_scalar_only()
                gold_count = gold_df.count()

            return bronze_count, silver_count, gold_count

        # FIX: dispatch blocking pipeline to thread pool
        bronze_count, silver_count, gold_count = await run_in_executor(_pipeline)

        return {
            "status": "success",
            "code": 201,
            "message": "Pipeline executed successfully",
            "bronze_count": bronze_count,
            "silver_count": silver_count,
            "gold_count": gold_count,
            "alert_id": payload_data.get("alert_id"),
            "priority": payload_data.get("priority")
        }

    except HTTPException:
        raise

    except Exception as e:
        error_msg = str(e)
        logger.exception("json_to_hudi_pipeline error")

        if "INVALID_EXTRACT_BASE_FIELD_TYPE" in error_msg or "Can't extract a value from" in error_msg:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={"status": "error", "code": 400,
                        "message": "Schema inference failed: Empty arrays detected in JSON payload"}
            )

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={"status": "error", "code": 500, "message": "Pipeline execution failed"}
        )

    finally:
        # FIX: delete temp file only AFTER the pipeline has fully returned,
        # guaranteeing Spark has finished reading it.
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                logger.warning(f"Could not delete temp file: {tmp_path}")


@app.post("/invalidate_schema_cache", status_code=status.HTTP_200_OK)
async def invalidate_schema_cache_endpoint():
    """FIX: Manually invalidate the schema cache after a schema migration."""
    invalidate_schema_cache()
    return {"status": "success", "message": "Schema cache invalidated"}


# ============================================================
# Run server
# ============================================================
if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("APP_PORT", "8282")), loop="asyncio")