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
    
    logger.info("Requisicao processada com sucesso no endpoint raiz.")
    return {
        "message": "GitOps operando em tempo real com AWS ECR, ArgoCD e Observabilidade!",
        "database_configured": configured,
        "db_status": "Conectado com sucesso (Injetado via AWS SSM Parameter Store)" if configured else "Desconectado (Aguardando AWS Secrets)"
    }

@app.get("/healthz")
def liveness():
    """
    Liveness Probe: Valida se o processo e event-loop da aplicacao estao vivos.
    Se falhar, o Kubernetes reinicia o container para recuperar de deadlocks.
    """
    return {"status": "alive"}

@app.get("/readyz")
def readiness(response: Response):
    """
    Readiness Probe: Valida se a aplicacao esta pronta para receber trafego.
    Verifica se configuracoes essenciais e conexoes foram injetadas.
    Se falhar, o Kubernetes apenas remove o pod dos endpoints de trafego (sem reiniciar).
    """
    db_status = os.getenv("DB_CONNECTION")
    if not db_status or db_status.startswith("Desconectado"):
        logger.warning("Readiness probe falhou: DB_CONNECTION ausente ou desconectado.")
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "not_ready", "reason": "DB_CONNECTION not configured"}
    
    return {"status": "ready"}