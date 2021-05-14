FROM crystallang/crystal:latest-alpine

WORKDIR /build
COPY . .
RUN [ "shards", "install", "--ignore-crystal-version" ]

CMD [ "shards", "build", "--release", "--static", "--no-debug", "--production" ]
