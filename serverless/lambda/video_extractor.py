"""Minimal MP4 -> H.264 Annex B extractor.

Parses an ISO BMFF (MP4) container to locate each video sample (one encoded
H.264 frame per sample), converts it from AVCC length-prefix framing to the
Annex B byte stream convention (``0x00 00 00 01`` start codes), and prepends
the SPS/PPS parameter sets before every IDR frame so the emitted per-frame
chunk is self-contained for downstream decoders (Foxglove's Video panel,
ffmpeg, etc.).

Why pure Python and no ffmpeg: we run inside AWS Lambda. Bundling ffmpeg
means maintaining a native Layer for arm64 and paying a cold-start hit; the
logic we actually need (``avcC`` -> Annex B) is a ~150 LOC MP4 box walk, so
we do it ourselves.

The parser is deliberately *narrow*: it supports a single H.264 video track
encoded as ``avc1`` + ``avcC`` — exactly what AVFoundation produces on iOS.
It rejects anything it doesn't understand instead of silently returning
wrong bytes.
"""

from __future__ import annotations

import logging
import struct
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator, List, Optional, Tuple

log = logging.getLogger(__name__)

ANNEX_B_START = b"\x00\x00\x00\x01"


@dataclass
class H264Frame:
    """One encoded H.264 frame as an Annex B byte stream."""

    index: int
    is_keyframe: bool
    data: bytes


@dataclass
class _Track:
    timescale: int = 0
    sps: List[bytes] = field(default_factory=list)
    pps: List[bytes] = field(default_factory=list)
    nalu_length_size: int = 4
    sample_sizes: List[int] = field(default_factory=list)
    chunk_offsets: List[int] = field(default_factory=list)
    samples_per_chunk: List[Tuple[int, int]] = field(default_factory=list)
    keyframe_indices: set[int] = field(default_factory=set)


# ----------------------------------------------------------------------------
# Public API
# ----------------------------------------------------------------------------

def extract_h264_frames(mp4_path: Path) -> Iterator[H264Frame]:
    """Yield one :class:`H264Frame` per video sample in the file.

    Raises :class:`ValueError` if the MP4 doesn't contain a parseable H.264
    track (wrong codec, fragmented MP4 without ``moov``, etc.).
    """
    track = _parse_mp4(mp4_path)

    if not track.sample_sizes:
        raise ValueError(f"{mp4_path}: parsed 0 samples — not an MP4 or moov missing")

    sample_offsets = _resolve_sample_offsets(track)
    param_sets = b"".join(ANNEX_B_START + nal for nal in track.sps + track.pps)

    with mp4_path.open("rb") as fp:
        for i, (offset, size) in enumerate(zip(sample_offsets, track.sample_sizes)):
            fp.seek(offset)
            sample = fp.read(size)
            annex_b = _avcc_to_annex_b(sample, track.nalu_length_size)
            is_key = i in track.keyframe_indices
            if is_key:
                # SPS/PPS live in the avcC box, not inside every IDR in the
                # mdat. Downstream decoders expect them ahead of each keyframe
                # to be able to start playback from any random IDR.
                annex_b = param_sets + annex_b
            yield H264Frame(index=i, is_keyframe=is_key, data=annex_b)


# ----------------------------------------------------------------------------
# AVCC -> Annex B per-sample conversion
# ----------------------------------------------------------------------------

def _avcc_to_annex_b(sample: bytes, nalu_length_size: int) -> bytes:
    """Replace length-prefix framing with Annex B start codes.

    MP4 samples store NAL units as ``[length:N][payload:length]...`` where
    ``N`` is 1/2/4 bytes. Annex B uses ``[0x00 00 00 01][payload]...``.
    """
    out = bytearray()
    i = 0
    n = len(sample)
    while i < n:
        if n - i < nalu_length_size:
            raise ValueError("truncated sample: length prefix overruns buffer")
        length = int.from_bytes(sample[i : i + nalu_length_size], "big")
        i += nalu_length_size
        if length == 0 or i + length > n:
            raise ValueError(f"invalid NAL length {length} at offset {i}")
        out += ANNEX_B_START
        out += sample[i : i + length]
        i += length
    return bytes(out)


# ----------------------------------------------------------------------------
# Sample-offset resolution (stsc + stco/co64 + stsz)
# ----------------------------------------------------------------------------

