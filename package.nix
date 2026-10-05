{
  lib,
  stdenv,
  stdenvNoCC,
  buildGoModule,
  bun,
  nodejs,
  fetchFromGitHub,
  writableTmpDirAsHomeHook,
}:

let
  version = "2.1.0";

  src = fetchFromGitHub {
    owner = "mr-karan";
    repo = "logchef";
    tag = "v${version}";
    hash = "sha256-3KE3S0jrjweonEHtTSk/xfMmbKHG0b8+GsDKZbBk6KM=";
  };

  nodeModules = stdenvNoCC.mkDerivation {
    pname = "logchef-frontend-node-modules";
    inherit src version;

    nativeBuildInputs = [
      bun
      writableTmpDirAsHomeHook
    ];

    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
      "GIT_PROXY_COMMAND"
      "SOCKS_SERVER"
    ];

    dontConfigure = true;
    dontFixup = true;

    buildPhase = ''
      runHook preBuild

      cd frontend
      export BUN_INSTALL_CACHE_DIR="$(mktemp -d)"
      bun install \
        --backend=copyfile \
        --cpu="*" \
        --os="*" \
        --frozen-lockfile \
        --ignore-scripts \
        --no-progress

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -R node_modules "$out/"

      runHook postInstall
    '';

    outputHash = "sha256-NVIen3WD9ml2RxzgXnCcyyZSoLqqj5XIHW6aGsEJhss=";
    outputHashMode = "recursive";
  };
in
buildGoModule (finalAttrs: {
  pname = "logchef";
  inherit src version;

  vendorHash = "sha256-HZq+Yp+WqthWR89L9+bgKbIIbQ7yppwpc53jbGDr0K0=";

  env.CGO_ENABLED = 0;

  nativeBuildInputs = [
    bun
    nodejs
    writableTmpDirAsHomeHook
  ];

  subPackages = [ "cmd/server" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.buildString=v${finalAttrs.version}"
    "-X main.versionString=v${finalAttrs.version}"
  ];

  preBuild = ''
    cp -R ${nodeModules}/node_modules frontend/node_modules
    chmod -R u+w frontend/node_modules
    patchShebangs frontend/node_modules
    (cd frontend && bun ./node_modules/vite/bin/vite.js build)
  '';

  overrideModAttrs = _final: _previous: {
    preBuild = "";
  };

  doCheck = true;

  checkPhase = ''
    runHook preCheck

    # Vitest's jsdom workers require Node's EventTarget implementation.
    (cd frontend && node ./node_modules/vitest/vitest.mjs run)
    go test ./...

    runHook postCheck
  '';

  postInstall = ''
    mv "$out/bin/server" "$out/bin/logchef"
  '';

  passthru = {
    inherit nodeModules;
    updateScript = ./update.sh;
  };

  meta = {
    description = "Self-hosted log analytics and log explorer for ClickHouse and VictoriaLogs";
    homepage = "https://github.com/mr-karan/logchef";
    changelog = "https://github.com/mr-karan/logchef/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    mainProgram = "logchef";
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
