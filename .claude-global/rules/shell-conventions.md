# シェルスクリプト規約

## 基本
- shebang: `#!/bin/bash` または `#!/usr/bin/env bash`
- set -euo pipefail を使用
- ShellCheck準拠

## 変数
- 環境変数: UPPER_SNAKE_CASE
- ローカル変数: lower_snake_case
- 配列使用時は `"${array[@]}"` でクォート

## 関数
- 名前: lower_snake_case
- localで変数宣言
- ドキュメントコメント必須
