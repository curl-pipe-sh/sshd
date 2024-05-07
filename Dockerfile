FROM alpine

RUN adduser -D pschmitt && \
    apk add --no-cache sudo && \
    echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel && \
    addgroup pschmitt wheel && \
    mkdir -p /app

USER pschmitt

WORKDIR /app
