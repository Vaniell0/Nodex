{
  description = "Nodex - Declarative HTML/DOCX/ODT generation (Ruby DSL + C++20 core)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems
        (system: f (import nixpkgs { inherit system; }));

      mkProject = pkgs:
        let
          stdenv = pkgs.gcc14Stdenv;     # C++20 достаточно gcc14
          lib    = pkgs.lib;
          isDarwin = pkgs.stdenv.isDarwin;

          rubyLib       = ./ruby/lib;
          officeRubyLib = ./nodex-office/lib;
          # Combined load path so `require 'nodex'` and `require 'nodex/office'`
          # both resolve under one RUBYLIB.
          rubyLibAll = "${rubyLib}:${officeRubyLib}";

          src = lib.cleanSourceWith {
            src = ./.;
            filter = path: type:
              let b = builtins.baseNameOf path; in
              !(b == "build" || b == "result" || b == ".git" || b == ".direnv");
          };

          nativeDeps = with pkgs; [ cmake pkg-config ];
          buildDeps  = with pkgs; [ fmt nlohmann_json inja ];

          nodex-cpp = stdenv.mkDerivation {
            pname   = "nodex";
            version = "1.2.0";
            inherit src;

            nativeBuildInputs = nativeDeps;
            buildInputs       = buildDeps;

            cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" "-DNodex_BUILD_PDF=OFF" ];

            meta = {
              description = "Declarative HTML/document generation — C++ core";
              license     = lib.licenses.asl20;
              platforms   = lib.platforms.unix;
            };
          };

          nodex-ruby = pkgs.writeShellApplication {
            name = "nodex-ruby";
            runtimeInputs = [ pkgs.ruby ];
            text = ''export RUBYLIB="${rubyLibAll}:''${RUBYLIB:-}"; exec ruby "$@"'';
          };

          nodex-cli = pkgs.writeShellApplication {
            name = "nodex";
            runtimeInputs = [ pkgs.ruby ];
            text = ''
              export RUBYLIB="${rubyLibAll}:''${RUBYLIB:-}"
              exec ruby -r nodex -e "Nodex::CLI.run(ARGV)" -- "$@"
            '';
          };

          nodex = pkgs.symlinkJoin {
            name = "nodex-1.2.0";
            paths = [ nodex-cpp nodex-cli nodex-ruby ];
            meta.description = "Nodex — declarative HTML/DOCX/ODT generation";
          };

          mkRubyApp = script: pkgs.writeShellScript "nodex-${script}" ''
            export RUBYLIB="${rubyLibAll}:''${RUBYLIB:-}"
            exec ${pkgs.ruby}/bin/ruby ${./examples/ruby + "/${script}.rb"} "$@"
          '';
        in { inherit nodex nodex-cpp nodex-cli nodex-ruby stdenv isDarwin mkRubyApp; };

    in {
      packages = forAllSystems (pkgs:
        let p = mkProject pkgs; in {
          default = p.nodex;
          cpp     = p.nodex-cpp;
        });

      apps = forAllSystems (pkgs:
        let p = mkProject pkgs; in {
          default = { type = "app"; program = "${p.nodex-cli}/bin/nodex"; };
          ruby    = { type = "app"; program = "${p.nodex-ruby}/bin/nodex-ruby"; };
          serve   = { type = "app"; program = toString (p.mkRubyApp "server"); };
          dev     = { type = "app"; program = toString (p.mkRubyApp "server"); };
          demo    = { type = "app"; program = toString (p.mkRubyApp "demo"); };
        });

      devShells = forAllSystems (pkgs:
        let p = mkProject pkgs; in {
          default = (pkgs.mkShell.override { inherit (p) stdenv; }) {
            inputsFrom = [ p.nodex-cpp ];
            packages   = [ pkgs.ruby ]
              ++ nixpkgs.lib.optionals (!p.isDarwin) [ pkgs.gdb pkgs.valgrind ];
            shellHook = ''
              export RUBYLIB="${toString ./ruby/lib}:${toString ./nodex-office/lib}:$RUBYLIB"
              echo ""
              echo "Nodex devShell ($(g++ --version | head -1))"
              echo "  nix run            - nodex CLI (build/serve/new)"
              echo "  nix run .#serve    - HTTP server"
              echo "  nix run .#dev      - dev server (hot-reload)"
              echo "  nix run .#ruby     - ruby with Nodex"
              echo "  nix run .#demo     - Ruby demo"
              echo ""
            '';
          };
        });

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);
    };
}
