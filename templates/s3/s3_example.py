#!/usr/bin/env python3
"""
s3_example.py — Reading and Writing Data on CESNET S3 Directly from Python
==========================================================================
Demonstrates how to connect to CESNET S3 (https://s3.cl4.du.cesnet.cz),
list objects, download files, read CSVs directly into pandas, and upload
results using boto3.

Prerequisites:
    pip install boto3 pandas

Credentials setup (choose one):
    1. Environment variables:
         export AWS_ACCESS_KEY_ID="your_access_key"
         export AWS_SECRET_ACCESS_KEY="your_secret_key"
    2. Or ~/.passwd-s3fs file (formatted as ACCESS_KEY:SECRET_KEY)
    3. Or inside a CESNET Kubernetes Pod using the 's3-credentials' Secret
"""

import io
import os
from pathlib import Path
import boto3
from botocore.config import Config
import pandas as pd

S3_ENDPOINT = os.environ.get("S3_ENDPOINT", "https://s3.cl4.du.cesnet.cz")
S3_BUCKET = os.environ.get("S3_BUCKET", "peg-bucket")


def get_s3_client():
    """Creates an authenticated boto3 S3 client for CESNET Object Storage."""
    access_key = os.environ.get("AWS_ACCESS_KEY_ID")
    secret_key = os.environ.get("AWS_SECRET_ACCESS_KEY")

    # Fallback: read from ~/.passwd-s3fs if present locally
    passwd_s3fs = Path.home() / ".passwd-s3fs"
    if (not access_key or not secret_key) and passwd_s3fs.exists():
        content = passwd_s3fs.read_text().strip()
        if ":" in content:
            access_key, secret_key = content.split(":", 1)

    if not access_key or not secret_key:
        raise RuntimeError(
            "S3 credentials not found! Please set AWS_ACCESS_KEY_ID and "
            "AWS_SECRET_ACCESS_KEY environment variables, or create ~/.passwd-s3fs."
        )

    return boto3.client(
        "s3",
        endpoint_url=S3_ENDPOINT,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=Config(signature_version="s3v4", max_pool_connections=25),
    )


def list_prefix(prefix: str = "Ostatni/", max_keys: int = 20):
    """Lists objects in the bucket under the given prefix."""
    s3 = get_s3_client()
    resp = s3.list_objects_v2(Bucket=S3_BUCKET, Prefix=prefix, MaxKeys=max_keys)
    contents = resp.get("Contents", [])
    print(f"Found {len(contents)} objects (showing up to {max_keys}) in s3://{S3_BUCKET}/{prefix}:")
    for obj in contents:
        size_mb = obj["Size"] / (1024 * 1024)
        print(f"  - {obj['Key']} ({size_mb:.2f} MB, modified {obj['LastModified']})")
    return contents


def read_csv_from_s3(s3_key: str) -> pd.DataFrame:
    """Reads a CSV file directly from S3 into a pandas DataFrame without saving to disk."""
    s3 = get_s3_client()
    obj = s3.get_object(Bucket=S3_BUCKET, Key=s3_key)
    return pd.read_csv(io.BytesIO(obj["Body"].read()))


def upload_dataframe_to_s3(df: pd.DataFrame, s3_key: str):
    """Uploads a pandas DataFrame directly to S3 as a CSV file."""
    s3 = get_s3_client()
    csv_bytes = df.to_csv(index=False).encode("utf-8")
    s3.put_object(Bucket=S3_BUCKET, Key=s3_key, Body=csv_bytes, ContentType="text/csv")
    print(f"Uploaded DataFrame ({len(df)} rows) to s3://{S3_BUCKET}/{s3_key}")


def download_file(s3_key: str, local_path: str):
    """Downloads a single file from S3 to a local path."""
    s3 = get_s3_client()
    Path(local_path).parent.mkdir(parents=True, exist_ok=True)
    s3.download_file(S3_BUCKET, s3_key, local_path)
    print(f"Downloaded s3://{S3_BUCKET}/{s3_key} -> {local_path}")


def upload_file(local_path: str, s3_key: str):
    """Uploads a local file to S3."""
    s3 = get_s3_client()
    s3.upload_file(local_path, S3_BUCKET, s3_key)
    print(f"Uploaded {local_path} -> s3://{S3_BUCKET}/{s3_key}")


if __name__ == "__main__":
    list_prefix(prefix="Ostatni/", max_keys=15)

