FROM ubuntu:24.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-aiohttp python3-requests curl && \
    apt-get clean
