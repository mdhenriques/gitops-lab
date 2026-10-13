from fastapi import FastAPI
import os

app = FastAPI(title="GitOps DevSecOps API")

@app.get("/")
def read_root():
    # Retorna uma variável de ambiente que injetaremos de forma segura via AWS depois
    db_status = os.getenv("DB_CONNECTION", "Desconectado (Aguardando AWS Secrets)")
    return {"message": "GitOps operando em tempo real com AWS ECR e ArgoCD!", "db_status": db_status}

@app.get("/healthz")
def health_check():
    # Endpoint obrigatório para o Kubernetes (Liveness/Readiness probes)
    return {"status": "ok"}