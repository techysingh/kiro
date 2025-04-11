FROM debian:bookworm-slim as builder

RUN apt-get update && apt-get install -y \
    build-essential \
    libssl-dev \
    liblzo2-dev \
    libpam0g-dev \
    libpkcs11-helper1-dev \
    git \
    && git clone https://github.com/OpenVPN/openvpn.git \
    && cd openvpn \
    && git checkout v2.6.6 \
    && ./configure \
    && make \
    && make install

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    openssl \
    liblzo2-2 \
    libpam0g \
    libpkcs11-helper1 \
    iptables \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/sbin/openvpn /usr/local/sbin/openvpn

ENTRYPOINT ["openvpn"]
