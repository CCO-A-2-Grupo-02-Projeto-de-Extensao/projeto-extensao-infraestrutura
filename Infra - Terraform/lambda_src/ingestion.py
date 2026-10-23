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
CHAMADAS_FIELDS = ("id_chamada", "data_chamada", "presenca")
CHAMADAS_QUERY = (
    "SELECT c.idChamada, c.data_chamada, p.presenca "
    "FROM presenca p JOIN chamada c ON c.idChamada = p.Chamada_idChamada "
    "ORDER BY c.data_chamada, c.idChamada"
)


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
        # "owner" e palavra reservada no DynamoDB: precisa de alias no expression.
        table.delete_item(
            Key={"lock_id": lock_id},
            ConditionExpression="#owner = :owner",
            ExpressionAttributeNames={"#owner": "owner"},
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


def _chamadas_csv(rows):
    output = io.StringIO()
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow(CHAMADAS_FIELDS)
    for id_chamada, data_chamada, presenca in rows:
        writer.writerow((id_chamada, data_chamada.isoformat(), int(bool(presenca))))
    return output.getvalue().encode("utf-8")


def chamadas_handler(event, context):
    import pymysql

    boto3 = _boto3()
    s3 = boto3.client("s3")
    dynamodb = boto3.resource("dynamodb")
    bucket = os.environ["BRONZE_BUCKET"]
    lock_table = os.environ["MANIFEST_LOCK_TABLE"]
    host = os.environ["DB_HOST"]
    database = os.environ["DB_NAME"]
    connection = pymysql.connect(
        host=host,
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        database=database,
        connect_timeout=30,
    )
    try:
        with connection.cursor() as cursor:
            cursor.execute(CHAMADAS_QUERY)
            rows = cursor.fetchall()
    finally:
        connection.close()

    body = _chamadas_csv(rows)
    key = f"chamadas/presencas_{hashlib.sha256(body).hexdigest()[:16]}.csv"
    if not _object_exists(s3, bucket, key):
        s3.put_object(Bucket=bucket, Key=key, Body=body, ContentType="text/csv; charset=utf-8")
        LOGGER.info("bronze_exported source=chamadas key=%s rows=%d", key, len(rows))
    else:
        LOGGER.info("bronze_exists source=chamadas key=%s rows=%d", key, len(rows))

    _append_manifest(
        s3,
        dynamodb,
        bucket,
        lock_table,
        {
            "fonte": "Arandu Digital",
            "data_coleta": datetime.now(timezone.utc).isoformat(),
            "tamanho_bytes": len(body),
            "url": f"mysql://{host}/{database}",
            "arquivo_s3": key,
        },
    )
    return {"statusCode": 200, "rows": len(rows)}
