import os
import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_read_root_default(monkeypatch):
    """Verifies default response from root endpoint when DB_CONNECTION is not configured."""
    monkeypatch.delenv("DB_CONNECTION", raising=False)
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["database_configured"] is False
    assert "Disconnected" in data["db_status"]

def test_read_root_configured(monkeypatch):
    """Verifies response from root endpoint when DB_CONNECTION is injected by Kubernetes."""
    monkeypatch.setenv("DB_CONNECTION", "postgresql://admin:secret@localhost:5432/db")
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["database_configured"] is True
    assert "Connected successfully" in data["db_status"]

def test_liveness_probe():
    """Liveness probe must always return 200 alive while the process event loop is running."""
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "alive"}

def test_readiness_probe_fails_without_secret(monkeypatch):
    """Readiness probe must return 503 when the database credential has not been injected."""
    monkeypatch.delenv("DB_CONNECTION", raising=False)
    response = client.get("/readyz")
    assert response.status_code == 503
    data = response.json()
    assert data["status"] == "not_ready"
    assert "reason" in data

def test_readiness_probe_succeeds_with_secret(monkeypatch):
    """Readiness probe must return 200 ready when credentials are properly injected."""
    monkeypatch.setenv("DB_CONNECTION", "postgresql://user:pass@host:5432/db")
    response = client.get("/readyz")
    assert response.status_code == 200
    assert response.json() == {"status": "ready"}

def test_metrics_endpoint():
    """Verifies that the Prometheus endpoint exposes FastAPI runtime metrics."""
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "http_requests" in response.text or "process_cpu_seconds" in response.text
