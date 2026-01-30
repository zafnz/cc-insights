#!/usr/bin/env python3
"""MitM proxy for Claude binary - logs all stdin/stdout/stderr."""

import asyncio
import json
import os
import sys
from datetime import datetime

# Path to real binary (same directory as this script)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REAL_BINARY = os.path.join(SCRIPT_DIR, "_real_claude")

# Log file location
LOG_FILE = os.path.expanduser("~/claude_mitm.log")


def log(direction: str, data: bytes):
    """Append timestamped log entry as JSON."""
    timestamp = datetime.now().isoformat(timespec="milliseconds")

    # Try to decode as UTF-8 text
    try:
        text = data.decode("utf-8", errors="replace")
    except Exception:
        text = repr(data)

    # Try to parse as JSON
    log_entry = {
        "time": timestamp,
        "fd": direction,
    }

    try:
        parsed_json = json.loads(text)
        log_entry["type"] = "json"
        log_entry["json"] = parsed_json
    except (json.JSONDecodeError, ValueError):
        log_entry["type"] = "text"
        log_entry["text"] = text

    with open(LOG_FILE, "a") as f:
        f.write(json.dumps(log_entry) + "\n")


async def pipe_stdin(proc_stdin):
    """Read stdin and forward to process."""
    loop = asyncio.get_event_loop()
    reader = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(reader)
    await loop.connect_read_pipe(lambda: protocol, sys.stdin.buffer)

    buffer = b""
    try:
        while True:
            data = await reader.read(4096)
            if not data:
                break

            # ALWAYS forward data immediately to avoid blocking
            proc_stdin.write(data)
            await proc_stdin.drain()

            # Accumulate data in buffer for logging
            buffer += data

            # Process complete lines for logging (newline-delimited JSON)
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                if line:  # Skip empty lines
                    log("STDIN", line)

    except Exception as e:
        log("STDIN_ERROR", str(e).encode())
    finally:
        # Log any remaining buffered data
        if buffer:
            log("STDIN", buffer)
        proc_stdin.close()


async def pipe_output(proc_stream, out_stream, direction: str):
    """Read from process and forward to our stdout/stderr."""
    buffer = b""
    try:
        while True:
            data = await proc_stream.read(4096)
            if not data:
                break

            # ALWAYS forward data immediately to avoid blocking
            out_stream.buffer.write(data)
            out_stream.buffer.flush()

            # Accumulate data in buffer for logging
            buffer += data

            # Process complete lines for logging (newline-delimited JSON)
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                if line:  # Skip empty lines
                    log(direction, line)

    except Exception as e:
        log(f"{direction}_ERROR", str(e).encode())
    finally:
        # Log any remaining buffered data
        if buffer:
            log(direction, buffer)
            out_stream.buffer.write(buffer)
            out_stream.buffer.flush()


async def main():
    # Log startup
    log("STARTUP", f"Args: {sys.argv[1:]}".encode())

    # Start the real binary with same args
    proc = await asyncio.create_subprocess_exec(
        REAL_BINARY,
        *sys.argv[1:],
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )

    # Run all pipes concurrently
    tasks = [
        asyncio.create_task(pipe_stdin(proc.stdin)),
        asyncio.create_task(pipe_output(proc.stdout, sys.stdout, "STDOUT")),
        asyncio.create_task(pipe_output(proc.stderr, sys.stderr, "STDERR")),
    ]

    # Wait for process to complete
    await proc.wait()

    # Cancel remaining tasks
    for task in tasks:
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass

    log("EXIT", f"Return code: {proc.returncode}".encode())
    sys.exit(proc.returncode)


if __name__ == "__main__":
    asyncio.run(main())
