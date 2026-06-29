#!/usr/bin/env python3
"""HTTP fetch helpers with timeouts (trafilatura has no built-in timeout)."""

from __future__ import annotations

import concurrent.futures

from trafilatura import fetch_url

DEFAULT_TIMEOUT = 45.0


def fetch_url_timed(url: str, *, timeout: float = DEFAULT_TIMEOUT) -> str | None:
    """Fetch a URL via trafilatura, aborting after `timeout` seconds."""
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        future = pool.submit(fetch_url, url)
        try:
            return future.result(timeout=timeout)
        except concurrent.futures.TimeoutError:
            print(f"    ! timeout ({int(timeout)}s): {url}", flush=True)
            return None
