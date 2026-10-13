# Usar uma imagem base oficial e enxuta do Python
FROM python:3.11-slim

# Evitar que o Python grave arquivos .pyc e forçar o log direto no terminal (stdout)
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Criar um usuário não-root (boa prática de cibersegurança e requisito do nosso Kyverno)
RUN adduser --disabled-password --gecos "" appuser

# Definir o diretório de trabalho
WORKDIR /app

# Copiar os arquivos de dependência e instalar
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar o código da aplicação
COPY main.py .

# Mudar a propriedade dos arquivos para o usuário não-root
RUN chown -R appuser:appuser /app

# Trocar para o usuário restrito
USER appuser

# Expor a porta que a aplicação vai rodar
EXPOSE 8000

# Comando para iniciar o servidor
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]