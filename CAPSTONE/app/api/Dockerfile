# Capstone API tier: Flask app served by gunicorn on port 8000.
FROM python:3.12-slim

# Don't write .pyc files; flush logs straight to `kubectl logs`.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=1.0.0

WORKDIR /app

# Dependencies first, so code changes don't re-run pip (layer caching).
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Run as a fixed non-root UID. Day 11's "restricted" Pod Security
# profile will require this, so the image is ready for it from day one.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin app
USER 10001

EXPOSE 8000
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--access-logfile", "-", "app:app"]
