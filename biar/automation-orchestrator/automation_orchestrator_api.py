from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import subprocess
import os
import json
import uvicorn
from typing import Optional
import threading
from queue import Queue
import traceback
from lakehouse_automation_pipeline import run_full_etl, get_spark_session, run_all_views, DEFAULT_WAREHOUSE_ROOT

app = FastAPI()
job_queue = Queue()
NUM_WORKERS = int(os.getenv("NUM_WORKERS", "1"))

STATE_LOCK = threading.Lock()
STATE_COND = threading.Condition(STATE_LOCK)
VIEW_BUILD_IN_PROGRESS = False
COMPLETED_TABLES = set()

APP_BASE_DIR = os.getenv("APP_BASE_DIR", os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.getenv("OUT_DIR", os.path.join(APP_BASE_DIR, "out"))

# NOTEBOOK_PATH = os.path.join(APP_BASE_DIR, "test_runner.ipynb")
NOTEBOOK_PATH = os.path.join(APP_BASE_DIR, "Tazama_Data_Lake_House.ipynb")
OUTPUT_NOTEBOOK = os.path.join(OUT_DIR, "last_run.ipynb")
OUTPUT_REQUEST = os.path.join(OUT_DIR, "last_request.json")

try:
    GLOBAL_SPARK = get_spark_session()
    print("[INIT] Spark session initialized globally")
except Exception as e:
    print("[INIT ERROR] Spark init failed, will fallback per job:", str(e))
    GLOBAL_SPARK = None

class TriggerRequest(BaseModel):
    raw_path: str
    bucket: Optional[str] = ""
    table: Optional[str] = ""
    object_key: Optional[str] = ""
    execute_notebook: Optional[bool] = False

@app.get("/health")
def health():
    with STATE_LOCK:
        return {
            "status": "ok",
            "num_workers": NUM_WORKERS,
            "view_build_in_progress": VIEW_BUILD_IN_PROGRESS,
            "completed_tables": sorted(COMPLETED_TABLES),
        }


def maybe_run_views_after_full_pipeline():
    global VIEW_BUILD_IN_PROGRESS

    with STATE_COND:
        if VIEW_BUILD_IN_PROGRESS:
            return

        # Only run views when the current queue batch is fully drained.
        if job_queue.unfinished_tasks != 0:
            return

        # If nothing succeeded in this drained batch, don't waste time building views.
        if not COMPLETED_TABLES:
            return

        VIEW_BUILD_IN_PROGRESS = True

    try:
        spark = GLOBAL_SPARK if GLOBAL_SPARK else get_spark_session()
        run_all_views(spark, DEFAULT_WAREHOUSE_ROOT)
    finally:
        with STATE_COND:
            VIEW_BUILD_IN_PROGRESS = False
            COMPLETED_TABLES.clear()
            STATE_COND.notify_all()

def run_job(req):
    # ======================================================
    # OPTION 1: NOTEBOOK (Papermill)
    # ======================================================

    # cmd = [
    #     "papermill",
    #     NOTEBOOK_PATH,
    #     OUTPUT_NOTEBOOK,
    #     "-k", "spark",
    #     "-p", "raw_path", req.raw_path,
    #     "-p", "bucket", req.bucket or "",
    #     "-p", "table", req.table or "",
    #     "-p", "object_key", req.object_key or "",
    # ]

    # proc = subprocess.Popen(cmd)

    # return {
    #     "status": "notebook_running",
    #     "pid": proc.pid,
    #     "output_notebook": OUTPUT_NOTEBOOK
    # }

    # ======================================================
    # OPTION 2: PYTHON FUNCTION
    # ======================================================

    print(f"[JOB] Starting ETL for: {req.raw_path}")

    spark = GLOBAL_SPARK if GLOBAL_SPARK else get_spark_session()

    result = run_full_etl(
        spark=spark,
        raw_path=req.raw_path,
        bucket=req.bucket,
        table=req.table,
        object_key=req.object_key
    )

    print(f"[JOB] Completed ETL for: {req.raw_path}")
    
    return {
        "status": "python_running",
        "result": result
    }

# ======================================================
# BACKGROUND THREAD WRAPPER
# ======================================================

def worker(worker_id):
    print(f"[WORKER-{worker_id}] Started")
    while True:
        req = job_queue.get()
        print(f"[WORKER-{worker_id}] Picked job: {req.raw_path}")

        # Do not start new ETL work while views are being built.
        with STATE_COND:
            while VIEW_BUILD_IN_PROGRESS:
                STATE_COND.wait()

        try:
            print(f"[WORKER-{worker_id}] Processing: {req.raw_path}")
            run_job(req)
            print(f"[WORKER-{worker_id}] Done: {req.raw_path}")
            job_success = True
        except Exception as e:
            print(f"[WORKER-{worker_id} ERROR] {str(e)}")
            traceback.print_exc()
            job_success = False
        finally:
            job_queue.task_done()

            if job_success and req.table:
                with STATE_LOCK:
                    COMPLETED_TABLES.add(req.table)

            maybe_run_views_after_full_pipeline()

# ======================================================
# START MULTIPLE WORKERS
# ======================================================
for i in range(NUM_WORKERS):
    threading.Thread(target=worker, args=(i,), daemon=True).start()

# ======================================================
# MAIN ENDPOINT
# ======================================================

@app.post("/checksubmit")
def submit(req: TriggerRequest):
    os.makedirs(os.path.dirname(OUTPUT_REQUEST), exist_ok=True)

    payload = {
        "raw_path": req.raw_path,
        "bucket": req.bucket,
        "table": req.table,
        "object_key": req.object_key,
        "execute_notebook": req.execute_notebook
    }

    # Read the existing requests from last_request.json
    try:
        if os.path.exists(OUTPUT_REQUEST):
            with open(OUTPUT_REQUEST, "r") as f:
                existing_requests = json.load(f)
        else:
            existing_requests = []
    except json.JSONDecodeError:
        existing_requests = []  # In case the file is empty or corrupted

    # Append the new request to the list
    existing_requests.append(payload)

    # Save request metadata
    with open(OUTPUT_REQUEST, "w") as f:
        json.dump(existing_requests, f, indent=2)

    # Only store metadata (no execution)
    if not req.execute_notebook:
        return {
            "status": "received_only",
            "message": "Metadata received from NiFi and written to out folder",
            "request_file": OUTPUT_REQUEST,
            "data": payload
        }

    # RUN IN BACKGROUND (NON-BLOCKING)
    try:
        job_queue.put(req)

        print(f"[QUEUE] Added job: {req.raw_path} | Queue size: {job_queue.qsize()}")

        return {
            "status": "queued",
            "message": "ETL job added to queue",
            "raw_path": req.raw_path
        }
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ======================================================
# START SERVER
# ======================================================
if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("APP_PORT", "7619")), loop="asyncio")