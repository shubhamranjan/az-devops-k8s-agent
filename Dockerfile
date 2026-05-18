FROM ubuntu:25.04

  # Map BuildKit's TARGETARCH (amd64/arm64/…) → Azure's platform naming
  # (linux-x64/linux-arm64/…) and persist it so start.sh sees it at runtime.
  # Default to amd64 for non-BuildKit builds.
  ARG TARGETARCH=amd64
  ENV TARGETARCH=linux-${TARGETARCH/amd64/x64}

  ENV DEBIAN_FRONTEND=noninteractive
  RUN echo "APT::Get::Assume-Yes \"true\";" > /etc/apt/apt.conf.d/90assumeyes

  RUN apt update && apt install -y --no-install-recommends \
      ca-certificates \
      curl \
      file \
      jq \
      git \
      iputils-ping \
      libcurl4 \
      libicu76 \
      libunwind-14 \
      netcat-traditional \
      libssl3 \
    && rm -rf /var/lib/apt/lists/*

  RUN curl -LsS https://aka.ms/InstallAzureCLIDeb | bash \
    && rm -rf /var/lib/apt/lists/*

  # Install kubectl
  RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
      echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

  RUN apt-get update && apt-get install -y --no-install-recommends \
      kubectl \
    && rm -rf /var/lib/apt/lists/*

  WORKDIR /azp

  COPY ./start.sh .
  RUN chmod +x start.sh

  ENTRYPOINT ["./start.sh"]