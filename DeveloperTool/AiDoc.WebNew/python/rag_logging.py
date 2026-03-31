"""
Configure file logging for RAG setup, config, and indexing. All Python RAG scripts should call setup_rag_logging() at start.
Log file: RAG_LOG_DIR or C:\\opt\\data\\AllPwshLog, filename RAG-Python_<hostname>_<yyyyMMdd>.log
"""
import logging
import os
import socket
from datetime import datetime
from pathlib import Path


def setup_rag_logging(name: str = "rag") -> logging.Logger:
    """Set up logging to a daily file in RAG_LOG_DIR (or C:\\opt\\data\\AllPwshLog). Returns logger."""
    log_dir = os.environ.get("RAG_LOG_DIR", "").strip() or "C:\\opt\\data\\AllPwshLog"
    path = Path(log_dir)
    path.mkdir(parents=True, exist_ok=True)
    hostname = getattr(socket, "gethostname", lambda: "localhost")() or "localhost"
    date_str = datetime.now().strftime("%Y%m%d")
    log_file = path / f"RAG-Python_{hostname}_{date_str}.log"
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger
    logger.setLevel(logging.DEBUG)
    fh = logging.FileHandler(log_file, encoding="utf-8")
    fh.setLevel(logging.DEBUG)
    fmt = logging.Formatter("%(asctime)s [%(levelname)s] [%(name)s] %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
    fh.setFormatter(fmt)
    logger.addHandler(fh)
    ch = logging.StreamHandler()
    ch.setLevel(logging.INFO)
    ch.setFormatter(fmt)
    logger.addHandler(ch)
    logger.info("RAG Python logging started; log file: %s", log_file)
    return logger
