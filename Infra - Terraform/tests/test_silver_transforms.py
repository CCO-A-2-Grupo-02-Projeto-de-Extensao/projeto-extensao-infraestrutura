import sys
import gzip
import io
import json
import tarfile
import unittest
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lambda_src"))

from silver import _event_rows, _events_rows, _inmet_timestamp, _parse_measurement, _write_gzip


class MemoryS3:
    def __init__(self, content):
        self.content = content

    def get_object(self, **kwargs):
        return {"Body": io.BytesIO(self.content)}

    def put_object(self, **kwargs):
        self.upload = {**kwargs, "Body": kwargs["Body"].read()}


class SilverTransformTests(unittest.TestCase):
    def event(self, begin="2024-07-01", end="2024-07-03", **overrides):
        value = {
            "name": "Festival",
            "type": "Festival",
            "cancelled": False,
            "life-span": {"begin": begin, "end": end},
            "relations": [{
                "type": "held at",
                "place": {"name": "Anhembi", "area": {"name": "São Paulo"}},
            }],
        }
        value.update(overrides)
        return value

    def test_multiday_event_expands_inclusive_dates(self):
        rows = _event_rows(self.event())
        self.assertEqual([row["dia"] for row in rows], [
            "2024-07-01", "2024-07-02", "2024-07-03",
        ])
        self.assertTrue(all(row["local"] == "Anhembi" for row in rows))

    def test_single_date_event_defaults_missing_end_to_start(self):
        self.assertEqual(
            _event_rows(self.event(end=""))[0]["dia"],
            "2024-07-01",
        )
        self.assertEqual(_event_rows(self.event(begin="invalid")), [])

    def test_cancelled_event_is_discarded(self):
        self.assertEqual(_event_rows(self.event(cancelled=True)), [])

    def test_event_outside_sao_paulo_is_discarded(self):
        event = self.event(relations=[{
            "type": "held at",
            "place": {"name": "Campinas", "area": {"name": "Campinas"}},
        }])
        self.assertEqual(_event_rows(event), [])

    def test_utc_hour_converts_to_sao_paulo(self):
        instant = _inmet_timestamp("2024/01/02", "0300 UTC")
        self.assertEqual(instant.isoformat(), "2024-01-02T00:00:00-03:00")

    def test_missing_sensor_value_becomes_null(self):
        self.assertEqual(_parse_measurement("-9999"), "")
        self.assertEqual(_parse_measurement("12,5"), 12.5)

    def test_hour_2400_rolls_to_next_day(self):
        instant = _inmet_timestamp("2024/01/02", "2400 UTC")
        self.assertEqual(instant.date(), date(2024, 1, 2))
        self.assertEqual(instant.isoformat(), "2024-01-02T21:00:00-03:00")

    def test_streaming_musicbrainz_archive_filters_and_expands_events(self):
        events = [
            self.event(),
            self.event(name="Cancelled", cancelled=True),
            self.event(name="Other city", relations=[{
                "type": "held at",
                "place": {"name": "Campinas", "area": {"name": "Campinas"}},
            }]),
        ]
        content = "\n".join(json.dumps(event, ensure_ascii=False) for event in events).encode()
        archive_bytes = io.BytesIO()
        with tarfile.open(fileobj=archive_bytes, mode="w:xz") as archive:
            member = tarfile.TarInfo("mbdump/event")
            member.size = len(content)
            archive.addfile(member, io.BytesIO(content))

        rows = _events_rows(MemoryS3(archive_bytes.getvalue()), "bronze", "event.tar.xz")

        self.assertEqual(len(rows), 3)
        self.assertEqual(rows[0]["evento"], "Festival")

    def test_silver_output_is_gzip_csv_with_expected_columns(self):
        s3 = MemoryS3(b"")
        _write_gzip(
            s3,
            "silver",
            "eventos_cidade.csv.gz",
            ("dia", "evento", "local", "tipo"),
            [{"dia": "2024-07-01", "evento": "Festival", "local": "Anhembi", "tipo": "Festival"}],
        )

        output = gzip.decompress(s3.upload["Body"]).decode()
        self.assertEqual(output.splitlines()[0], "dia,evento,local,tipo")
        self.assertIn("2024-07-01,Festival,Anhembi,Festival", output)


if __name__ == "__main__":
    unittest.main()
