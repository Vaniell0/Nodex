{
  description = "Nodex - Declarative HTML/DOCX/ODT generation (Ruby DSL + C++20 core)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib  = pkgs.lib;
        isDarwin = pkgs.stdenv.isDarwin;

        rubyLib = ./ruby/lib;

        cleanSrc = lib.cleanSourceWith {
          src = ./.;
          filter = path: type:
            let b = builtins.baseNameOf path; in
            !(b == "build" || b == "result" || b == ".git" || b == ".direnv");
        };

        buildDeps  = with pkgs; [ fmt nlohmann_json inja ];
        nativeDeps = with pkgs; [ cmake pkg-config ];
        ncpuCmd = if isDarwin then "sysctl -n hw.ncpu" else "nproc";

        # C++ core library (SSG, embed tools — no libharu, PDF goes through DOCX)
        nodex-cpp = pkgs.stdenv.mkDerivation {
          pname   = "nodex";
          version = "1.2.0";
          src     = cleanSrc;

          nativeBuildInputs = nativeDeps;
          buildInputs       = buildDeps;

          cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" "-DNodex_BUILD_PDF=OFF" ];

          meta = {
            description = "Declarative HTML/document generation — C++ core";
            license     = lib.licenses.asl20;
          };
        };

        # Ruby DSL — wrapper that makes `ruby -r nodex` work from anywhere
        nodex-ruby = pkgs.writeShellApplication {
          name = "nodex-ruby";
          runtimeInputs = [ pkgs.ruby ];
          text = ''export RUBYLIB="${rubyLib}:''${RUBYLIB:-}"; exec ruby "$@"'';
        };

        # CLI: nodex build | serve | new | new page | new component
        nodex-cli = pkgs.writeShellApplication {
          name = "nodex";
          runtimeInputs = [ pkgs.ruby ];
          text = ''
            export RUBYLIB="${rubyLib}:''${RUBYLIB:-}"
            exec ruby -r nodex -e "Nodex::CLI.run(ARGV)" -- "$@"
          '';
        };

        # Combined package: C++ binaries + Ruby CLI + Ruby wrapper
        nodex = pkgs.symlinkJoin {
          name = "nodex-1.2.0";
          paths = [ nodex-cpp nodex-cli nodex-ruby ];
          meta.description = "Nodex — declarative HTML/DOCX/ODT generation";
        };

      in {
        packages = {
          default = nodex;
          cpp = nodex-cpp;
        };

        apps = {
          default = {
            type    = "app";
            program = "${nodex-cli}/bin/nodex";
          };
          ruby = {
            type    = "app";
            program = "${nodex-ruby}/bin/nodex-ruby";
          };
          serve = {
            type    = "app";
            program = toString (pkgs.writeShellScript "nodex-serve" ''
              export RUBYLIB="${rubyLib}:''${RUBYLIB:-}"
              exec ${pkgs.ruby}/bin/ruby ${./examples/ruby/server.rb} "$@"
            '');
          };
          dev = {
            type    = "app";
            program = toString (pkgs.writeShellScript "nodex-dev" ''
              export RUBYLIB="${rubyLib}:''${RUBYLIB:-}"
              exec ${pkgs.ruby}/bin/ruby ${./examples/ruby/server.rb} --dev "$@"
            '');
          };
          demo = {
            type    = "app";
            program = toString (pkgs.writeShellScript "nodex-demo" ''
              export RUBYLIB="${rubyLib}:''${RUBYLIB:-}"
              exec ${pkgs.ruby}/bin/ruby ${./examples/ruby/demo.rb}
            '');
          };
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ nodex-cpp ];
          packages   = [ pkgs.ruby ]
            ++ lib.optionals (!isDarwin) [ pkgs.gdb pkgs.valgrind ];

          shellHook = ''
            export RUBYLIB="${rubyLib}:$RUBYLIB"
            echo ""
            echo "Nodex devShell"
            echo "  nix run            - nodex CLI (build/serve/new)"
            echo "  nix run .#serve    - HTTP server"
            echo "  nix run .#dev      - dev server (hot-reload)"
            echo "  nix run .#ruby     - ruby with Nodex"
            echo "  nix run .#demo     - Ruby demo"
            echo ""
          '';
        };
      }
    );
}
