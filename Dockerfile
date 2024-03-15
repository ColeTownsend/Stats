# Use cargo-chef to cache dependencies, speeding up builds significantly
FROM lukemathwalker/cargo-chef:latest-rust-1 AS chef
WORKDIR /app

FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
COPY --from=planner /app/recipe.json recipe.json
# Build dependencies first to cache them
RUN cargo chef cook --release --recipe-path recipe.json
# Build the actual application
COPY . .
RUN cargo build --release --bin stats

# Build diesel CLI for running migrations
FROM rust AS diesel-builder
RUN apt update && \
  apt install -y libsqlite3-dev && \
  rm -rf /var/lib/apt/lists/*
WORKDIR /app

RUN cargo install diesel_cli --no-default-features --features sqlite --root /app

# The final image starts here
FROM debian:bookworm-slim AS runtime
WORKDIR /app

# Environment variables for your application
ENV APP_URL=https://stats-api.fly.dev:8080
ENV SERVICE_PORT=8080
ENV DATABASE_URL=/app/data/stats.sqlite
ENV PROCESSING_BATCH_SIZE=500
ENV CORS_DOMAINS=https://stats-api.fly.dev,https://www.twnsnd.co


RUN apt update && \
  apt install -y libsqlite3-0 && \
  rm -rf /var/lib/apt/lists/*

# Copy necessary files to /data
WORKDIR /app

# Add GeoLite2-City.mmdb and cities5000.txt directly from the web sources
ADD https://git.io/GeoLite2-City.mmdb /app/data/GeoLite2-City.mmdb
ADD https://github.com/PrismaPhonic/filter-cities-by-country/raw/master/cities5000.txt /app/data/cities5000.txt

# Copy necessary files and binaries from previous stages
COPY migrations/ /app/migrations
COPY ui/ /app/ui
COPY --from=diesel-builder /app/bin/diesel /app
COPY --from=builder /app/target/release/stats /app
COPY --chmod=0755 docker-entrypoint.sh /app

# Copy your entrypoint script into the image and make sure it's executable
COPY docker-entrypoint.sh /app
RUN chmod +x /app/docker-entrypoint.sh

# Set the PATH to include the app directory
ENV PATH="/app:${PATH}"

ENTRYPOINT ["/app/docker-entrypoint.sh"]
