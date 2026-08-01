FROM python:3.12-alpine
WORKDIR /app
COPY server.py /app/server.py
RUN addgroup -S termvault && adduser -S termvault -G termvault && mkdir /data && chown termvault:termvault /data
USER termvault
ENV PORT=8791 TERMVAULT_DB=/data/termvault.sqlite3
EXPOSE 8791
CMD ["python", "/app/server.py"]
