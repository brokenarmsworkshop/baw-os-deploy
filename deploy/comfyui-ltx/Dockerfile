# syntax=docker/dockerfile:1.7

FROM python:3.12-slim-bookworm

ARG COMFYUI_VERSION=v0.24.0
ARG TORCH_VERSION=2.11.0
ARG TORCHVISION_VERSION=0.26.0
ARG TORCHAUDIO_VERSION=2.11.0

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        ffmpeg \
        libgl1 \
        libglib2.0-0 \
        libgomp1 \
        tini \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

# Archive de version immuable : évite le clone Git et le checkout ambigus.
RUN set -eux; \
    curl --fail --location --retry 5 --retry-delay 3 \
      "https://github.com/Comfy-Org/ComfyUI/archive/refs/tags/${COMFYUI_VERSION}.tar.gz" \
      --output /tmp/comfyui.tar.gz; \
    tar -xzf /tmp/comfyui.tar.gz -C /opt; \
    mv "/opt/ComfyUI-${COMFYUI_VERSION#v}" /opt/ComfyUI; \
    rm /tmp/comfyui.tar.gz; \
    test -f /opt/ComfyUI/main.py; \
    test -f /opt/ComfyUI/requirements.txt

RUN python -m pip install --upgrade pip setuptools wheel

# Versions CUDA 12.6 explicitement épinglées.
RUN python -m pip install \
      "torch==${TORCH_VERSION}" \
      "torchvision==${TORCHVISION_VERSION}" \
      "torchaudio==${TORCHAUDIO_VERSION}" \
      --index-url https://download.pytorch.org/whl/cu126

WORKDIR /opt/ComfyUI

# Évite que requirements.txt remplace les roues PyTorch CUDA épinglées.
RUN set -eux; \
    sed -E '/^(torch|torchvision|torchaudio)([<>= ].*)?$/d' requirements.txt > /tmp/requirements-comfyui.txt; \
    python -m pip install -r /tmp/requirements-comfyui.txt; \
    rm /tmp/requirements-comfyui.txt

# Échec immédiat du build si PyTorch n’est pas bien compilé avec CUDA.
RUN python - <<'PYTORCH'
import torch
print('Torch:', torch.__version__)
print('CUDA runtime PyTorch:', torch.version.cuda)
assert torch.version.cuda == '12.6', torch.version.cuda
PYTORCH

EXPOSE 8188

HEALTHCHECK --interval=15s --timeout=5s --start-period=90s --retries=10 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8188/system_stats', timeout=4)" || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188", "--lowvram", "--reserve-vram", "1.5", "--preview-method", "none"]
