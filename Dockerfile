# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization (production-ready)
#
#   Stage 1 `builder`: cài dependency vào một virtualenv riêng (/opt/venv).
#   Stage 2 `runtime`: chỉ copy venv + source sang image slim sạch,
#                      chạy bằng user thường, có HEALTHCHECK, đọc $PORT.
#
# Build:  docker build -t day12-agent:prod .
# Chạy:   docker run --env-file .env -p 8000:8000 day12-agent:prod
# ═══════════════════════════════════════════════════════════════════

# ─── Stage 1: builder ──────────────────────────────────────────────
FROM python:3.11-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Chỉ copy requirements.txt trước → layer cài thư viện được cache,
# sửa code không làm pip install chạy lại.
COPY requirements.txt .
RUN pip install -r requirements.txt

# ─── Stage 2: runtime ──────────────────────────────────────────────
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    PORT=8000

# User thường, không có shell đăng nhập, không có quyền root
RUN groupadd --system app && useradd --system --gid app --no-create-home app

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --chown=app:app app/ ./app/
COPY --chown=app:app utils/ ./utils/

USER app

EXPOSE 8000

# Image slim không có curl → dùng Python có sẵn để gọi /health
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen(f'http://127.0.0.1:{os.environ.get(\"PORT\", \"8000\")}/health', timeout=3)" || exit 1

# `exec` để uvicorn thành PID 1 và nhận thẳng SIGTERM (graceful shutdown).
# Dạng shell để $PORT do platform cấp được thay giá trị lúc chạy.
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
