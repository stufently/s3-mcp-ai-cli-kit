FROM golang:1.27.2 AS build
ARG VERSION=0.1.0
ARG COMMIT=dev
ARG BUILD_UID=65532
ARG BUILD_GID=65532
ENV HOME=/tmp GOCACHE=/tmp/go-cache GOMODCACHE=/tmp/go-mod-cache
WORKDIR /src
COPY --chown=${BUILD_UID}:${BUILD_GID} go.mod go.sum ./
USER ${BUILD_UID}:${BUILD_GID}
RUN go mod download
COPY --chown=${BUILD_UID}:${BUILD_GID} . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.version=$VERSION -X main.commit=$COMMIT" -o /tmp/@@BINARY@@ ./cmd/@@BINARY@@
FROM scratch
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build /tmp/@@BINARY@@ /@@BINARY@@
# Introspection placeholder only. Real keys are passed with -e and override it.
ENV @@ENV_PREFIX@@ACCESS_KEY_ID=introspection-placeholder-not-a-key
ENV @@ENV_PREFIX@@SECRET_ACCESS_KEY=introspection-placeholder-not-a-key
LABEL io.modelcontextprotocol.server.name="@@SERVER_NAME@@"
LABEL org.opencontainers.image.source="https://github.com/stufently/@@REPO@@"
USER 65532:65532
ENTRYPOINT ["/@@BINARY@@"]
CMD ["mcp"]
