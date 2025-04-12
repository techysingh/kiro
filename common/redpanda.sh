mkdir redpanda-quickstart && cd redpanda-quickstart && \
curl -sSL https://docs.redpanda.com/redpanda-quickstart.tar.gz | tar xzf - && \
cd docker-compose && docker compose up -d