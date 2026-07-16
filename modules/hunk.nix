{ config, pkgs, ... }:

# hunk (hunkdiff) — review-first ターミナルdiffビューア
#
# なぜ pkgs.hunk（nixpkgs版）を使わないか:
#   nixpkgs の hunk は bun --compile で作られた単体ネイティブELFで、
#   このWSL環境では起動時に SIGSEGV (SEGV_MAPERR) で即クラッシュする。
#
# なぜ buildNpmPackage + bun wrapper か:
#   npm版 hunkdiff は bin/hunk.cjs が「native単体バイナリ → bun main.js → エラー」
#   の順でランタイムを探すランチャー。native単体バイナリ(hunkdiff-linux-x64)も
#   同じくSIGSEGVするので、それを掴ませずに bun で dist/npm/main.js を直接叩く。
#   main.js は @opentui/core-linux-x64 のnative FFIを実行時ロードするため、
#   optional依存を含む node_modules 一式と bun ランタイムが必要（実測で確認済み）。
let
  version = "0.17.1";

  # npm tarball（package/ プレフィックスを剥がす）
  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/hunkdiff/-/hunkdiff-${version}.tgz";
    hash = "sha256-skCmwbN5wY9ZBUueBlwj1uX8WaPk+B+WEj6JyoI2k6o=";
  };

  hunk = pkgs.buildNpmPackage {
    pname = "hunk";
    inherit version src;

    # tarball には lock が無いため dotfiles 側で生成したものを注入する。
    # optional deps（native FFI: @opentui/core-linux-x64 等）を含む lock。
    postPatch = ''
      cp ${./hunk-package-lock.json} package-lock.json
    '';

    npmDepsHash = "sha256-48UQc9c9OMXoI8Wxn2TYfJKQbqKtv4kg/iUFj16Cwbg=";

    # このパッケージにビルドステップは無い（配布物は既にビルド済み dist/）
    dontNpmBuild = true;

    # postinstall 等でネットワークを触らせない
    npmFlags = [ "--ignore-scripts" ];

    nativeBuildInputs = [ pkgs.makeWrapper ];

    # buildNpmPackage の bin 自動リンク（hunk.cjsランチャー）は使わず、
    # bun で main.js を直接起動する wrapper を自前で用意する。
    dontNpmInstall = true;

    installPhase = ''
      runHook preInstall

      # buildNpmPackage は hunkdiff 本体を展開ディレクトリ直下に置き、
      # 依存を node_modules/ に入れる（main.js は dist/npm/main.js）。
      mkdir -p $out/lib/hunk
      cp -r . $out/lib/hunk/app
      mkdir -p $out/bin

      makeWrapper ${pkgs.bun}/bin/bun $out/bin/hunk \
        --add-flags "$out/lib/hunk/app/dist/npm/main.js" \
        --unset HUNK_BIN_PATH

      runHook postInstall
    '';

    meta = with pkgs.lib; {
      description = "review-first ターミナルdiffビューア（bun runtime, WSL native-crash回避版）";
      homepage = "https://github.com/modem-dev/hunk";
      license = licenses.mit;
      platforms = [ "x86_64-linux" ];
      mainProgram = "hunk";
    };
  };
in
{
  home.packages = [ hunk ];
}
