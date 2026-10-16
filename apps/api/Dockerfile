# Use official lightweight Python base image
FROM python:3.11-slim

# Prevent Python from writing .pyc files and force unbuffered stdout/stderr logging
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Create non-root user with explicit numeric UID (CIS Benchmark best practice)
RUN adduser --disabled-password --gecos "" --uid 10001 appuser

# Set working directory
WORKDIR /app

# Copy dependency files and install
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code with direct ownership
COPY --chown=appuser:appuser main.py .

# Switch to restricted user by numeric UID
USER 10001

# Expose application port
EXPOSE 8000

# Command to start the server
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]