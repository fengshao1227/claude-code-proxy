# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec file for claude-code-proxy
# Build: uv run pyinstaller claude-code-proxy.spec
# Output: dist/claude-code-proxy (single file executable)

import sys
from PyInstaller.utils.hooks import collect_submodules

block_cipher = None

# Collect all submodules for packages that use dynamic imports
uvicorn_hidden = collect_submodules('uvicorn')
fastapi_hidden = collect_submodules('fastapi')

a = Analysis(
    ['src/main.py'],
    pathex=['.'],
    binaries=[],
    datas=[
        ('src', 'src'),
        ('.env.example', '.'),
    ],
    hiddenimports=[
        # Project modules
        'src',
        'src.main',
        'src.api.endpoints',
        'src.core.config',
        'src.core.client',
        'src.core.constants',
        'src.core.logging',
        'src.core.model_manager',
        'src.models.claude',
        'src.models.openai',
        'src.conversion.request_converter',
        'src.conversion.response_converter',
        # Uvicorn internals
        'uvicorn.logging',
        'uvicorn.loops',
        'uvicorn.loops.auto',
        'uvicorn.loops.asyncio',
        'uvicorn.protocols',
        'uvicorn.protocols.http',
        'uvicorn.protocols.http.auto',
        'uvicorn.protocols.http.h11_impl',
        'uvicorn.protocols.http.httptools_impl',
        'uvicorn.protocols.websockets',
        'uvicorn.protocols.websockets.auto',
        'uvicorn.protocols.websockets.wsproto_impl',
        'uvicorn.lifespan',
        'uvicorn.lifespan.on',
        'uvicorn.lifespan.off',
        # FastAPI
        'fastapi.openapi.utils',
        'fastapi.responses',
        'fastapi.routing',
        'fastapi.middleware',
        'fastapi.middleware.cors',
        # Pydantic
        'pydantic',
        'pydantic.v1',
        'pydantic._internal',
        # OpenAI SDK
        'openai',
        'openai._exceptions',
        'openai.types',
        'openai.types.chat',
        # Dotenv
        'dotenv',
        # Async support
        'asyncio',
        'httptools',
        'websockets',
        'h11',
    ] + uvicorn_hidden + fastapi_hidden,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        'tkinter',
        'matplotlib',
        'numpy',
        'scipy',
        'PIL',
        'cv2',
        'torch',
        'tensorflow',
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='claude-code-proxy',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
