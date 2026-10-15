import os
import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_read_root_default(monkeypatch):
    """Testa resposta padrao do endpoint raiz quando DB_CONNECTION nao esta configurada."""
    monkeypatch.delenv("DB_CONNECTION", raising=False)
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["database_configured"] is False
    assert "Desconectado" in data["db_status"]

def test_read_root_configured(monkeypatch):
    """Testa resposta do endpoint raiz quando DB_CONNECTION foi injetada pelo Kubernetes."""
    monkeypatch.setenv("DB_CONNECTION", "postgresql://admin:secret@localhost:5432/db")
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["database_configured"] is True
    assert "Conectado com sucesso" in data["db_status"]

def test_liveness_probe():
    """Liveness probe deve sempre responder 200 alive enquanto o processo estiver vivo."""
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "alive"}

def test_readiness_probe_fails_without_secret(monkeypatch):
    """Readiness probe deve retornar 503 quando a credencial do DB nao foi injetada."""
    monkeypatch.delenv("DB_CONNECTION", raising=False)
    response = client.get("/readyz")
    assert response.status_code == 503
    data = response.json()
    assert data["status"] == "not_ready"
    assert "reason" in data

def test_readiness_probe_succeeds_with_secret(monkeypatch):
    """Readiness probe deve retornar 200 ready quando as credenciais estao presentes."""
    monkeypatch.setenv("DB_CONNECTION", "postgresql://user:pass@host:5432/db")
    response = client.get("/readyz")
    assert response.status_code == 200
    assert response.json() == {"status": "ready"}

def test_metrics_endpoint():
    """Valida se o endpoint do Prometheus expoe metricas do FastAPI."""
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "http_requests" in response.text or "process_cpu_seconds" in response.text
