import os
import logging
import json
import time
from fastapi import FastAPI, Response, status
from prometheus_fastapi_instrumentator import Instrumentator

# Configuração de Logs Estruturados (Formato JSON para observabilidade)
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
    description="API de Produção com Observabilidade Prometheus e Práticas DevSecOps",
    version="1.1.0"
)

# Instrumentação nativa para expor métricas no padrão Prometheus (/metrics)
Instrumentator().instrument(app).expose(app)

@app.get("/")
def read_root():
    db_status = os.getenv("DB_CONNECTION")
    configured = bool(db_status and db_status != "Desconectado")
    
    logger.info("Requisição processada com sucesso no endpoint raiz.")
    return {
        "message": "GitOps operando em tempo real com AWS ECR, ArgoCD e Observabilidade!",
        "database_configured": configured,
        "db_status": db_status if db_status else "Desconectado (Aguardando AWS Secrets)"
    }

@app.get("/healthz")
def health_check(response: Response):
    """
    Probe inteligente de saúde (Readiness/Liveness).
    Garante que o pod só recebe tráfego se os segredos essenciais foram injetados.
    """
    db_status = os.getenv("DB_CONNECTION")
    if not db_status or db_status.startswith("Desconectado"):
        logger.warning("Falha na checagem de saúde: segredos da AWS não encontrados.")
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "unhealthy", "reason": "DB_CONNECTION secret not injected"}
    
    return {"status": "healthy", "service": "api"}