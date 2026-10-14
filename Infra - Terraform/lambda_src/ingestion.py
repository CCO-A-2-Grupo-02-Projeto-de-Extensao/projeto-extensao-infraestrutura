import csv
import hashlib
import io
import json
import logging
import os
import re
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone
from urllib.parse import quote


LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)
USER_AGENT = "Arandu-FatoresExternos/1.0 (data ingestion)"
PART_SIZE = 8 * 1024 * 1024
MANIFEST_FIELDS = ("fonte", "data_coleta", "tamanho_bytes", "url", "arquivo_s3")


def _boto3():
    import boto3

    return boto3


def _request(url, method="GET", referer=None):
    headers = {"User-Agent": USER_AGENT}
    if referer:
        headers["Referer"] = referer
    return urllib.request.Request(url, headers=headers, method=method)


def _remote_metadata(url, referer=None):
    with urllib.request.urlopen(_request(url, "HEAD", referer), timeout=30) as response:
        return {
            "etag": response.headers.get("ETag", "").strip('"'),
            "last_modified": response.headers.get("Last-Modified", ""),
        }


def _version_token(metadata):
    identity = metadata.get("etag") or metadata.get("last_modified") or "current"
    return hashlib.sha256(identity.encode("utf-8")).hexdigest()[:16]


def _object_exists(s3, bucket, key):
    try:
        s3.head_object(Bucket=bucket, Key=key)
        return True
    except Exception as error:
        response = getattr(error, "response", {})
        code = response.get("Error", {}).get("Code")
        if response.get("ResponseMetadata", {}).get("HTTPStatusCode") == 404:
            return False
        if code in ("404", "NoSuchKey", "NotFound"):
            return False
        raise


def _stream_to_s3(s3, bucket, key, url, referer=None):
    request = _request(url, referer=referer)
    response = urllib.request.urlopen(request, timeout=60)
    multipart = None
    parts = []
    part_number = 1
    size = 0
    buffer = bytearray()

    try:
        multipart = s3.create_multipart_upload(Bucket=bucket, Key=key)
        upload_id = multipart["UploadId"]
        while True:
            block = response.read(1024 * 1024)
            if not block:
                break
            size += len(block)
            buffer.extend(block)
            if len(buffer) >= PART_SIZE:
                result = s3.upload_part(
                    Bucket=bucket,
                    Key=key,
                    UploadId=upload_id,
                    PartNumber=part_number,
                    Body=bytes(buffer),
                )
                parts.append({"PartNumber": part_number, "ETag": result["ETag"]})
                part_number += 1
                buffer.clear()

        if parts:
            if buffer:
                result = s3.upload_part(
                    Bucket=bucket,
                    Key=key,
                    UploadId=upload_id,
                    PartNumber=part_number,
                    Body=bytes(buffer),
                )
                parts.append({"PartNumber": part_number, "ETag": result["ETag"]})
            s3.complete_multipart_upload(
                Bucket=bucket,
                Key=key,
                UploadId=upload_id,
                MultipartUpload={"Parts": parts},
            )
        else:
            s3.abort_multipart_upload(Bucket=bucket, Key=key, UploadId=upload_id)
            multipart = None
            s3.put_object(Bucket=bucket, Key=key, Body=bytes(buffer))
        return size
    except Exception:
        if multipart is not None:
            s3.abort_multipart_upload(
                Bucket=bucket, Key=key, UploadId=multipart["UploadId"]
            )
        raise
    finally:
        response.close()


