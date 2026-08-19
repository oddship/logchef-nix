{
  pkgs,
  module,
  package,
}:

pkgs.testers.runNixOSTest {
  name = "logchef-smoke";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ module ];

      services.logchef = {
        enable = true;
        inherit package;
        adminEmails = [ "admin@example.test" ];
        localAuth.enable = true;
        credentialFiles.LOGCHEF_AUTH__API_TOKEN_SECRET = "/run/logchef-secrets/api-token-secret";
        settings = {
          server.secure_cookie = false;
          ai.enabled = false;
          alerts.enabled = false;
        };
      };

      systemd.services.logchef = {
        requires = [ "logchef-secrets.service" ];
        after = [ "logchef-secrets.service" ];
      };

      systemd.services.logchef-secrets = {
        description = "Generate an ephemeral Logchef smoke-test secret";
        before = [ "logchef.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          RuntimeDirectory = "logchef-secrets";
          RuntimeDirectoryMode = "0700";
          UMask = "0077";
          ExecStart = pkgs.writeShellScript "generate-logchef-smoke-secret" ''
            set -euo pipefail
            ${pkgs.coreutils}/bin/head -c 48 /dev/urandom \
              | ${pkgs.coreutils}/bin/base64 \
              > /run/logchef-secrets/api-token-secret
          '';
        };
      };

      environment.systemPackages = [ pkgs.curl ];
      system.stateVersion = "26.05";
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("logchef.service")
    machine.wait_for_open_port(8125)
    machine.succeed("curl --fail --silent http://127.0.0.1:8125/ | grep -q '<div id=\"app\">'")
    machine.succeed("test -s /var/lib/private/logchef/logchef.db")
    machine.succeed("systemctl show logchef.service -p DynamicUser --value | grep -qx yes")
    machine.succeed("systemctl show logchef.service -p ProtectSystem --value | grep -qx strict")
    machine.succeed("test $(stat -c %a /var/lib/private/logchef) = 700")
  '';
}
