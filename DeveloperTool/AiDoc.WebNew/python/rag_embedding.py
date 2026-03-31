"""
Bundle-local ONNX embedding so the model lives inside AiDoc.Python and the whole tree is portable.
Use this instead of chromadb.utils.embedding_functions.ONNXMiniLM_L6_V2 so one folder (venv + model)
can be copied to an offline server as a single image.
"""
from pathlib import Path

from chromadb.utils.embedding_functions import ONNXMiniLM_L6_V2

# Store ONNX model inside the bundle; no dependency on %USERPROFILE%\\.cache
_BASE = Path(__file__).resolve().parent
BUNDLE_ONNX_PATH = _BASE / ".onnx_models" / "all-MiniLM-L6-v2"


class LocalONNXMiniLM_L6_V2(ONNXMiniLM_L6_V2):
    """Same as ONNXMiniLM_L6_V2 but downloads/caches the model under AiDoc.Python/.onnx_models/."""

    DOWNLOAD_PATH = BUNDLE_ONNX_PATH
