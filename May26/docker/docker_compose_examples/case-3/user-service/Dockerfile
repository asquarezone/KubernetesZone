FROM astral/uv:python3.12-bookworm-slim
COPY . /app
WORKDIR /app
RUN uv sync
EXPOSE 8080
CMD ["uv", "run","uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]