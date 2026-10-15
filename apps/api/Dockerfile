# Usar uma imagem base oficial e enxuta do Python
FROM python:3.11-slim

# Evitar que o Python grave arquivos .pyc e forçar o log direto no terminal (stdout)
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Criar um usuário não-root com UID numérico explícito (boa prática CIS Benchmark)
RUN adduser --disabled-password --gecos "" --uid 10001 appuser

# Definir o diretório de trabalho
WORKDIR /app

# Copiar os arquivos de dependência e instalar
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar o código da aplicação com ownership direto
COPY --chown=appuser:appuser main.py .

# Trocar para o usuário restrito pelo UID numérico
USER 10001

# Expor a porta que a aplicação vai rodar
EXPOSE 8000

# Comando para iniciar o servidor
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]