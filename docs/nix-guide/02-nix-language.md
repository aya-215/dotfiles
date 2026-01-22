# Nix言語の基礎

## 概要

Nix言語は、設定ファイルやパッケージ定義を記述するための純粋関数型言語です。このセクションでは、Nix言語の基本的な構文とデータ型を学びます。

## なぜNix言語を学ぶのか

- `flake.nix`や`home.nix`を書くために必要
- Nixパッケージをカスタマイズするために必要
- エラーメッセージを理解するために必要

## `nix repl`の使い方

Nix言語を試すには`nix repl`を使います。

```bash
nix repl
```

終了するには`:q`と入力します。

## データ型

### 1. 文字列

```nix
# シングルクォート（推奨）
"hello"

# ダブルクォート（複数行）
''
  multiple
  lines
''

# 文字列補間
"Hello, ${name}"

# パスと文字列の違いに注意
"/home/user"  # 文字列
/home/user    # パス（後述）
```

**nix replで試す:**

```nix
nix-repl> "hello"
"hello"

nix-repl> name = "Nix"

nix-repl> "Hello, ${name}"
"Hello, Nix"
```

### 2. 数値

```nix
# 整数
42

# 負の数
-10

# 浮動小数点数
3.14
```

### 3. ブール

```nix
true
false

# 論理演算
true && false  # false
true || false  # true
!true          # false
```

### 4. null

```nix
null  # 値が存在しないことを表す
```

### 5. パス

```nix
# 絶対パス
/home/user/file.txt

# 相対パス（現在のディレクトリからの相対）
./config.nix
../parent/file.nix

# ホームディレクトリ
~/.config/nvim
```

**注意**: パスは文字列ではなく、Nixが特別に扱う型です。

### 6. リスト

```nix
# 基本的なリスト
[ 1 2 3 ]

# 異なる型を混在可能
[ 1 "hello" true ]

# ネストしたリスト
[ 1 [ 2 3 ] 4 ]

# リスト結合
[ 1 2 ] ++ [ 3 4 ]  # [ 1 2 3 4 ]
```

**nix replで試す:**

```nix
nix-repl> [ 1 2 3 ]
[ 1 2 3 ]

nix-repl> [ 1 2 ] ++ [ 3 4 ]
[ 1 2 3 4 ]
```

### 7. 属性セット（Attribute Set）

最も重要なデータ型です。他の言語でいうオブジェクトや辞書に相当します。

```nix
# 基本的な属性セット
{
  name = "John";
  age = 30;
  active = true;
}

# ネストした属性セット
{
  user = {
    name = "John";
    email = "john@example.com";
  };
  settings = {
    theme = "dark";
  };
}

# 属性へのアクセス
config.user.name
```

**nix replで試す:**

```nix
nix-repl> config = { user = { name = "John"; }; }

nix-repl> config.user.name
"John"
```

## 関数

Nix言語では、すべての関数は1つの引数のみを取ります（カリー化）。

### 1. 基本的な関数定義

```nix
# ラムダ式
x: x + 1

# 使用例
(x: x + 1) 5  # 6
```

**nix replで試す:**

```nix
nix-repl> add1 = x: x + 1

nix-repl> add1 5
6
```

### 2. 複数引数の関数（カリー化）

```nix
# 2つの引数を取る関数
x: y: x + y

# 使用例
add = x: y: x + y
add 3 5  # 8

# 部分適用
add3 = add 3
add3 5  # 8
```

### 3. 属性セットを引数に取る関数

最も一般的なパターンです。

```nix
# 基本
{ name, age }: "Hello, ${name}"

# デフォルト値
{ name, age ? 18 }: "Hello, ${name}, age ${toString age}"

# @パターン（元の属性セット全体を参照）
args@{ name, age }: args

# または
{ name, age, ... }@args: args
```

**nix replで試す:**

```nix
nix-repl> greet = { name, age ? 18 }: "Hello, ${name}, age ${toString age}"

nix-repl> greet { name = "Alice"; }
"Hello, Alice, age 18"

nix-repl> greet { name = "Bob"; age = 25; }
"Hello, Bob, age 25"
```

### 4. 可変長引数（`...`）

すべての属性を受け入れる場合に使用します。

```nix
{ name, ... }: "Hello, ${name}"

# これは余分な属性を無視する
```

**nix replで試す:**

```nix
nix-repl> greet = { name, ... }: "Hello, ${name}"

nix-repl> greet { name = "Alice"; age = 25; city = "Tokyo"; }
"Hello, Alice"
```

## let-in式

ローカル変数を定義するために使用します。

```nix
let
  name = "Alice";
  age = 25;
in
  "Hello, ${name}, age ${toString age}"
```

**nix replで試す:**

```nix
nix-repl> let
            x = 5;
            y = 10;
          in
            x + y
15
```

### ネストしたlet-in

```nix
let
  x = 5;
  y = let
    z = 10;
  in
    x + z;
in
  y * 2  # (5 + 10) * 2 = 30
```

## with式

属性セットのスコープを一時的に開きます。

```nix
let
  config = {
    name = "Alice";
    age = 25;
  };
in
  with config; "Hello, ${name}"  # "Hello, Alice"
```

**注意**: `with`は便利ですが、過度に使用するとコードが読みにくくなります。明示的な参照を推奨することが多いです。

```nix
# 推奨されない
with pkgs; [ git vim ]

# 推奨
[ pkgs.git pkgs.vim ]
```

