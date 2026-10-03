"""Check that the R2 credentials in lib/core/config/app_secrets.dart work.

Worth running after rotating credentials and BEFORE kicking off a ~2 hour
release build — it tells you in seconds whether the keys authenticate.

Reads the values straight out of app_secrets.dart, so it verifies the file that
actually ships rather than a copy. The round trip is self-cleaning: it writes
under a `diagnostics/` prefix and deletes what it wrote.

    python -m venv <somewhere>
    <somewhere>/Scripts/python.exe -m pip install boto3
    <somewhere>/Scripts/python.exe verify_r2.py

Exits 0 when every step passes, 1 otherwise, so it can gate a build.
"""

import re
import sys
from pathlib import Path

import boto3
from botocore.config import Config

SECRETS = (
    Path(__file__).resolve().parent / "lib" / "core" / "config" / "app_secrets.dart"
)


def read_secrets() -> dict[str, str]:
    text = SECRETS.read_text(encoding="utf-8")

    def val(name: str) -> str:
        match = re.search(rf"static const String {name}\s*=\s*'([^']*)'", text)
        if not match:
            sys.exit(f"could not find {name} in {SECRETS}")
        return match.group(1)

    return {
        "account": val("r2AccountId"),
        "access_key": val("r2AccessKeyId"),
        "secret_key": val("r2SecretAccessKey"),
        "bucket": val("r2BucketName"),
        "endpoint": val("r2EndpointUrl"),
    }


def main() -> int:
    cfg = read_secrets()

    print(f"endpoint  = {cfg['endpoint']}")
    print(f"bucket    = {cfg['bucket']}")
    print(
        f"accessKey = {cfg['access_key'][:8]}...{cfg['access_key'][-4:]}"
        f" ({len(cfg['access_key'])} chars)"
    )
    print(f"secretKey = {len(cfg['secret_key'])} chars")
    print()

    client = boto3.client(
        "s3",
        endpoint_url=cfg["endpoint"],
        aws_access_key_id=cfg["access_key"],
        aws_secret_access_key=cfg["secret_key"],
        # R2 is not a real AWS region; signing with anything else yields
        # SignatureDoesNotMatch. Path style for the same reason R2Config uses it.
        region_name="auto",
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
    )

    key = "diagnostics/imo-live-credential-check.txt"
    payload = b"imo-live r2 credential check\n"
    results: list[bool] = []

    def step(name: str, fn) -> None:
        try:
            print(f"PASS  {name}  ({fn()})")
            results.append(True)
        except Exception as exc:  # noqa: BLE001 - surfacing the failure is the point
            print(f"FAIL  {name}  -> {type(exc).__name__}: {exc}")
            results.append(False)

    def head():
        client.head_bucket(Bucket=cfg["bucket"])
        return "authenticated, bucket reachable"

    def put():
        client.put_object(
            Bucket=cfg["bucket"], Key=key, Body=payload, ContentType="text/plain"
        )
        return f"wrote {key}"

    def get():
        body = client.get_object(Bucket=cfg["bucket"], Key=key)["Body"].read()
        if body != payload:
            raise ValueError("content mismatch on read-back")
        return "read back, content matches"

    def cleanup():
        client.delete_object(Bucket=cfg["bucket"], Key=key)
        return "test object removed"

    step("HeadBucket   (authenticate)", head)
    step("PutObject    (write)", put)
    step("GetObject    (read)", get)
    step("DeleteObject (cleanup)", cleanup)

    failed = results.count(False)
    print()
    print("RESULT:", "ALL PASS" if failed == 0 else f"{failed} of {len(results)} FAILED")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
