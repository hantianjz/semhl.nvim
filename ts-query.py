#!/usr/bin/env python3
"""
Tree-sitter Query Tool

A command-line tool for parsing source code files with tree-sitter and
executing queries to extract symbols and patterns.

Usage:
    echo "(function_definition) @func" | python ts-query.py file.py
    python ts-query.py file.py --query-file query.scm
    python ts-query.py file.py -q query.scm --show-type --show-position
"""

import sys
import argparse
import json
from pathlib import Path
from typing import Dict, List, Optional, Tuple

try:
    import tree_sitter_language_pack as tslp
    from tree_sitter import Language, Parser, Node, Query, QueryCursor
except ImportError as e:
    print(f"Error: Missing required dependencies. Please install them:", file=sys.stderr)
    print(f"  pip install tree-sitter tree-sitter-language-pack", file=sys.stderr)
    sys.exit(1)


# Language detection mapping from file extensions
EXTENSION_TO_LANGUAGE = {
    '.py': 'python',
    '.pyi': 'python',
    '.js': 'javascript',
    '.jsx': 'javascript',
    '.ts': 'typescript',
    '.tsx': 'tsx',
    '.c': 'c',
    '.h': 'c',
    '.cpp': 'cpp',
    '.cc': 'cpp',
    '.cxx': 'cpp',
    '.hpp': 'cpp',
    '.hh': 'cpp',
    '.hxx': 'cpp',
    '.java': 'java',
    '.go': 'go',
    '.rs': 'rust',
    '.rb': 'ruby',
    '.lua': 'lua',
    '.php': 'php',
    '.cs': 'c_sharp',
    '.swift': 'swift',
    '.kt': 'kotlin',
    '.scala': 'scala',
    '.r': 'r',
    '.R': 'r',
    '.sh': 'bash',
    '.bash': 'bash',
    '.vim': 'vim',
    '.el': 'elisp',
    '.md': 'markdown',
    '.html': 'html',
    '.htm': 'html',
    '.css': 'css',
    '.json': 'json',
    '.yaml': 'yaml',
    '.yml': 'yaml',
    '.toml': 'toml',
    '.xml': 'xml',
    '.sql': 'sql',
}


def detect_language(file_path: Path, language_override: Optional[str] = None) -> str:
    """
    Detect the programming language from file extension or use override.

    Args:
        file_path: Path to the source file
        language_override: Optional language name to override auto-detection

    Returns:
        Language name string

    Raises:
        ValueError: If language cannot be detected or is not supported
    """
    if language_override:
        return language_override

    suffix = file_path.suffix.lower()
    if suffix not in EXTENSION_TO_LANGUAGE:
        raise ValueError(
            f"Cannot detect language from extension '{suffix}'. "
            f"Use --language to specify explicitly."
        )

    return EXTENSION_TO_LANGUAGE[suffix]


def get_language_parser(language_name: str) -> Tuple[Language, Parser]:
    """
    Get tree-sitter language and parser for the given language name.

    Args:
        language_name: Name of the language (e.g., 'python', 'javascript')

    Returns:
        Tuple of (Language, Parser)

    Raises:
        ValueError: If language is not supported
    """
    try:
        language = tslp.get_language(language_name)
        parser = tslp.get_parser(language_name)
        return language, parser
    except Exception as e:
        raise ValueError(f"Language '{language_name}' is not supported: {e}")


def read_query(query_file: Optional[Path], stdin_query: bool) -> str:
    """
    Read tree-sitter query from file or stdin.

    Args:
        query_file: Path to query file, or None
        stdin_query: Whether to read from stdin

    Returns:
        Query string

    Raises:
        ValueError: If neither query source is provided or both are provided
        FileNotFoundError: If query file doesn't exist
    """
    if query_file and not stdin_query:
        if not query_file.exists():
            raise FileNotFoundError(f"Query file not found: {query_file}")
        return query_file.read_text()
    elif stdin_query and not query_file:
        return sys.stdin.read()
    elif not query_file and not stdin_query:
        raise ValueError("No query provided. Use --query-file or pipe query to stdin.")
    else:
        raise ValueError("Cannot specify both --query-file and stdin query.")


def execute_query(
    source_code: bytes,
    language: Language,
    parser: Parser,
    query_string: str
) -> List[Tuple[Node, str]]:
    """
    Parse source code and execute tree-sitter query.

    Args:
        source_code: Source code as bytes
        language: Tree-sitter Language object
        parser: Tree-sitter Parser object
        query_string: Query string in tree-sitter query syntax

    Returns:
        List of tuples containing (Node, capture_name)

    Raises:
        RuntimeError: If parsing or query execution fails
    """
    try:
        tree = parser.parse(source_code)
    except Exception as e:
        raise RuntimeError(f"Failed to parse source code: {e}")

    try:
        query = Query(language, query_string)
    except Exception as e:
        raise RuntimeError(f"Invalid tree-sitter query: {e}")

    try:
        cursor = QueryCursor(query)
        captures_dict = cursor.captures(tree.root_node)
        # Flatten the dictionary into a list of (node, capture_name) tuples
        results = []
        for capture_name, nodes in captures_dict.items():
            for node in nodes:
                results.append((node, capture_name))
        return results
    except Exception as e:
        raise RuntimeError(f"Query execution failed: {e}")


