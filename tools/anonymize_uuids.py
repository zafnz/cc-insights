#!/usr/bin/env python3
"""
Anonymize UUIDs in JSONL log files while maintaining consistency.

This tool:
1. Scans a JSONL file for UUIDs in various fields
2. Creates a consistent mapping for each UUID
3. Replaces all occurrences with anonymized versions
4. Uses a random prefix per file with sequential numbering

Usage:
    python anonymize_uuids.py input.jsonl [output.jsonl]
    python anonymize_uuids.py --in-place input.jsonl

If output is not specified, writes to input.anonymized.jsonl
Use --in-place to overwrite the original file
"""

import json
import re
import sys
import secrets
import tempfile
import shutil
from pathlib import Path
from typing import Dict, Any


# UUID pattern (8-4-4-4-12 hex digits)
UUID_PATTERN = re.compile(
    r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b',
    re.IGNORECASE
)


def generate_random_prefix() -> str:
    """Generate a random 4-byte hex prefix for this file."""
    return secrets.token_hex(4)


def anonymize_uuid(uuid: str, mapping: Dict[str, str], prefix: str, counter: Dict[str, int]) -> str:
    """
    Anonymize a UUID using the mapping dictionary.

    Args:
        uuid: The UUID to anonymize
        mapping: Dictionary mapping original UUIDs to anonymized ones
        prefix: The random prefix for this file
        counter: Dictionary with a single 'count' key for tracking the sequence

    Returns:
        The anonymized UUID
    """
    uuid_lower = uuid.lower()

    if uuid_lower not in mapping:
        # Create new anonymized UUID: prefix-0000-0000-0000-{sequential}
        counter['count'] += 1
        seq_num = f"{counter['count']:012d}"
        anonymized = f"{prefix}-0000-0000-0000-{seq_num}"
        mapping[uuid_lower] = anonymized

    return mapping[uuid_lower]


def anonymize_value(value: Any, mapping: Dict[str, str], prefix: str, counter: Dict[str, int]) -> Any:
    """
    Recursively anonymize UUIDs in any JSON value.

    Args:
        value: The value to process (can be dict, list, str, or primitive)
        mapping: UUID mapping dictionary
        prefix: Random prefix for this file
        counter: Counter for sequential numbering

    Returns:
        The value with all UUIDs anonymized
    """
    if isinstance(value, str):
        # Replace all UUIDs in the string
        return UUID_PATTERN.sub(
            lambda m: anonymize_uuid(m.group(0), mapping, prefix, counter),
            value
        )
    elif isinstance(value, dict):
        return {k: anonymize_value(v, mapping, prefix, counter) for k, v in value.items()}
    elif isinstance(value, list):
        return [anonymize_value(item, mapping, prefix, counter) for item in value]
    else:
        # Numbers, booleans, null - return as-is
        return value


def anonymize_jsonl_file(input_path: Path, output_path: Path) -> Dict[str, str]:
    """
    Anonymize UUIDs in a JSONL file.

    Args:
        input_path: Path to input JSONL file
        output_path: Path to output JSONL file

    Returns:
        Dictionary mapping original UUIDs to anonymized ones
    """
    # Generate random prefix for this file
    prefix = generate_random_prefix()

    # Mapping and counter
    mapping: Dict[str, str] = {}
    counter = {'count': 0}

    # Process file line by line
    with open(input_path, 'r', encoding='utf-8') as infile, \
         open(output_path, 'w', encoding='utf-8') as outfile:

        for line_num, line in enumerate(infile, 1):
            line = line.strip()
            if not line:
                # Preserve empty lines
                outfile.write('\n')
                continue

            try:
                # Parse JSON
                data = json.loads(line)

                # Anonymize all UUIDs in the data
                anonymized_data = anonymize_value(data, mapping, prefix, counter)

                # Write back as JSON
                outfile.write(json.dumps(anonymized_data, separators=(',', ':')) + '\n')

            except json.JSONDecodeError as e:
                print(f"Warning: Line {line_num} is not valid JSON: {e}", file=sys.stderr)
                print(f"  Skipping line: {line[:100]}...", file=sys.stderr)
                # Write original line
                outfile.write(line + '\n')

    return mapping


def print_mapping(mapping: Dict[str, str]) -> None:
    """Print the UUID mapping for reference."""
    print(f"\nAnonymized {len(mapping)} unique UUIDs:")
    print("=" * 80)
    for original, anonymized in sorted(mapping.items()):
        print(f"{original} -> {anonymized}")


def main():
    """Main entry point."""
    if len(sys.argv) < 2:
        print("Usage: python anonymize_uuids.py input.jsonl [output.jsonl]", file=sys.stderr)
        print("       python anonymize_uuids.py --in-place input.jsonl", file=sys.stderr)
        print("\nIf output is not specified, writes to input.anonymized.jsonl", file=sys.stderr)
        print("Use --in-place to overwrite the original file", file=sys.stderr)
        sys.exit(1)

    # Check for --in-place flag
    in_place = '--in-place' in sys.argv
    args = [arg for arg in sys.argv[1:] if not arg.startswith('--')]

    if len(args) < 1:
        print("Error: No input file specified", file=sys.stderr)
        sys.exit(1)

    input_path = Path(args[0])

    if not input_path.exists():
        print(f"Error: Input file '{input_path}' does not exist", file=sys.stderr)
        sys.exit(1)

    # Determine output path
    if in_place:
        # Write to a temporary file first, then move it
        temp_fd, temp_path = tempfile.mkstemp(suffix='.jsonl', text=True)
        import os
        os.close(temp_fd)  # Close the file descriptor, we'll open it normally
        output_path = Path(temp_path)
        print(f"Anonymizing UUIDs in-place: {input_path}")
    elif len(args) >= 2:
        output_path = Path(args[1])
        print(f"Anonymizing UUIDs in: {input_path}")
        print(f"Output will be written to: {output_path}")
    else:
        output_path = input_path.with_suffix('.anonymized.jsonl')
        print(f"Anonymizing UUIDs in: {input_path}")
        print(f"Output will be written to: {output_path}")

    # Process the file
    mapping = anonymize_jsonl_file(input_path, output_path)

    # If in-place mode, replace the original file
    if in_place:
        shutil.move(str(output_path), str(input_path))
        print(f"\n✓ Successfully anonymized {len(mapping)} unique UUIDs")
        print(f"✓ Original file overwritten: {input_path}")
    else:
        print(f"\n✓ Successfully anonymized {len(mapping)} unique UUIDs")
        print(f"✓ Output written to: {output_path}")

    # Optionally print mapping (comment out if not needed)
    if '--show-mapping' in sys.argv:
        print_mapping(mapping)
    else:
        print("\nUse --show-mapping flag to see the full UUID mapping")


if __name__ == '__main__':
    main()
