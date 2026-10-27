# ---------------------------------------------------------------- build
# Instala as dependencias num venv isolado; pip e cache ficam neste estagio.
FROM python:3.12-alpine AS build

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir --no-compile -r requirements.txt \
 && pip uninstall -y pip \
 && find /opt/venv -name '__pycache__' -prune -exec rm -rf {} +

# ---------------------------------------------------------------- final
FROM python:3.12-alpine

RUN addgroup -S loja && adduser -S -G loja -H loja

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    SQLITE_PATH=/dados/loja.db

COPY --from=build /opt/venv /opt/venv

WORKDIR /app
COPY app/ app/
COPY static/ static/

# Diretorio gravavel para o SQLite; o codigo continua de root (somente leitura)
RUN mkdir /dados && chown loja:loja /dados
USER loja

EXPOSE 8000

# busybox wget ja vem no Alpine: nada a instalar para o healthcheck
HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8000/health || exit 1

# Forma exec: uvicorn e o PID 1 e recebe o SIGTERM do docker stop
CMD ["uvicorn", "app:api", "--host", "0.0.0.0", "--port", "8000"]