def format_match_plain(
    node: Node,
    capture_name: str,
    source_code: bytes,
    show_type: bool = False,
    show_position: bool = False,
    show_capture: bool = False
) -> str:
    """
    Format a query match as plain text.

    Args:
        node: Tree-sitter Node object
        capture_name: Name of the capture from the query
        source_code: Original source code as bytes
        show_type: Whether to show node type
        show_position: Whether to show position info
        show_capture: Whether to show capture name

    Returns:
        Formatted string
    """
    text = source_code[node.start_byte:node.end_byte].decode('utf-8', errors='replace')

    parts = []

    if show_capture:
        parts.append(f"@{capture_name}")

    if show_type:
        parts.append(f"[{node.type}]")

    if show_position:
        start_line = node.start_point[0] + 1  # 1-indexed
        start_col = node.start_point[1] + 1
        end_line = node.end_point[0] + 1
        end_col = node.end_point[1] + 1
        parts.append(f"{start_line}:{start_col}-{end_line}:{end_col}")

    parts.append(text)

    return " ".join(parts)


def format_match_json(
    node: Node,
    capture_name: str,
    source_code: bytes
) -> Dict:
    """
    Format a query match as JSON object.

    Args:
        node: Tree-sitter Node object
        capture_name: Name of the capture from the query
        source_code: Original source code as bytes

    Returns:
        Dictionary with match information
    """
    text = source_code[node.start_byte:node.end_byte].decode('utf-8', errors='replace')

    return {
        'capture': capture_name,
        'type': node.type,
        'text': text,
        'start': {
            'line': node.start_point[0] + 1,  # 1-indexed
            'column': node.start_point[1] + 1,
            'byte': node.start_byte
        },
        'end': {
            'line': node.end_point[0] + 1,
            'column': node.end_point[1] + 1,
            'byte': node.end_byte
        }
    }


def main():
    parser = argparse.ArgumentParser(
        description='Parse source files with tree-sitter and execute queries',
        epilog='''
Examples:
  # Query from stdin
  echo "(function_definition) @func" | python ts-query.py file.py

  # Query from file
  python ts-query.py file.py --query-file query.scm

  # With custom output options
  python ts-query.py file.py -q query.scm --show-type --show-position

  # JSON output
  python ts-query.py file.py -q query.scm --format json

  # Override language detection
  python ts-query.py file.txt --language python -q query.scm
        ''',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        'file',
        type=Path,
        help='Source file to parse'
    )

    parser.add_argument(
        '-q', '--query-file',
        type=Path,
        help='File containing tree-sitter query (if not provided, reads from stdin)'
    )

    parser.add_argument(
        '-l', '--language',
        help='Programming language (overrides auto-detection from file extension)'
    )

    parser.add_argument(
        '--format',
        choices=['plain', 'json'],
        default='plain',
        help='Output format (default: plain)'
    )

    parser.add_argument(
        '--show-type',
        action='store_true',
        help='Show node type in plain text output'
    )

    parser.add_argument(
        '--show-position',
        action='store_true',
        help='Show position (line:column) in plain text output'
    )

    parser.add_argument(
        '--show-capture',
        action='store_true',
        help='Show capture name in plain text output'
    )

    args = parser.parse_args()

    # Validate source file
    if not args.file.exists():
        print(f"Error: File not found: {args.file}", file=sys.stderr)
        sys.exit(1)

    try:
        # Detect language
        language_name = detect_language(args.file, args.language)

        # Get language parser
        language, ts_parser = get_language_parser(language_name)

        # Read query
        stdin_query = not sys.stdin.isatty() and args.query_file is None
        query_string = read_query(args.query_file, stdin_query)

        # Read source file
        source_code = args.file.read_bytes()

        # Execute query
        matches = execute_query(source_code, language, ts_parser, query_string)

        # Format and output results
        if args.format == 'json':
            results = [
                format_match_json(node, capture_name, source_code)
                for node, capture_name in matches
            ]
            print(json.dumps(results, indent=2))
        else:  # plain text
            for node, capture_name in matches:
                output = format_match_plain(
                    node, capture_name, source_code,
                    show_type=args.show_type,
                    show_position=args.show_position,
                    show_capture=args.show_capture
                )
                print(output)

    except (ValueError, FileNotFoundError, RuntimeError) as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
