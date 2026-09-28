"""Capstone API tier: a small Flask app backed by redis.

Routes
  GET /api/hits   increment and return the visit counter (the capstone's proof of life)
  GET /api/info   pod name, version and redis target, no side effects
  GET /api/cpu    burn CPU for ?ms=N milliseconds (load for the Day 09 HPA)
  GET /healthz    liveness: "is this process alive?"  Never touches redis.
  GET /ready      readiness: "can I serve traffic?"   Pings redis.

Liveness and readiness are deliberately different. If redis goes down,
every API Pod turns NotReady (taken out of the Service), but none are
restarted, because restarting the API would not fix redis.
"""
import os
import socket
import time

from flask import Flask, jsonify, request
from redis import Redis, RedisError

APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD") or None  # set from a Secret on Day 11

POD = socket.gethostname()

app = Flask(__name__)
redis = Redis(
    host=REDIS_HOST,
    port=REDIS_PORT,
    password=REDIS_PASSWORD,
    socket_connect_timeout=1,
    socket_timeout=1,
)


@app.get("/api/hits")
def hits():
    try:
        count = redis.incr("hits")
    except RedisError as exc:
        return jsonify(error=f"redis unavailable: {exc}", pod=POD), 503
    return jsonify(hits=count, pod=POD, version=APP_VERSION)


@app.get("/api/info")
def info():
    return jsonify(pod=POD, version=APP_VERSION, redis=f"{REDIS_HOST}:{REDIS_PORT}")


@app.get("/api/cpu")
def cpu():
    ms = min(int(request.args.get("ms", "100")), 2000)
    end = time.perf_counter() + ms / 1000
    n = 0
    while time.perf_counter() < end:
        n += 1
    return jsonify(pod=POD, burned_ms=ms, loops=n)


@app.get("/healthz")
def healthz():
    return "ok\n", 200


@app.get("/ready")
def ready():
    try:
        redis.ping()
    except RedisError as exc:
        return f"not ready: redis {REDIS_HOST}:{REDIS_PORT} unreachable ({exc})\n", 503
    return "ready\n", 200
