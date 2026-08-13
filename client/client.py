#!/usr/bin/env python3
"""
Thin interactive client for Boom's control socket.
Basically my answer to "how do I get decent readline support in Elixir?"

Connects over TCP or a Unix domain socket and provides line editing,
persistent history, and safe interleaving of asynchronous server output
with user input, via prompt_toolkit.

Wire protocol is JSON blobs, one per line.

  client → server:  {"type": "cmd", "text": "<UTF-8 command>"}
  server → client:  {"type": "out", "text": "<UTF-8 output w/ ANSI escapes>"}

Both commands and output can be multi-line, since newlines are escaped as `\n`.

Usage:
    python3 client.py --unix-socket /path/to/app.sock
    python3 client.py --host localhost --port 4000
"""

import argparse
import asyncio
import contextlib
import json
import sys
import os
import stat
from pathlib import Path

from prompt_toolkit import PromptSession, print_formatted_text
from prompt_toolkit.formatted_text import ANSI
from prompt_toolkit.history import FileHistory
from prompt_toolkit.patch_stdout import patch_stdout

user_id = os.getuid()
DEFAULT_HISTORY_FILE = Path.home() / ".local/share/boom-history"
DEFAULT_SOCKETS = [
    f"/run/user/{user_id}/boom/socket",
    f"/tmp/boom-{user_id}/socket"
]

async def reader_loop(reader: asyncio.StreamReader) -> None:
    """Read JSON-lines messages from the server and print them safely.

    print_formatted_text(), called while patch_stdout() is active, erases
    the prompt and any in-progress input, prints the new output above it,
    then redraws the prompt and input exactly as they were. This is what
    keeps async server output from clobbering what the user is typing.
    """
    while True:
        raw = await reader.readline()
        if not raw:
            print_formatted_text("[disconnected from server]")
            return

        line = raw.decode("utf-8", errors="replace").rstrip("\n")
        if not line:
            continue

        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            # Be tolerant of a non-JSON line rather than dying on it.
            msg = {"text": line}

        print_formatted_text(ANSI(msg.get("text", "")))


async def writer_loop(writer: asyncio.StreamWriter, session: PromptSession) -> None:
    """Prompt for input and forward each accepted command to the server."""
    while True:
        try:
            text = await session.prompt_async("> ")
        except KeyboardInterrupt:
            # Ctrl-C: clear the current line and keep going, like a shell.
            continue
        except EOFError:
            # Ctrl-D: exit.
            break

        if text == "":
            continue

        payload = json.dumps({"type": "cmd", "text": text}) + "\n"
        writer.write(payload.encode("utf-8"))
        await writer.drain()

    writer.close()
    await writer.wait_closed()


async def main_async(args: argparse.Namespace) -> None:
    if args.unix_socket:
        if path := socket_check(args.unix_socket, True):
            reader, writer = await asyncio.open_unix_connection(path)
        else:
            sys.exit(1)
    elif args.host:
        reader, writer = await asyncio.open_connection(args.host, args.port)
    elif socket := fallback_socket():
        reader, writer = await asyncio.open_unix_connection(socket)
    else:
        print("No Unix sockets found, falling back to TCP ...", file=sys.stderr)
        reader, writer = await asyncio.open_connection("localhost", 2666)

    args.history_file.parent.mkdir(parents=True, exist_ok=True)
    # FileHistory loads existing history on first use and appends to disk
    # on every accepted entry -- no separate save step is needed.
    session = PromptSession(history=FileHistory(str(args.history_file)))

    with patch_stdout():
        reader_task = asyncio.create_task(reader_loop(reader))
        writer_task = asyncio.create_task(writer_loop(writer, session))

        # Exit as soon as either side finishes: the server hung up, or
        # the user quit. Cancel whichever task is still running.
        _, pending = await asyncio.wait(
            {reader_task, writer_task}, return_when=asyncio.FIRST_COMPLETED
        )
        for task in pending:
            task.cancel()
        for task in pending:
            with contextlib.suppress(asyncio.CancelledError):
                await task


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    group = parser.add_mutually_exclusive_group(required=False)
    group.add_argument("--unix-socket", metavar="PATH", help="Unix domain socket path")
    group.add_argument("--host", help="TCP host to connect to")
    parser.add_argument("--port", type=int, default=2666, help="TCP port (with --host)")
    parser.add_argument(
        "--history-file",
        type=Path,
        default=DEFAULT_HISTORY_FILE,
        help="Where to persist command history (default: %(default)s)",
    )
    return parser.parse_args()


def fallback_socket():
    for path in DEFAULT_SOCKETS:
        if path := socket_check(path):
            return path

    return None

def socket_check(path, verbose=False):
    path = Path(path).resolve()

    if not path.exists():
        if verbose:
            print(f"Socket {path} does not exist", file=sys.stderr)
        return None

    path_stat = path.stat()
    parent_stat = path.parent.stat()
    uid = os.getuid()

    if not path.is_socket():
        error = "is not a Unix domain socket"
    elif path_stat.st_uid != uid:
        error = "is owned by someone else"
    elif parent_stat.st_uid != uid:
        error = "is in a directory owned by someone else"
    elif path_stat.st_mode & stat.S_IWOTH != 0:
        error = "has unsafe permissions"
    elif parent_stat.st_mode & (stat.S_IRWXO | stat.S_IRWXG) != 0:
        error = "is in a directory with unsafe permissions"
    else:
        return path

    print(f"Socket {path} {error}", file=sys.stderr)
    return None

def main() -> None:
    args = parse_args()
    try:
        asyncio.run(main_async(args))
    except (ConnectionRefusedError, FileNotFoundError, OSError) as e:
        print(f"Could not connect: {e}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
