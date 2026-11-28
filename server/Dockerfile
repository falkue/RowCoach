# Container des Rennen-Servers (Cloud-Run-Jobs rowcoach-tick und rowcoach-aggregate), docs/MULTIPLAYER.md
# „Server (Blaze)“. Bauen im Repo-Wurzelordner (Kontext braucht App/RowCoachKit und den Pool):
#   docker build -f server/Dockerfile -t europe-west1-docker.pkg.dev/<projekt>/rowcoach/server:latest .
FROM swift:6.1-noble AS build
WORKDIR /src
COPY App/RowCoachKit App/RowCoachKit
COPY server server
RUN cd server && swift build -c release --static-swift-stdlib \
    && cp "$(swift build -c release --show-bin-path)/rowcoach-server" /rowcoach-server

FROM ubuntu:noble
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libcurl4 libxml2 tzdata \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /rowcoach-server /app/rowcoach-server
COPY App/RowCoach/Resources/virtual-rowers-v1.bin /app/virtual-rowers-v1.bin
ENV ROWCOACH_POOL=/app/virtual-rowers-v1.bin
ENTRYPOINT ["/app/rowcoach-server"]
CMD ["tick"]
