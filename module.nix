{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    concatMapStringsSep
    hasAttrByPath
    imap0
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    optional
    optionalAttrs
    optionalString
    recursiveUpdate
    types
    ;

  cfg = config.services.logchef;
  toml = pkgs.formats.toml { };

  forbiddenSettingPaths = [
    [
      "auth"
      "api_token_secret"
    ]
    [
      "auth"
      "local"
      "admin_password"
    ]
    [
      "oidc"
      "client_secret"
    ]
    [
      "postgres"
      "dsn"
    ]
    [
      "clickhouse"
      "password"
    ]
    [
      "ai"
      "api_key"
    ]
    [
      "alerts"
      "smtp_password"
    ]
    [
      "demo"
      "provisioning_token"
    ]
  ];

  sensitiveNames = [
    "api_key"
    "api_token_secret"
    "client_secret"
    "dsn"
    "password"
    "provisioning_token"
    "smtp_password"
    "token"
  ];

  findSensitivePaths =
    path: value:
    if builtins.isAttrs value then
      lib.concatLists (
        mapAttrsToList (
          name: child:
          if builtins.elem name sensitiveNames then
            [ (path ++ [ name ]) ]
          else
            findSensitivePaths (path ++ [ name ]) child
        ) value
      )
    else if builtins.isList value then
      lib.concatLists (
        imap0 (
          index: child:
          findSensitivePaths (
            path
            ++ [
              toString
              index
            ]
          ) child
        ) value
      )
    else
      [ ];

  forbiddenSettings = lib.unique (
    builtins.filter (path: hasAttrByPath path cfg.settings) forbiddenSettingPaths
    ++ findSensitivePaths [ ] cfg.settings
  );
  showPath = path: concatMapStringsSep "." (x: x) path;

  generatedSettings = recursiveUpdate cfg.settings (
    {
      server = {
        host = cfg.listenAddress;
        port = cfg.port;
      };
      sqlite.path = "/var/lib/logchef/logchef.db";
      auth = {
        admin_emails = cfg.adminEmails;
        local.enabled = cfg.localAuth.enable;
      }
      // optionalAttrs (cfg.localAuth.adminEmail != null) {
        local.admin_email = cfg.localAuth.adminEmail;
      };
    }
    // optionalAttrs (cfg.provisioningFile != null) {
      provisioning.file = cfg.provisioningFile;
    }
  );

  configFile = toml.generate "logchef.toml" generatedSettings;

  credentialPairs = mapAttrsToList (environment: name: {
    inherit environment name;
  }) cfg.credentialNames;

  loadedCredentialPairs = imap0 (index: pair: pair // { name = "secret-${toString index}"; }) (
    mapAttrsToList (environment: path: {
      inherit environment path;
    }) cfg.credentialFiles
  );

  allCredentialPairs = credentialPairs ++ loadedCredentialPairs;

  startScript = pkgs.writeShellScript "logchef-start" ''
    set -euo pipefail

    ${concatMapStringsSep "\n" (pair: ''
      export ${pair.environment}="$(< "$CREDENTIALS_DIRECTORY/${pair.name}")"
    '') allCredentialPairs}
    ${optionalString (cfg.provisioningCredentialFile != null) ''
      export LOGCHEF_PROVISIONING__FILE="$CREDENTIALS_DIRECTORY/provisioning.toml"
    ''}

    exec ${lib.getExe cfg.package} -config ${configFile}
  '';

  secretAvailable =
    environment:
    cfg.environmentFile != null
    || builtins.hasAttr environment cfg.credentialFiles
    || builtins.hasAttr environment cfg.credentialNames;
