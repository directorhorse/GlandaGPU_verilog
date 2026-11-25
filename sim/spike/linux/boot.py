#!/usr/bin/env python3
"""Compatibility entry point; use bash linux/boot.sh directly for Python-free boot."""
import os
import sys
from pathlib import Path

os.execvp('bash', ['bash', str(Path(__file__).resolve().with_name('boot.sh')), *sys.argv[1:]])
