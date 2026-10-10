FROM python:3.14-slim

WORKDIR /app

COPY tools/serve_web.py /app/tools/serve_web.py
COPY build/web/ /app/build/web/

EXPOSE 8080

CMD ["python3", "/app/tools/serve_web.py", "8080", "/app/build/web"]

