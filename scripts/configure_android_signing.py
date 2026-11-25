#!/usr/bin/env python3
"""Configure the Pili-- release signing secrets from a maintainer's local keystore."""
import argparse
import base64
import getpass
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import warnings

REPO = 'Ktclat/Pili--'
PIN = 'ANDROID_RELEASE_CERT_SHA256'
VARIABLES = f'repos/{REPO}/actions/variables'


def run(args, error, *, data=b'', env=None):
    try:
        result = subprocess.run(args, input=data, capture_output=True, env=env)
    except FileNotFoundError:
        raise RuntimeError(f'找不到 {args[0]}，请将它加入 PATH。') from None
    if result.returncode:
        # Child diagnostics may contain credentials. Only show our own messages.
        raise RuntimeError(error)
    return result


def read_pin():
    # A failed lookup may mean insufficient access. A successful list can
    # distinguish an absent variable, including when the repository has many pages.
    result = run(['gh', 'api', '--paginate', '--hostname', 'github.com',
                  VARIABLES + '?per_page=100', '--jq',
                  f'.variables[] | select(.name == "{PIN}") | {{value}}'],
                 f'无法读取 {REPO} 的 Actions 变量，请核对 gh 登录账号和 Variables 权限。')
    return json.loads(result.stdout)['value'] if result.stdout.strip() else None


def configure(path, alias):
    existing = read_pin()
    if not path.is_file() or path.stat().st_size > 36 * 1024:
        raise RuntimeError('请选择可读取的专用密钥库，Base64 编码后须在 GitHub 的 48 KiB 限制内。')
    keystore = path.read_bytes()
    with warnings.catch_warnings():
        # Fail before getpass can fall back to echoing a password.
        warnings.simplefilter('error', getpass.GetPassWarning)
        store_password = getpass.getpass('密钥库密码：')
        key_password = getpass.getpass('条目密码（相同请回车）：') or store_password
    if not store_password:
        raise RuntimeError('密钥库密码不能为空。')
    env = {**os.environ, 'PILI_STORE_PASSWORD': store_password,
           'PILI_ENTRY_PASSWORD': key_password}
    options = ['-keystore', str(path), '-alias', alias, '-storepass:env', 'PILI_STORE_PASSWORD']
    cert = run(['keytool', '-exportcert', *options],
               '无法导出公开证书，请核对密钥库、别名和库密码。', env=env).stdout
    digest = hashlib.sha256(cert).hexdigest()
    if existing is not None and existing.lower() != digest:
        raise RuntimeError(f'公开签名指纹与仓库已有的 {PIN} 不同，配置已停止。')

    # Prove this is a private-key entry and its password works. The temporary
    # public certificate request is discarded and never sent to GitHub.
    check = run(['keytool', '-J-Duser.language=en', '-certreq', *options,
                 '-keypass:env', 'PILI_ENTRY_PASSWORD', '-file', os.devnull],
                '无法使用所选私钥，请核对别名和条目密码。', env=env)
    if b'Ignoring user-specified' in check.stderr:
        raise RuntimeError('此密钥库要求库密码与条目密码相同。')

    for name, value in [
        ('ANDROID_RELEASE_KEYSTORE_BASE64', base64.b64encode(keystore)),
        ('ANDROID_RELEASE_STORE_PASSWORD', store_password.encode()),
        ('ANDROID_RELEASE_KEY_ALIAS', alias.encode()),
        ('ANDROID_RELEASE_KEY_PASSWORD', key_password.encode()),
    ]:
        run(['gh', 'secret', 'set', name, '--repo', 'github.com/' + REPO],
            f'无法写入 {name}。请核对 Actions Secrets 写权限，再用同一密钥库重新运行。',
            data=value)
    if existing is None:
        # POST creates only. A concurrent maintainer cannot be silently overwritten.
        run(['gh', 'api', '--method', 'POST', '--hostname', 'github.com', VARIABLES, '-f', f'name={PIN}',
             '-f', f'value={digest}'],
            f'未能创建 {PIN}。请核对仓库变量及写权限，再用同一密钥库重新运行。')
    print(f'{REPO} 已配置发布签名。证书 SHA-256 为 {digest}')


def main():
    parser = argparse.ArgumentParser(description='从维护者电脑向 Ktclat/Pili-- 配置发布签名。')
    parser.add_argument('--keystore', type=Path, required=True,
                        help='经备份、仅含本项目发行密钥的密钥库（整个文件将作为 secret 上传）')
    parser.add_argument('--alias', required=True, help='发行私钥条目的别名')
    args = parser.parse_args()
    try:
        configure(args.keystore.expanduser(), args.alias)
    except (getpass.GetPassWarning, EOFError):
        sys.exit('请在可以隐藏输入的交互终端中运行。')
    except OSError:
        sys.exit('无法读取密钥库或执行本机工具，请核对文件和工具权限。')
    except RuntimeError as error:
        sys.exit(str(error))


if __name__ == '__main__':
    main()
