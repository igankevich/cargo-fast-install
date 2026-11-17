#!/usr/bin/env python3

# SPDX-License-Identifier: MIT

import importlib.util
from importlib.machinery import SourceFileLoader
import json
import unittest
from itertools import permutations
from types import SimpleNamespace
from hypothesis import given
from hypothesis import strategies as st


loader = SourceFileLoader("yard", "./yard")
spec = importlib.util.spec_from_loader("yard", loader)
yard = importlib.util.module_from_spec(spec)
loader.exec_module(yard)

# fmt: off
SHA256_HASH = st.text(
    alphabet=["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"],
    min_size=64,
    max_size=64,
)
# fmt: on
CRATE_VERSION = st.from_regex("[0-9]+.[0-9]+.[0-9]+", fullmatch=True)
CRATE_NAME = st.from_regex("[a-zA-Z0-9_-]{1,64}", fullmatch=True).filter(
    yard.is_valid_crate_name
)


class TestCrateSpec(unittest.TestCase):
    def test_good(self):
        @given(CRATE_NAME, st.one_of([SHA256_HASH, CRATE_VERSION]))
        def round_trip(crate_name, version_or_hash):
            raw_spec = f"{crate_name}@{version_or_hash}"
            spec = yard.parse_crate_spec(raw_spec)
            assert str(spec) == raw_spec

        round_trip()

    def test_bad(self):
        for raw_spec in ["", "@", "x@", "@x"]:
            with self.assertRaises(yard.Error):
                yard.parse_crate_spec(raw_spec)
        self.assertEqual("x@@", str(yard.parse_crate_spec("x@@")))


BINARY_NAME = CRATE_NAME
BINARY_VARIANT = BINARY_NAME


class TestBinarySpec(unittest.TestCase):
    def test_good(self):
        @given(BINARY_NAME, BINARY_VARIANT)
        def round_trip(name, variant):
            raw_spec = f"{name}:{variant}"
            spec = yard.parse_binary_spec(raw_spec)
            assert str(spec) == raw_spec

        round_trip()

    def test_bad(self):
        for raw_spec in ["", ":", "x:", ":x", "x::"]:
            with self.assertRaises(yard.Error):
                yard.parse_binary_spec(raw_spec)


TARGET = st.from_regex("[a-zA-Z0-9_-]+", fullmatch=True)


class TestArchiveSpec(unittest.TestCase):
    def test_good(self):
        @given(
            TARGET,
            SHA256_HASH,
            st.text(),
            st.lists(BINARY_NAME, min_size=1, unique=True),
            st.one_of([BINARY_VARIANT, st.just(None)]),
        )
        def round_trip(target, hash, url, binaries, variant):
            crate = None
            json_object = {
                "target": target,
                "binaries": sorted(binaries),
                "url": url,
                "hash": hash,
            }
            if variant is not None:
                json_object["variant"] = variant
            spec = yard.parse_archive_spec(json_object, crate)
            self.assertEqual(json.loads(spec.to_json()), json_object)

        round_trip()

    def test_bad(self):
        crate = None
        for json_object in [
            {},
            {
                "target": "target",
            },
            {
                "target": "target",
                "binaries": ["binary"],
                "url": "url",
            },
            {
                "target": "target",
                "binaries": [],
                "url": "url",
                "hash": "0000000000000000000000000000000000000000000000000000000000000000",
            },
            {
                "target": "target",
                "binaries": ["binary"],
                "url": "url",
                "hash": "0000000000000000000000000000000000000000000000000000000000000000x",
            },
        ]:
            with self.assertRaises(yard.Error):
                yard.parse_archive_spec(json_object, crate)


class TestCargoRegistry(unittest.TestCase):
    def test_get_download_url(self):
        MARKERS = ["crate", "version", "sha256-checksum"]
        for values in permutations(MARKERS):
            all_markers = {
                marker: "{" + value + "}" for marker, value in zip(MARKERS, values)
            }
            crate = SimpleNamespace()
            crate.name = all_markers["crate"]
            crate.vers = all_markers["version"]
            crate.cksum = all_markers["sha256-checksum"]
            config = SimpleNamespace()
            config.dl = "|".join(["{" + marker + "}" for marker in MARKERS])
            registry = yard.CargoRegistry("https://registry.local", config)
            url = registry.get_download_url(crate)
            self.assertEqual(
                ["{" + value + "}" for value in values],
                list(url.split("|")),
            )

    def test_get_crate_prefix(self):
        for expected, crate_name in [
            ("1/a", "a"),
            ("2/ab", "ab"),
            ("3/a/abc", "abc"),
            ("ab/cd/abcd", "abcd"),
            ("ab/cd/abcde", "abcde"),
        ]:
            self.assertEqual(expected, yard.get_crate_prefix(crate_name))


if __name__ == "__main__":
    unittest.main()
