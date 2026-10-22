{
  description = "Personal dotfiles configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    glauncher = {
      url = "git+ssh://git@github-aya215/aya-215/glauncher";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # deno 2.9.7 は zeno.zsh が使う @db/sqlite の FFI 読み込みでセグフォするため、2.9.2 の rev に固定する
    nixpkgs-deno.url = "github:NixOS/nixpkgs/18b9261cb3294b6d2a06d03f96872827b8fe2698";
  };

  outputs = { self, nixpkgs, home-manager, glauncher, nixpkgs-deno }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      pkgs-deno = nixpkgs-deno.legacyPackages.${system};
    in
    {
      homeConfigurations."aya" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        extraSpecialArgs = {
          inherit glauncher pkgs-deno;
        };

        modules = [
          ./home.nix
        ];
      };
    };
}
