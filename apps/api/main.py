import os
import logging
import json
import time
from fastapi import FastAPI, Response, status
from prometheus_fastapi_instrumentator import Instrumentator

# Structured Logs (JSON format for observability)
class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_record = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(record.created)),
            "level": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }
        return json.dumps(log_record)

logger = logging.getLogger("api")
logger.setLevel(logging.INFO)
handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logger.handlers = [handler]

app = FastAPI(
    title="GitOps DevSecOps API",
    description="Production API with Prometheus for Observability and DevSecOps practices",
    version="1.1.0"
)

# Instrumentator for Prometheus metrics
Instrumentator().instrument(app).expose(app)

@app.get("/")
def read_root():
    db_status = os.getenv("DB_CONNECTION")
    configured = bool(db_status and not db_status.startswith("Disconnected") and not db_status.startswith("Desconectado"))
    
    logger.info("Request processed successfully on root endpoint.")
    return {
        "message": "GitOps operating in real time with AWS ECR, ArgoCD, and Observability!",
        "database_configured": configured,
        "db_status": "Connected successfully (Injected via AWS SSM Parameter Store)" if configured else "Disconnected (Awaiting AWS Secrets)"
    }

@app.get("/healthz")
def liveness():
    """
    Liveness Probe: Verifies that the application process and event loop are alive.
    If it fails, Kubernetes restarts the container to recover from deadlocks.
    """
    return {"status": "alive"}

@app.get("/readyz")
def readiness(response: Response):
    """
    Readiness Probe: Verifies that the application is ready to accept user traffic.
    Validates that essential configurations and connections have been injected.
    If it fails, Kubernetes removes the pod from Service traffic endpoints without restarting.
    """
    db_status = os.getenv("DB_CONNECTION")
    if not db_status or db_status.startswith("Disconnected") or db_status.startswith("Desconectado"):
        logger.warning("Readiness probe failed: DB_CONNECTION missing or disconnected.")
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "not_ready", "reason": "DB_CONNECTION not configured"}
    
    return {"status": "ready"}