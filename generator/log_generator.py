"""
log_generator.py

Simulates a web server access log and periodically writes a batch of
JSON-lines log records to a local folder AND (optionally) uploads that
batch straight to an S3 bucket, where Snowpipe will auto-ingest it.

Usage:
    python log_generator.py --interval 30 --batch-size 50 --bucket my-log-bucket

If --bucket is omitted, files are only written locally to ./logs_out/
so you can test the generator before wiring up AWS credentials.

Requires:
    pip install faker boto3
"""

import argparse
import json
import random
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

from faker import Faker

fake = Faker()

ENDPOINTS = [
    "/", "/home", "/products", "/products/{}".format,
    "/cart", "/checkout", "/api/login", "/api/logout",
    "/api/search", "/static/app.js", "/static/style.css",
]

STATUS_WEIGHTS = [
    (200, 0.80),
    (301, 0.03),
    (404, 0.08),
    (500, 0.05),
    (503, 0.04),
]


def weighted_status():
    r = random.random()
    cumulative = 0.0
    for status, weight in STATUS_WEIGHTS:
        cumulative += weight
        if r <= cumulative:
            return status
    return 200


def random_endpoint():
    ep = random.choice(ENDPOINTS)
    if callable(ep):
        return ep(random.randint(1, 500))
    return ep


def make_log_record():
    status = weighted_status()
    return {
        "log_id": str(uuid.uuid4()),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "ip_address": fake.ipv4_public(),
        "method": random.choice(["GET", "GET", "GET", "POST", "PUT", "DELETE"]),
        "endpoint": random_endpoint(),
        "status_code": status,
        "response_time_ms": (
            random.randint(20, 250) if status < 400 else random.randint(200, 3000)
        ),
        "user_agent": fake.user_agent(),
    }


def write_batch(records, out_dir: Path) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    filename = f"logs_{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')}_{uuid.uuid4().hex[:8]}.json"
    filepath = out_dir / filename
    with open(filepath, "w") as f:
        for record in records:
            f.write(json.dumps(record) + "\n")
    return filepath


def upload_to_s3(filepath: Path, bucket: str, prefix: str = "raw/"):
    import boto3  # imported lazily so local-only mode doesn't need boto3

    s3 = boto3.client("s3")
    key = f"{prefix}{filepath.name}"
    s3.upload_file(str(filepath), bucket, key)
    print(f"  -> uploaded to s3://{bucket}/{key}")


def main():
    parser = argparse.ArgumentParser(description="Fake web log generator")
    parser.add_argument("--interval", type=int, default=30, help="Seconds between batches")
    parser.add_argument("--batch-size", type=int, default=50, help="Records per batch")
    parser.add_argument("--bucket", type=str, default=None, help="S3 bucket to upload to")
    parser.add_argument("--prefix", type=str, default="raw/", help="S3 key prefix")
    parser.add_argument("--out-dir", type=str, default="./logs_out", help="Local output folder")
    parser.add_argument("--iterations", type=int, default=0, help="0 = run forever")
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    count = 0

    print(f"Generating logs every {args.interval}s, batch size {args.batch_size}")
    print(f"Local output: {out_dir.resolve()}")
    if args.bucket:
        print(f"Uploading to: s3://{args.bucket}/{args.prefix}")
    else:
        print("No --bucket given, running in local-only mode.")

    try:
        while True:
            records = [make_log_record() for _ in range(args.batch_size)]
            filepath = write_batch(records, out_dir)
            print(f"[{datetime.now().strftime('%H:%M:%S')}] wrote {len(records)} records -> {filepath.name}")

            if args.bucket:
                upload_to_s3(filepath, args.bucket, args.prefix)

            count += 1
            if args.iterations and count >= args.iterations:
                break

            time.sleep(args.interval)

    except KeyboardInterrupt:
        print("\nStopped by user.")


if __name__ == "__main__":
    main()
