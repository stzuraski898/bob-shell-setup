# -*- mode: python ; coding: utf-8 -*-

import os
import sys

block_cipher = None

datas = [
    ('logo.png', '.'),
    ('logo.gif', '.'),
    ('bob-agents-gui.desktop', '.'),
    ('launch-bob-agents.sh', '.'),
]

# Only include files that actually exist
datas = [(src, dst) for src, dst in datas if os.path.exists(src)]

a = Analysis(
    ['bob-agents-gui.py'],
    pathex=[],
    binaries=[],
    datas=datas,
    hiddenimports=[
        'PIL',
        'PIL._tkinter_finder',
        'tkinter',
        'tkinter.filedialog',
        'tkinter.font',
        'tkinter.scrolledtext',
        'tkinter.messagebox',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
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
    name='bob-agents-gui',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon='logo.png' if os.path.exists('logo.png') else None,
)

if sys.platform == 'darwin':
    app = BUNDLE(
        exe,
        name='BobAgentLauncher.app',
        icon='logo.png' if os.path.exists('logo.png') else None,
        bundle_identifier='com.bob.agents.gui',
    )