def _resolve_sample_offsets(track: _Track) -> List[int]:
    """Expand stsc/stco/stsz tables into one absolute byte offset per sample."""
    if not track.chunk_offsets:
        raise ValueError("track has no chunk offsets (stco/co64 missing)")
    if not track.samples_per_chunk:
        raise ValueError("track has no sample-to-chunk map (stsc missing)")

    # Expand stsc runs into an explicit "this chunk holds N samples" list.
    per_chunk: List[int] = []
    num_chunks = len(track.chunk_offsets)
    runs = list(track.samples_per_chunk)
    runs.append((num_chunks + 1, 0))  # sentinel
    for (start, count), (next_start, _) in zip(runs, runs[1:]):
        for _ in range(start, next_start):
            per_chunk.append(count)
            if len(per_chunk) >= num_chunks:
                break
        if len(per_chunk) >= num_chunks:
            break
    per_chunk = per_chunk[:num_chunks]

    offsets: List[int] = []
    sample_idx = 0
    for chunk_idx, chunk_off in enumerate(track.chunk_offsets):
        running = chunk_off
        for _ in range(per_chunk[chunk_idx]):
            offsets.append(running)
            running += track.sample_sizes[sample_idx]
            sample_idx += 1
            if sample_idx >= len(track.sample_sizes):
                break
        if sample_idx >= len(track.sample_sizes):
            break

    if len(offsets) != len(track.sample_sizes):
        raise ValueError(
            f"stsc/stco inconsistency: resolved {len(offsets)} offsets for "
            f"{len(track.sample_sizes)} samples"
        )
    return offsets


# ----------------------------------------------------------------------------
# MP4 box walker (narrow: finds the first H.264 video track)
# ----------------------------------------------------------------------------

def _parse_mp4(mp4_path: Path) -> _Track:
    """Walk the MP4 and populate a :class:`_Track` for the first H.264 video."""
    data = mp4_path.read_bytes()

    moov = _find_box(data, 0, len(data), b"moov")
    if moov is None:
        raise ValueError(f"{mp4_path}: no moov box — fragmented/streaming MP4?")

    for trak_start, trak_end in _iter_boxes(data, *moov, b"trak"):
        track = _try_parse_trak(data, trak_start, trak_end)
        if track is not None:
            return track

    raise ValueError(f"{mp4_path}: no H.264 (avc1) video track found")


def _try_parse_trak(data: bytes, start: int, end: int) -> Optional[_Track]:
    mdia = _find_box(data, start, end, b"mdia")
    if mdia is None:
        return None

    hdlr = _find_box(data, *mdia, b"hdlr")
    if hdlr is None:
        return None
    # hdlr payload: version(1) + flags(3) + pre_defined(4) + handler_type(4 chars)
    ds, de = hdlr
    if de - ds < 12 or data[ds + 8 : ds + 12] != b"vide":
        return None

    mdhd = _find_box(data, *mdia, b"mdhd")
    if mdhd is None:
        return None
    timescale = _parse_mdhd_timescale(data, *mdhd)

    minf = _find_box(data, *mdia, b"minf")
    if minf is None:
        return None
    stbl = _find_box(data, *minf, b"stbl")
    if stbl is None:
        return None

    stsd = _find_box(data, *stbl, b"stsd")
    if stsd is None:
        return None
    avc_info = _parse_stsd(data, *stsd)
    if avc_info is None:
        return None
    sps, pps, nalu_len_size = avc_info

    stsz = _find_box(data, *stbl, b"stsz")
    if stsz is None:
        return None
    sample_sizes = _parse_stsz(data, *stsz)

    stsc = _find_box(data, *stbl, b"stsc")
    if stsc is None:
        return None
    samples_per_chunk = _parse_stsc(data, *stsc)

    stco = _find_box(data, *stbl, b"stco")
    co64 = _find_box(data, *stbl, b"co64")
    if stco is not None:
        chunk_offsets = _parse_stco(data, *stco, wide=False)
    elif co64 is not None:
        chunk_offsets = _parse_stco(data, *co64, wide=True)
    else:
        return None

    # stss is optional: if absent, every sample is a sync sample.
    stss = _find_box(data, *stbl, b"stss")
    if stss is not None:
        keyframes = _parse_stss(data, *stss)
    else:
        keyframes = set(range(len(sample_sizes)))

    return _Track(
        timescale=timescale,
        sps=sps,
        pps=pps,
        nalu_length_size=nalu_len_size,
        sample_sizes=sample_sizes,
        chunk_offsets=chunk_offsets,
        samples_per_chunk=samples_per_chunk,
        keyframe_indices=keyframes,
    )


# ----------------------------------------------------------------------------
# Box-walking primitives
# ----------------------------------------------------------------------------

