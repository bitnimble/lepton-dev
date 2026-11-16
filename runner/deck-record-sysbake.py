#!/usr/bin/env python3
"""Runs `lepton-customize sysbake` on STAGE with a prebuilt sysbake in place of its isolated helper.

The bundled helper needs rootless podman, which sysbox can't nest, so runner/sysbake-rootful.sh bakes instead;
everything else (validation, digests, STAGE.json record) is lepton-customize's own code.
Usage (as an unprivileged user): deck-record-sysbake.py STAGE PREBAKED   (PREBAKED holds sysbake/ + sysbake.xattrs)
"""
import importlib.machinery
import importlib.util
import json
import runpy
import subprocess
import sys
import types
from pathlib import Path


def main(stage, prebaked):
    tools = stage / 'compat_tool/tools'
    loader = importlib.machinery.SourceFileLoader('lepton_customize', str(tools / 'lepton-customize'))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    core = importlib.util.module_from_spec(spec)
    loader.exec_module(core)
    sys.modules[loader.name] = core
    companion = runpy.run_path(str(tools / 'lepton_customize_package.py'))

    def helper(argv, _):
        if '--execute' in argv:
            subprocess.run(['cp', '-a', str(prebaked / 'sysbake'), str(prebaked / 'sysbake.xattrs'),
                            str(stage / 'compat_tool/')], check=True)

    # run_path returned a copy; the functions read their real module globals
    module = companion['main'].__globals__
    module['host_problems'] = lambda *_args, **_kwargs: []
    module['runpy'] = types.SimpleNamespace(run_path=lambda _path: {'command': helper})
    companion['main'](['--execute', '--stage-dir', str(stage)], core, 'sysbake')

    state = json.loads((stage / 'STAGE.json').read_text())
    state['sysbake']['generator'] = 'lepton sysbake, rootful (lepton-dev runner), validated by lepton-customize'
    companion['write_stage'](stage, state)


if __name__ == '__main__':
    main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