## inherit

親スコープの変数を属性セットに取り込むための糖衣構文です。

```nix
let
  name = "Alice";
  age = 25;
in
{
  inherit name age;
  # これは以下と同じ
  # name = name;
  # age = age;
}
```

**nix replで試す:**

```nix
nix-repl> let
            x = 5;
            y = 10;
          in
            { inherit x y; }
{ x = 5; y = 10; }
```

### 属性セットからのinherit

```nix
let
  config = { name = "Alice"; age = 25; };
in
{
  inherit (config) name;
  # これは以下と同じ
  # name = config.name;
}
```

## import

他のNixファイルを読み込みます。

```nix
# config.nix
{
  name = "Alice";
  age = 25;
}

# main.nix
let
  config = import ./config.nix;
in
  config.name  # "Alice"
```

## 演算子

### 算術演算子

```nix
1 + 2   # 3
5 - 3   # 2
2 * 3   # 6
10 / 2  # 5
```

### 比較演算子

```nix
1 == 1   # true
1 != 2   # true
1 < 2    # true
2 > 1    # true
2 <= 2   # true
2 >= 1   # true
```

### 論理演算子

```nix
true && false  # false
true || false  # true
!true          # false
```

### 文字列結合

```nix
"Hello" + " " + "World"  # "Hello World"
```

### リスト結合

```nix
[ 1 2 ] ++ [ 3 4 ]  # [ 1 2 3 4 ]
```

### 属性セット結合

```nix
{ a = 1; } // { b = 2; }  # { a = 1; b = 2; }

# 右側が優先される
{ a = 1; } // { a = 2; }  # { a = 2; }
```

## 条件式

```nix
if condition then trueValue else falseValue

# 例
if age >= 18 then "adult" else "minor"
```

**nix replで試す:**

```nix
nix-repl> age = 20

nix-repl> if age >= 18 then "adult" else "minor"
"adult"
```

## 組み込み関数

Nixには多くの組み込み関数があります。よく使うものを紹介します。

### `builtins.toString`

値を文字列に変換します。

```nix
builtins.toString 42  # "42"
toString 42           # builtins. は省略可
```

### `builtins.map`

リストの各要素に関数を適用します。

```nix
map (x: x * 2) [ 1 2 3 ]  # [ 2 4 6 ]
```

### `builtins.filter`

条件に一致する要素のみを抽出します。

```nix
filter (x: x > 2) [ 1 2 3 4 ]  # [ 3 4 ]
```

### `builtins.attrNames`

属性セットのキー一覧を取得します。

```nix
builtins.attrNames { a = 1; b = 2; }  # [ "a" "b" ]
```

## 実践演習

以下を`nix repl`で試してみてください。

### 演習1: 基本的なデータ型

```nix
# 文字列補間を使って自己紹介を作る
let
  name = "あなたの名前";
  age = 25;
in
  "私の名前は${name}で、年齢は${toString age}です"
```

### 演習2: 関数を作る

```nix
# 2つの数を受け取って合計を返す関数
add = x: y: x + y
add 5 10
```

### 演習3: 属性セットを使う

```nix
# ユーザー情報を属性セットで表現
user = {
  name = "Alice";
  email = "alice@example.com";
  settings = {
    theme = "dark";
    language = "ja";
  };
}

# 属性にアクセス
user.settings.theme
```

### 演習4: let-inとinherit

```nix
let
  name = "Bob";
  age = 30;
  email = "bob@example.com";
in
{
  inherit name age;
  contact = email;
}
```

### 演習5: リストと組み込み関数

```nix
# 数値のリストを2倍にする
numbers = [ 1 2 3 4 5 ]
map (x: x * 2) numbers

# 偶数のみを抽出
filter (x: x > 0 && x < 10) [ -5 3 15 7 ]
```

## 確認ポイント

以下の質問に答えられるか確認してください。

- [ ] `nix repl`で基本的なデータ型（文字列、数値、リスト、属性セット）を扱えますか？
- [ ] 関数を定義して呼び出せますか？
- [ ] 属性セットを引数に取る関数を書けますか？
- [ ] `let-in`式の役割を説明できますか？
- [ ] `inherit`の使い方を理解していますか？
- [ ] `map`や`filter`などの組み込み関数を使えますか？

## よくある間違い

### 1. セミコロンの忘れ

```nix
# ❌ 間違い
{ name = "Alice" age = 25 }

# ✅ 正しい
{ name = "Alice"; age = 25; }
```

### 2. 文字列補間で`toString`を忘れる

```nix
# ❌ 間違い（数値は直接補間できない）
"Age: ${age}"

# ✅ 正しい
"Age: ${toString age}"
```

### 3. `with`の過度な使用

```nix
# ❌ 推奨されない（どこから来たか不明確）
with pkgs; with lib; mkIf enable [ git vim ]

# ✅ 推奨（明示的）
lib.mkIf config.myModule.enable [ pkgs.git pkgs.vim ]
```

## 次のステップ

Nix言語の基礎を理解したら、次は核心概念を学びましょう。

→ [03. 核心概念](./03-core-concepts.md)

## 参考資料

- [Nix Language Basics - nix.dev](https://nix.dev/tutorials/nix-language)
- [Nix Manual - Language Constructs](https://nixos.org/manual/nix/stable/language/)
- [Nix Pills - Basics of the Language](https://nixos.org/guides/nix-pills/basics-of-language)
