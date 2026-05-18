FROM ubuntu:25.04

# BuildKit auto-populates TARGETARCH (amd64/arm64/arm). We pass it through
# unchanged to the container; start.sh does the Azure platform mapping.
ARG TARGETARCH
ENV TARGETARCH=${TARGETARCH:-amd64}

ENV DEBIAN_FRONTEND=noninteractive
RUN echo 'APT::Get::Assume-Yes "true";' > /etc/apt/apt.conf.d/90assumeyes

RUN apt update && apt install -y --no-install-recommends \
      ca-certificates curl file jq git iputils-ping \
      libcurl4 libicu76 libunwind-14 netcat-traditional libssl3 \
  && rm -rf /var/lib/apt/lists/*

RUN curl -LsS https://aka.ms/InstallAzureCLIDeb | bash \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p -m 755 /etc/apt/keyrings \
  && curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key \
        | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
  && echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' \
        > /etc/apt/sources.list.d/kubernetes.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends kubectl \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /azp
COPY ./start.sh .
RUN chmod +x start.sh

ENTRYPOINT ["./start.sh"]