in
{
  options.services.logchef = {
    enable = mkEnableOption "Logchef log analytics server";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "Logchef package to run.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address on which Logchef listens.";
    };

    port = mkOption {
      type = types.port;
      default = 8125;
      description = "TCP port on which Logchef listens.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the Logchef port in the firewall.";
    };

    adminEmails = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "admin@example.com" ];
      description = "Email addresses granted Logchef administrator access.";
    };

    localAuth = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Logchef's built-in email and password authentication.";
      };

      adminEmail = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "admin@example.com";
        description = "Optional local bootstrap administrator email.";
      };
    };

    settings = mkOption {
      type = types.submodule {
        freeformType = toml.type;
      };
      default = { };
      example = {
        server = {
          frontend_url = "https://logs.example.com";
          secure_cookie = true;
          trusted_proxies = [ "127.0.0.1" ];
        };
        oidc = {
          provider_url = "https://id.example.com";
          auth_url = "https://id.example.com/oauth/v2/authorize";
          token_url = "https://id.example.com/oauth/v2/token";
          client_id = "logchef";
          redirect_url = "https://logs.example.com/api/v1/auth/callback";
        };
        ai.enabled = false;
      };
      description = ''
        Non-secret Logchef configuration written as TOML in the Nix store.
        `server.host`, `server.port`, `sqlite.path`, administrator emails, and
        local-auth enablement are controlled by dedicated module options.
        Secret-bearing fields are rejected; use `environmentFile`,
        `credentialFiles`, or `credentialNames` for those values.
      '';
    };

    environmentFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/secrets/logchef.env";
      description = ''
        Runtime systemd EnvironmentFile containing secret `LOGCHEF_*` values.
        The file must not be in the Nix store. At minimum it normally defines
        `LOGCHEF_AUTH__API_TOKEN_SECRET`.
      '';
    };

    credentialFiles = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        LOGCHEF_AUTH__API_TOKEN_SECRET = "/run/secrets/logchef-api-token-secret";
        LOGCHEF_OIDC__CLIENT_SECRET = "/run/secrets/logchef-oidc-client-secret";
      };
      description = ''
        Mapping from `LOGCHEF_*` environment variables to runtime files loaded
        with systemd `LoadCredential=`. Each file's contents become the value
        of its environment variable without entering the Nix store.
      '';
    };

    credentialNames = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example.LOGCHEF_AUTH__API_TOKEN_SECRET = "logchef-api-token-secret";
      description = ''
        Mapping from `LOGCHEF_*` environment variables to credential names
        supplied independently to the unit, for example with
        `LoadCredentialEncrypted=` in a systemd service override.
      '';
    };

    provisioningFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/secrets/logchef-provisioning.toml";
      description = ''
        Runtime path to an upstream provisioning TOML file. Use this to
        declaratively provision external ClickHouse sources when the file is
        already made readable to the dynamic service user. It must not reside
        in the Nix store because datasource credentials may be present.
      '';
    };

    provisioningCredentialFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/secrets/logchef-provisioning.toml";
      description = ''
        Runtime provisioning TOML loaded as a systemd credential. Logchef is
        pointed at the private credential copy on service startup. This is the
        preferred integration for declarative external ClickHouse sources.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.adminEmails != [ ];
        message = "services.logchef.adminEmails must contain at least one administrator email";
      }
      {
        assertion = secretAvailable "LOGCHEF_AUTH__API_TOKEN_SECRET";
        message = "provide LOGCHEF_AUTH__API_TOKEN_SECRET via services.logchef.environmentFile, credentialFiles, or credentialNames";
      }
      {
        assertion = cfg.localAuth.adminEmail == null || cfg.localAuth.enable;
        message = "services.logchef.localAuth.adminEmail requires localAuth.enable = true";
      }
      {
        assertion =
          cfg.localAuth.adminEmail == null || secretAvailable "LOGCHEF_AUTH__LOCAL__ADMIN_PASSWORD";
        message = "a local bootstrap admin requires LOGCHEF_AUTH__LOCAL__ADMIN_PASSWORD via a runtime secret option";
      }
      {
        assertion = forbiddenSettings == [ ];
        message = "services.logchef.settings contains secret-bearing paths: ${
          concatMapStringsSep ", " showPath forbiddenSettings
        }";
      }
      {
        assertion = cfg.environmentFile == null || !lib.hasPrefix builtins.storeDir cfg.environmentFile;
        message = "services.logchef.environmentFile must not point into the Nix store";
      }
      {
        assertion = builtins.all (path: !lib.hasPrefix builtins.storeDir path) (
          builtins.attrValues cfg.credentialFiles
        );
        message = "services.logchef.credentialFiles values must not point into the Nix store";
      }
      {
        assertion = cfg.provisioningFile == null || !lib.hasPrefix builtins.storeDir cfg.provisioningFile;
        message = "services.logchef.provisioningFile must not point into the Nix store";
      }
      {
        assertion =
          cfg.provisioningCredentialFile == null
          || !lib.hasPrefix builtins.storeDir cfg.provisioningCredentialFile;
        message = "services.logchef.provisioningCredentialFile must not point into the Nix store";
      }
      {
        assertion = !(cfg.provisioningFile != null && cfg.provisioningCredentialFile != null);
        message = "choose either services.logchef.provisioningFile or provisioningCredentialFile, not both";
      }
      {
        assertion = builtins.all (name: builtins.match "LOGCHEF_[A-Z0-9_]+" name != null) (
          builtins.attrNames cfg.credentialFiles ++ builtins.attrNames cfg.credentialNames
        );
        message = "services.logchef credential keys must be valid nested LOGCHEF_* environment variable names";
      }
      {
        assertion = builtins.all (name: builtins.match "[A-Za-z0-9_.-]+" name != null) (
          builtins.attrValues cfg.credentialNames
        );
        message = "services.logchef.credentialNames values must be valid systemd credential names";
      }
    ];

    networking.firewall.allowedTCPPorts = optional cfg.openFirewall cfg.port;

    systemd.services.logchef = {
      description = "Logchef log analytics server";
      documentation = [ "https://logchef.app/docs/" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        ExecStart = startScript;
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStopSec = "30s";

        DynamicUser = true;
        StateDirectory = "logchef";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/logchef";
        UMask = "0077";

        EnvironmentFile = optional (cfg.environmentFile != null) cfg.environmentFile;
        LoadCredential =
          (map (pair: "${pair.name}:${pair.path}") loadedCredentialPairs)
          ++ optional (
            cfg.provisioningCredentialFile != null
          ) "provisioning.toml:${cfg.provisioningCredentialFile}";

        CapabilityBoundingSet = "";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RemoveIPC = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
      };
    };
  };
}
