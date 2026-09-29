import csv
import gzip
import io
import json
import logging
import os
import re
try:
    import resource
except ImportError:
    resource = None
import tempfile
import tarfile
import time
import zipfile
from datetime import date, datetime, time as datetime_time, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo
from urllib.parse import unquote_plus


LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)
FIELDS = {
    "clima": ("instante", "chuva_mm", "temp_c"),
    "eventos": ("dia", "evento", "local", "tipo"),
    "feriados": ("dia", "nome_feriado"),
}
SAO_PAULO = ZoneInfo("America/Sao_Paulo")


def _boto3():
    import boto3

    return boto3


def _date(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        return None


def _event_rows(event):
    if event.get("cancelled"):
        return []
    local = next(
        (
            relation.get("place")
            for relation in event.get("relations", [])
            if relation.get("type") == "held at"
            and ((relation.get("place") or {}).get("area") or {}).get("name") == "São Paulo"
        ),
        None,
    )
    if local is None:
        return []
    period = event.get("life-span") or {}
    start = _date(period.get("begin"))
    end = _date(period.get("end")) or start
    if start is None or end < start:
        return []
    name = event.get("name") or ""
    event_type = event.get("type") or ""
    return [
        {"dia": day.isoformat(), "evento": name, "local": local.get("name") or "", "tipo": event_type}
        for day in _days(start, end)
    ]


def _days(start, end):
    current = start
    while current <= end:
        yield current
        current += timedelta(days=1)


def _parse_measurement(value):
    value = (value or "").strip().replace(",", ".")
    if not value:
        return ""
    try:
        number = float(value)
    except ValueError:
        return ""
    return "" if number == -9999 else number


def _inmet_timestamp(day_value, hour_value):
    date_value = datetime.strptime(day_value.strip(), "%Y/%m/%d").date()
    digits = re.sub(r"\D", "", str(hour_value))[:4].zfill(4)
    hour = int(digits[:2])
    minute = int(digits[2:])
    if hour == 24 and minute == 0:
        date_value += timedelta(days=1)
        hour = 0
    moment = datetime.combine(date_value, datetime_time(hour, minute), timezone.utc)
    return moment.astimezone(SAO_PAULO)


def _find_column(columns, phrase):
    return next(column for column in columns if phrase in column.upper())


def _write_gzip(s3, bucket, key, fieldnames, rows):
    with tempfile.NamedTemporaryFile(suffix=".csv.gz", delete=False) as output:
        path = Path(output.name)
    try:
        with gzip.open(path, "wt", encoding="utf-8", newline="") as compressed:
            writer = csv.DictWriter(compressed, fieldnames=fieldnames, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        with path.open("rb") as body:
            s3.put_object(
                Bucket=bucket,
                Key=key,
                Body=body,
                ContentType="text/csv",
                ContentEncoding="gzip",
            )
    finally:
        path.unlink(missing_ok=True)


def _list_objects(s3, bucket, prefix):
    paginator = s3.get_paginator("list_objects_v2")
    result = []
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        result.extend(page.get("Contents", []))
    return result


def _latest_event_key(s3, bronze_bucket):
    objects = _list_objects(s3, bronze_bucket, "eventos/")
    if not objects:
        raise FileNotFoundError("Nenhum dump do MusicBrainz foi encontrado na Bronze")
    return max(objects, key=lambda item: (item["LastModified"], item["Key"]))["Key"]


def _latest_holiday_key(s3, bronze_bucket):
    objects = _list_objects(s3, bronze_bucket, "feriados/")
    if not objects:
        raise FileNotFoundError("Nenhuma planilha ANBIMA foi encontrada na Bronze")
    return max(objects, key=lambda item: (item["LastModified"], item["Key"]))["Key"]


def _latest_climate_keys(s3, bronze_bucket):
    latest = {}
    for item in _list_objects(s3, bronze_bucket, "clima/"):
        match = re.search(r"inmet_(\d{4})_", item["Key"])
        if match is None:
            continue
        year = int(match.group(1))
        if year not in latest or item["LastModified"] > latest[year]["LastModified"]:
            latest[year] = item
    return [latest[year]["Key"] for year in sorted(latest)]


def _climate_rows(s3, bronze_bucket):
    result = []
    for key in _latest_climate_keys(s3, bronze_bucket):
        response = s3.get_object(Bucket=bronze_bucket, Key=key)
        with tempfile.NamedTemporaryFile(suffix=".zip", delete=False) as archive_file:
            archive_path = Path(archive_file.name)
            for block in iter(lambda: response["Body"].read(1024 * 1024), b""):
                archive_file.write(block)
        response["Body"].close()
        try:
            with zipfile.ZipFile(archive_path) as archive:
                member = next(
                    name for name in archive.namelist()
                    if "A701" in name and name.upper().endswith(".CSV")
                )
                with archive.open(member) as source:
                    text = io.TextIOWrapper(source, encoding="latin-1")
                    for _ in range(8):
                        next(text, None)
                    reader = csv.DictReader(text, delimiter=";")
                    columns = reader.fieldnames or []
                    precipitation = _find_column(columns, "PRECIPITA")
                    temperature = _find_column(columns, "TEMPERATURA DO AR")
                    for row in reader:
                        try:
                            instant = _inmet_timestamp(row[columns[0]], row[columns[1]])
                        except (ValueError, TypeError):
                            continue
                        if instant.year < 2023 or instant.year > datetime.now(timezone.utc).year:
                            continue
                        result.append({
                            "_sort": instant,
                            "instante": instant.isoformat(sep=" ", timespec="seconds"),
                            "chuva_mm": _parse_measurement(row.get(precipitation)),
                            "temp_c": _parse_measurement(row.get(temperature)),
                        })
        finally:
            archive_path.unlink(missing_ok=True)
    result.sort(key=lambda row: row["_sort"])
    return [{field: row[field] for field in FIELDS["clima"]} for row in result]


def _events_rows(s3, bronze_bucket, key):
    response = s3.get_object(Bucket=bronze_bucket, Key=key)
    seen = set()
    rows = []
    started = time.monotonic()
    with response["Body"] as body, tarfile.open(fileobj=body, mode="r|xz") as archive:
        for member in archive:
            if member.name != "mbdump/event":
                continue
            source = archive.extractfile(member)
            if source is None:
                break
            with source:
                for line in source:
                    if b"S\xc3\xa3o Paulo" not in line and b"S\\u00e3o Paulo" not in line:
                        continue
                    event = json.loads(line)
                    for row in _event_rows(event):
                        identity = tuple(row[field] for field in FIELDS["eventos"])
                        if identity not in seen:
                            seen.add(identity)
                            rows.append(row)
            break
    max_rss_mb = (
        resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024
        if resource is not None
        else None
    )
    LOGGER.info(
        "musicbrainz_processed key=%s rows=%d elapsed_seconds=%.2f max_rss_mb=%s",
        key,
        len(rows),
        time.monotonic() - started,
        f"{max_rss_mb:.1f}" if max_rss_mb is not None else "unavailable",
    )
    return rows


def _holiday_date(value, cell_type, datemode, xlrd):
    if cell_type == xlrd.XL_CELL_DATE:
        try:
            return xlrd.xldate_as_datetime(value, datemode).date()
        except (ValueError, OverflowError):
            return None
    if isinstance(value, str):
        for pattern in ("%d/%m/%Y", "%Y-%m-%d"):
            try:
                return datetime.strptime(value.strip(), pattern).date()
            except ValueError:
                pass
    return None


def _holiday_rows(s3, bronze_bucket, key):
    import xlrd

    response = s3.get_object(Bucket=bronze_bucket, Key=key)
    content = response["Body"].read()
    workbook = xlrd.open_workbook(file_contents=content)
    sheet = workbook.sheet_by_index(0)
    headers = [str(sheet.cell_value(0, column)).strip() for column in range(sheet.ncols)]
    date_column = headers.index("Data")
    name_column = headers.index("Feriado")
    holidays = {}
    for row_index in range(1, sheet.nrows):
        holiday_date = _holiday_date(
            sheet.cell_value(row_index, date_column),
            sheet.cell_type(row_index, date_column),
            workbook.datemode,
            xlrd,
        )
        name = str(sheet.cell_value(row_index, name_column)).strip()
        if holiday_date is not None and name:
            holidays.setdefault(holiday_date, name)
    return [
        {"dia": holiday.isoformat(), "nome_feriado": holidays[holiday]}
        for holiday in sorted(holidays)
    ]


def _dispatch(s3, bronze_bucket, silver_bucket, prefix):
    if prefix == "clima/":
        rows = _climate_rows(s3, bronze_bucket)
        key = "clima_horario.csv.gz"
        fields = FIELDS["clima"]
    elif prefix == "eventos/":
        source_key = _latest_event_key(s3, bronze_bucket)
        rows = _events_rows(s3, bronze_bucket, source_key)
        key = "eventos_cidade.csv.gz"
        fields = FIELDS["eventos"]
    elif prefix == "feriados/":
        source_key = _latest_holiday_key(s3, bronze_bucket)
        rows = _holiday_rows(s3, bronze_bucket, source_key)
        key = "feriados_nacionais.csv.gz"
        fields = FIELDS["feriados"]
    else:
        raise ValueError(f"Prefixo Bronze desconhecido: {prefix}")
    _write_gzip(s3, silver_bucket, key, fields, rows)
    LOGGER.info("silver_written source=%s key=%s rows=%d", prefix, key, len(rows))
    return {"source": prefix, "key": key, "rows": len(rows)}


def handler(event, context):
    boto3 = _boto3()
    s3 = boto3.client("s3")
    bronze_bucket = os.environ["BRONZE_BUCKET"]
    silver_bucket = os.environ["SILVER_BUCKET"]
    sources = set()
    for record in event.get("Records", []):
        if record.get("eventSource") != "aws:s3":
            continue
        key = unquote_plus(record["s3"]["object"]["key"])
        for prefix in ("clima/", "eventos/", "feriados/"):
            if key.startswith(prefix):
                sources.add(prefix)
                break
    return [_dispatch(s3, bronze_bucket, silver_bucket, prefix) for prefix in sorted(sources)]