def _iter_boxes(data: bytes, start: int, end: int, want: bytes):
    """Yield (content_start, content_end) for every direct child matching ``want``."""
    pos = start
    while pos + 8 <= end:
        size = int.from_bytes(data[pos : pos + 4], "big")
        box_type = data[pos + 4 : pos + 8]
        header = 8
        if size == 1:
            size = int.from_bytes(data[pos + 8 : pos + 16], "big")
            header = 16
        if size < header or pos + size > end:
            return
        if box_type == want:
            yield pos + header, pos + size
        pos += size


def _find_box(data: bytes, start: int, end: int, want: bytes) -> Optional[Tuple[int, int]]:
    for s, e in _iter_boxes(data, start, end, want):
        return s, e
    return None


# ----------------------------------------------------------------------------
# Specific box parsers
# ----------------------------------------------------------------------------

def _parse_mdhd_timescale(data: bytes, start: int, end: int) -> int:
    version = data[start]
    if version == 1:
        return int.from_bytes(data[start + 20 : start + 24], "big")
    return int.from_bytes(data[start + 12 : start + 16], "big")


def _parse_stsd(
    data: bytes, start: int, end: int
) -> Optional[Tuple[List[bytes], List[bytes], int]]:
    """Return (SPS list, PPS list, NAL length size) if an avc1 entry is found."""
    # 4B version+flags, 4B entry_count, then entries
    pos = start + 8
    while pos + 8 <= end:
        entry_size = int.from_bytes(data[pos : pos + 4], "big")
        entry_type = data[pos + 4 : pos + 8]
        if entry_type not in (b"avc1", b"avc3"):
            pos += entry_size
            continue
        # avc1 header: 6B reserved + 2B data_reference_index
        # + 16B pre_defined/reserved
        # + 2B width + 2B height + 4B horiz_res + 4B vert_res + 4B reserved
        # + 2B frame_count + 32B compressorname + 2B depth + 2B pre_defined
        avc_entry_end = pos + entry_size
        child_start = pos + 8 + 78
        avcc = _find_box(data, child_start, avc_entry_end, b"avcC")
        if avcc is None:
            return None
        return _parse_avcc(data, *avcc)
    return None


def _parse_avcc(data: bytes, start: int, end: int) -> Tuple[List[bytes], List[bytes], int]:
    # configurationVersion(1) | profile(1) | profile_compat(1) | level(1)
    # | reserved(6b)+lengthSizeMinusOne(2b)(1)
    # | reserved(3b)+numOfSPS(5b)(1)
    pos = start
    _ = data[pos]           # version
    pos += 4
    nalu_length_size = (data[pos] & 0x03) + 1
    pos += 1
    num_sps = data[pos] & 0x1F
    pos += 1
    sps: List[bytes] = []
    for _ in range(num_sps):
        length = int.from_bytes(data[pos : pos + 2], "big")
        pos += 2
        sps.append(data[pos : pos + length])
        pos += length
    num_pps = data[pos]
    pos += 1
    pps: List[bytes] = []
    for _ in range(num_pps):
        length = int.from_bytes(data[pos : pos + 2], "big")
        pos += 2
        pps.append(data[pos : pos + length])
        pos += length
    return sps, pps, nalu_length_size


def _parse_stsz(data: bytes, start: int, end: int) -> List[int]:
    # 4B version+flags | 4B default_size | 4B sample_count | [4B size]*
    default_size = int.from_bytes(data[start + 4 : start + 8], "big")
    count = int.from_bytes(data[start + 8 : start + 12], "big")
    if default_size != 0:
        return [default_size] * count
    sizes = struct.unpack_from(f">{count}I", data, start + 12)
    return list(sizes)


def _parse_stsc(data: bytes, start: int, end: int) -> List[Tuple[int, int]]:
    """Return list of (first_chunk_1based, samples_per_chunk)."""
    count = int.from_bytes(data[start + 4 : start + 8], "big")
    out: List[Tuple[int, int]] = []
    pos = start + 8
    for _ in range(count):
        first_chunk = int.from_bytes(data[pos : pos + 4], "big")
        samples = int.from_bytes(data[pos + 4 : pos + 8], "big")
        out.append((first_chunk, samples))
        pos += 12
    return out


def _parse_stco(data: bytes, start: int, end: int, wide: bool) -> List[int]:
    count = int.from_bytes(data[start + 4 : start + 8], "big")
    if wide:
        return list(struct.unpack_from(f">{count}Q", data, start + 8))
    return list(struct.unpack_from(f">{count}I", data, start + 8))


def _parse_stss(data: bytes, start: int, end: int) -> set[int]:
    """Return zero-based sample indices that are sync samples."""
    count = int.from_bytes(data[start + 4 : start + 8], "big")
    one_based = struct.unpack_from(f">{count}I", data, start + 8)
    return {n - 1 for n in one_based}
