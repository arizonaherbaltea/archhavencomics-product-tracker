FROM python:3.9.12-buster

RUN    apt-get update \
    && apt-get install -y \
        curl \
        bash \
        jq \
        pandoc \
    && pip install yq \
    && jq --version \
    && yq --version

WORKDIR /usr/src/app
COPY src/ src
COPY entrypoint.sh .

ENTRYPOINT ["/bin/bash", "-c", "./entrypoint.sh"]
