FROM crystallang/crystal:1.1.0-alpine

WORKDIR /build
COPY . .
RUN [ "shards", "install", "--ignore-crystal-version" ]

CMD [ "shards", "build", "--release", "--static", "--no-debug", "--production" ]