def _append_manifest(s3, dynamodb, bucket, table_name, record):
    table = dynamodb.Table(table_name)
    lock_id = "manifesto.csv"
    owner = str(uuid.uuid4())
    now = int(time.time())
    acquired = False

    for _ in range(120):
        try:
            table.put_item(
                Item={"lock_id": lock_id, "owner": owner, "expires_at": now + 120},
                ConditionExpression="attribute_not_exists(lock_id) OR expires_at < :now",
                ExpressionAttributeValues={":now": now},
            )
            acquired = True
            break
        except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
            time.sleep(0.25)
    if not acquired:
        raise TimeoutError("Nao foi possivel adquirir o lock do manifesto.csv")

    try:
        try:
            response = s3.get_object(Bucket=bucket, Key="manifesto.csv")
            existing = response["Body"].read().decode("utf-8-sig")
        except Exception as error:
            code = getattr(error, "response", {}).get("Error", {}).get("Code")
            status = getattr(error, "response", {}).get("ResponseMetadata", {}).get("HTTPStatusCode")
            if code not in ("404", "NoSuchKey", "NotFound") and status != 404:
                raise
            existing = ""
        rows = list(csv.DictReader(io.StringIO(existing))) if existing else []
        if any(row.get("arquivo_s3") == record["arquivo_s3"] for row in rows):
            return
        output = io.StringIO()
        writer = csv.DictWriter(output, fieldnames=MANIFEST_FIELDS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
        writer.writerow(record)
        s3.put_object(
            Bucket=bucket,
            Key="manifesto.csv",
            Body=output.getvalue().encode("utf-8"),
            ContentType="text/csv; charset=utf-8",
        )
    finally:
        table.delete_item(
            Key={"lock_id": lock_id},
            ConditionExpression="owner = :owner",
            ExpressionAttributeValues={":owner": owner},
        )


def _ingest(s3, dynamodb, bucket, table_name, source, url, key, referer=None):
    if not _object_exists(s3, bucket, key):
        size = _stream_to_s3(s3, bucket, key, url, referer)
        LOGGER.info("bronze_downloaded source=%s key=%s bytes=%d", source, key, size)
    else:
        size = s3.head_object(Bucket=bucket, Key=key)["ContentLength"]
        LOGGER.info("bronze_exists source=%s key=%s bytes=%d", source, key, size)

    _append_manifest(
        s3,
        dynamodb,
        bucket,
        table_name,
        {
            "fonte": source,
            "data_coleta": datetime.now(timezone.utc).isoformat(),
            "tamanho_bytes": size,
            "url": url,
            "arquivo_s3": key,
        },
    )


def inmet_handler(event, context):
    boto3 = _boto3()
    s3 = boto3.client("s3")
    dynamodb = boto3.resource("dynamodb")
    bucket = os.environ["BRONZE_BUCKET"]
    lock_table = os.environ["MANIFEST_LOCK_TABLE"]
    first_year = int(os.environ.get("INMET_START_YEAR", "2023"))
    last_year = datetime.now(timezone.utc).year
    for year in range(first_year, last_year + 1):
        url = f"https://portal.inmet.gov.br/uploads/dadoshistoricos/{year}.zip"
        metadata = _remote_metadata(url)
        key = f"clima/inmet_{year}_{_version_token(metadata)}.zip"
        _ingest(s3, dynamodb, bucket, lock_table, "INMET", url, key)
    return {"statusCode": 200}


def musicbrainz_handler(event, context):
    boto3 = _boto3()
    s3 = boto3.client("s3")
    dynamodb = boto3.resource("dynamodb")
    bucket = os.environ["BRONZE_BUCKET"]
    lock_table = os.environ["MANIFEST_LOCK_TABLE"]
    root = "https://data.metabrainz.org/pub/musicbrainz/data/json-dumps"
    with urllib.request.urlopen(_request(f"{root}/LATEST"), timeout=30) as response:
        version = response.read().decode("utf-8").strip().strip("/")
    if not version or ".." in version.split("/"):
        raise ValueError("A resposta LATEST do MusicBrainz nao contem uma versao valida")
    url = f"{root}/{quote(version, safe='/-._')}/event.tar.xz"
    key = f"eventos/{version}/event.tar.xz"
    _ingest(s3, dynamodb, bucket, lock_table, "MusicBrainz", url, key)
    return {"statusCode": 200, "version": version}


def anbima_handler(event, context):
    boto3 = _boto3()
    s3 = boto3.client("s3")
    dynamodb = boto3.resource("dynamodb")
    bucket = os.environ["BRONZE_BUCKET"]
    lock_table = os.environ["MANIFEST_LOCK_TABLE"]
    url = "https://www.anbima.com.br/feriados/arqs/feriados_nacionais.xls"
    referer = "https://www.anbima.com.br/feriados/feriados.asp"
    metadata = _remote_metadata(url, referer)
    key = f"feriados/feriados_nacionais_{_version_token(metadata)}.xls"
    _ingest(s3, dynamodb, bucket, lock_table, "ANBIMA", url, key, referer)
    return {"statusCode": 200}
