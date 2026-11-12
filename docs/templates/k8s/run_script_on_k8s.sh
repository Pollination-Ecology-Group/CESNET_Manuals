#!/usr/bin/env bash
# ==============================================================================
# run_script_on_k8s.sh — One-Command Launcher for R or Python Scripts on CESNET
# ==============================================================================
# Automatically packages a local .R or .py script into a Kubernetes ConfigMap,
# submits a CERIT-SC compliant Job with S3 credentials injected, and streams
# the live output logs to your terminal.
#
# Usage:
#   ./run_script_on_k8s.sh <path/to/script.R|script.py> [--gpu] [--cpu 4] [--mem 12Gi]
#
# Examples:
#   ./run_script_on_k8s.sh my_simulation.R
#   ./run_script_on_k8s.sh train_yolo.py --gpu
#   ./run_script_on_k8s.sh heavy_model.R --cpu 8 --mem 32Gi
# ==============================================================================

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <script.R|script.py> [--gpu] [--cpu N] [--mem SIZE] [--namespace NS]"
    exit 1
fi

SCRIPT_PATH="$1"
shift

if [[ ! -f "${SCRIPT_PATH}" ]]; then
    echo "Error: Script file '${SCRIPT_PATH}' not found."
    exit 1
fi

NAMESPACE="${K8S_NAMESPACE:-stenc-ns}"
USE_GPU="false"
CPU_REQ="4"
CPU_LIM="8"
MEM_REQ="8Gi"
MEM_LIM="16Gi"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --gpu)
            USE_GPU="true"
            shift
            ;;
        --cpu)
            CPU_REQ="$2"
            CPU_LIM="$2"
            shift 2
            ;;
        --mem)
            MEM_REQ="$2"
            MEM_LIM="$2"
            shift 2
            ;;
        --namespace|-n)
            NAMESPACE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

SCRIPT_FILENAME="$(basename "${SCRIPT_PATH}")"
EXTENSION="${SCRIPT_FILENAME##*.}"
SAFE_NAME="$(echo "${SCRIPT_FILENAME%.*}" | tr '[:upper:]_' '[:lower:]-' | tr -cd 'a-z0-9-')"
JOB_NAME="run-${SAFE_NAME}"
CM_NAME="cm-${SAFE_NAME}"

if [[ "${EXTENSION}" == "R" || "${EXTENSION}" == "r" ]]; then
    IMAGE="rocker/tidyverse:4.4.1"
    RUN_CMD="mkdir -p /app/workspace /app/R_libs && export HOME=/app R_LIBS_USER=/app/R_libs && cd /app/workspace && Rscript -e 'if (!requireNamespace(\"aws.s3\", quietly=TRUE)) install.packages(\"aws.s3\", repos=\"https://cloud.r-project.org\", lib=Sys.getenv(\"R_LIBS_USER\"))' && Rscript /scripts/${SCRIPT_FILENAME}"
elif [[ "${EXTENSION}" == "py" ]]; then
    if [[ "${USE_GPU}" == "true" ]]; then
        IMAGE="ultralytics/ultralytics:latest"
    else
        IMAGE="python:3.12-slim"
    fi
    RUN_CMD="mkdir -p /app/workspace && export HOME=/app PATH=/app/.local/bin:\$PATH && cd /app/workspace && pip install --user --quiet --no-warn-script-location boto3 awscli pandas numpy && python3 -u /scripts/${SCRIPT_FILENAME}"
else
    echo "Error: Unsupported file extension '.${EXTENSION}'. Please provide a .R or .py script."
    exit 1
fi

echo "============================================================"
echo "1. Uploading '${SCRIPT_FILENAME}' to ConfigMap '${CM_NAME}' in namespace '${NAMESPACE}'..."
kubectl create configmap "${CM_NAME}" -n "${NAMESPACE}" \
    --from-file="${SCRIPT_FILENAME}=${SCRIPT_PATH}" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "2. Removing any previous Job named '${JOB_NAME}'..."
kubectl delete job "${JOB_NAME}" -n "${NAMESPACE}" --ignore-not-found >/dev/null

GPU_RESOURCE_REQ=""
GPU_RESOURCE_LIM=""
if [[ "${USE_GPU}" == "true" ]]; then
    GPU_RESOURCE_REQ='nvidia.com/gpu: "1"'
    GPU_RESOURCE_LIM='nvidia.com/gpu: "1"'
fi

echo "3. Submitting Job '${JOB_NAME}' (Image: ${IMAGE}, CPU: ${CPU_LIM}, RAM: ${MEM_LIM}, GPU: ${USE_GPU})..."
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: runner
        image: ${IMAGE}
        workingDir: /app/workspace
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
        command: ["sh", "-c", "${RUN_CMD}"]
        env:
        - name: HOME
          value: "/app"
        - name: PYTHONUNBUFFERED
          value: "1"
        - name: S3_ENDPOINT
          value: "https://s3.cl4.du.cesnet.cz"
        - name: AWS_S3_ENDPOINT
          value: "s3.cl4.du.cesnet.cz"
        - name: AWS_DEFAULT_REGION
          value: ""
        - name: S3_BUCKET
          value: "peg-bucket"
        - name: AWS_ACCESS_KEY_ID
          valueFrom:
            secretKeyRef:
              name: s3-credentials
              key: access-key
        - name: AWS_SECRET_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: s3-credentials
              key: secret-key
        resources:
          requests:
            cpu: "${CPU_REQ}"
            memory: "${MEM_REQ}"
            ${GPU_RESOURCE_REQ}
          limits:
            cpu: "${CPU_LIM}"
            memory: "${MEM_LIM}"
            ${GPU_RESOURCE_LIM}
        volumeMounts:
        - name: dshm
          mountPath: /dev/shm
        - name: scripts-vol
          mountPath: /scripts
          readOnly: true
        - name: app-vol
          mountPath: /app
      volumes:
      - name: dshm
        emptyDir:
          medium: Memory
          sizeLimit: 4Gi
      - name: scripts-vol
        configMap:
          name: ${CM_NAME}
      - name: app-vol
        emptyDir: {}
EOF

echo "============================================================"
echo "Job '${JOB_NAME}' submitted!"
echo "Waiting for Pod to start (press Ctrl+C at any time; the job will keep running on the cluster)..."
kubectl wait --for=condition=Ready pod -l job-name="${JOB_NAME}" -n "${NAMESPACE}" --timeout=120s || true
echo "--- Streaming live logs (Ctrl+C to detach) ---"
kubectl logs -f "job/${JOB_NAME}" -n "${NAMESPACE}"

