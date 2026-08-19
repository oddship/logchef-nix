{
  lib,
  pkgs,
  module,
  package,
}:

let
  evaluated = lib.nixosSystem {
    inherit (pkgs.stdenv.hostPlatform) system;
    modules = [
      module
      {
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "none";
          fsType = "tmpfs";
        };
        system.stateVersion = "26.05";
        services.logchef = {
          enable = true;
          inherit package;
          adminEmails = [ "admin@example.test" ];
          localAuth.enable = true;
          credentialNames.LOGCHEF_AUTH__API_TOKEN_SECRET = "api-token-secret";
        };
      }
    ];
  };

  service = evaluated.config.systemd.services.logchef.serviceConfig;
  failedAssertions = builtins.filter (item: !item.assertion) evaluated.config.assertions;
in
assert lib.assertMsg (failedAssertions == [ ]) "Logchef module assertions failed";
assert pkgs.lib.assertMsg (service.DynamicUser == true) "Logchef must use DynamicUser";
assert pkgs.lib.assertMsg (
  service.StateDirectory == "logchef"
) "Logchef must have persistent state";
assert pkgs.lib.assertMsg (
  service.ProtectSystem == "strict"
) "Logchef must use ProtectSystem=strict";
pkgs.runCommand "logchef-module-evaluation" { } ''
  touch "$out"
''
