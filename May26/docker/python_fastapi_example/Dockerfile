FROM python:3.12-slim
# install uv
RUN pip install --no-cache-dir uv
COPY . /app
WORKDIR /app
RUN uv sync --frozen --no-dev
EXPOSE 18000
CMD ["uv", "run", "main.py"]