# ZeroClaw NixOS Module
# Simplified: configuration is provided as Nix attrset via settings option
{ config, lib, pkgs, ... }:

let
  cfg = config.services.zeroclaw;
  settingsFormat = pkgs.formats.toml { };

  # Helper to convert a dotted path to a nested attribute set.
  pathToNestedAttrs = path: value:
    let
      parts = lib.splitString "." path;
      build = p:
        if p == [] then {} else
        let
          h = builtins.head p;
          t = builtins.tail p;
        in
          { ${h} = if t == [] then value else build t; };
    in
      build parts;

  effectiveSettings = let
    secretOverrides = lib.foldl' (acc: mapping:
      let
        placeholder = "__ZEROCLAW_SECRET_${baseNameOf mapping.file}__";
        nested = pathToNestedAttrs mapping.path placeholder;
      in
        lib.recursiveUpdate acc nested
    ) {} (lib.mapAttrsToList (file: path: { inherit file path; }) cfg.secretFiles);
  in
    lib.recursiveUpdate cfg.settings secretOverrides;
in
{
  options.services.zeroclaw = {
    enable = lib.mkEnableOption "ZeroClaw AI assistant";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.zeroclaw;
      description = "ZeroClaw package to use";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "zeroclaw";
      description = "User account under which ZeroClaw runs";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "zeroclaw";
      description = "Group under which ZeroClaw runs";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/zeroclaw";
      description = "Directory for ZeroClaw workspace and configuration";
    };

    additionalPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [ curl gitMinimal];
      description = "Additional packages to install alongside ZeroClaw";
    };

    # Main configuration as Nix attrset (converted to TOML in preStart)
    settings = lib.mkOption {
      type = settingsFormat.type;
      default = { };
      description = "ZeroClaw configuration as Nix attrset. See https://github.com/zeroclaw-labs/zeroclaw/wiki/04.1-Configuration-File-Reference for all options";
    };

    # Environment files for systemd (NAME=value format)
    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "List of files containing environment variable assignments (NAME=value). Loaded by systemd before starting the service. See systemd.exec(5).";
    };

    # Secret injection: map file path to TOML configuration path
    secretFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "/run/keys/zeroclaw-api-key" = "api_key";
        "/run/keys/telegram-token" = "channels_config.telegram.bot_token";
        "/run/keys/discord-token" = "channels_config.discord.bot_token";
        "/run/keys/slack-bot-token" = "channels_config.slack.bot_token";
        "/run/keys/brave-api-key" = "web_search.brave_api_key";
      };
      description = "Attribute set mapping file paths to TOML configuration paths. The file content will be read and injected into config.toml at the specified path. Supports nested paths using dot notation (e.g., 'channels_config.telegram.bot_token').";
    };

    # Resource limits
    resources = {
      memoryMax = lib.mkOption {
        type = lib.types.str;
        default = "512M";
        description = "Memory limit";
      };

      cpuQuota = lib.mkOption {
        type = lib.types.str;
        default = "200%";
        description = "CPU quota";
      };
    };

    # Environment variable overrides
    extraEnvironment = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional environment variables for the service";
    };

    # Services this service depends on and must start first
    afterServices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of systemd services that zeroclaw depends on and must start first. Added to service 'after' and 'requires' directives. Use for dependencies like sops-nix that must complete before zeroclaw starts.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create user and group
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      createHome = true;
      description = "ZeroClaw service user";
    };

    users.groups.${cfg.group} = { };

    # Systemd service
    systemd.services.zeroclaw = {
      description = "ZeroClaw AI Assistant";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ] ++ cfg.afterServices;
      wants = [ "network-online.target" ] ++ cfg.afterServices;
      requires = cfg.afterServices;
      path = cfg.additionalPackages;

      environment = {
        ZEROCLAW_CONFIG = "${cfg.dataDir}/config.toml";
        ZEROCLAW_WORKSPACE = cfg.dataDir;
      } // cfg.extraEnvironment;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        ExecStart = "${cfg.package}/bin/zeroclaw gateway";
        Restart = "on-failure";
        RestartSec = "5s";

        # Environment files
        EnvironmentFile = cfg.environmentFiles;

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;

        # Filesystem access
        ReadWritePaths = [ cfg.dataDir ];

        # Resource limits
        MemoryMax = cfg.resources.memoryMax;
        CPUQuota = cfg.resources.cpuQuota;

        # Load secrets via systemd Credentials (available at /run/credentials/zeroclaw/)
        LoadCredential = lib.mapAttrsToList (filePath: tomlPath:
          "zeroclaw-${baseNameOf filePath}:${filePath}"
        ) cfg.secretFiles;
      };

      preStart = let
        configFile = "${cfg.dataDir}/config.toml";
        secretsSubst = lib.concatMapStrings (x:
          let
            fileName = baseNameOf x.file;
            placeholder = "__ZEROCLAW_SECRET_${fileName}__";
          in
            ''
              CRED="/run/credentials/zeroclaw.service/zeroclaw-${fileName}"
              if [ -f "''${CRED}" ]; then
                VALUE=$(cat "''${CRED}")
                sed -i "s|${placeholder}|''${VALUE}|g" "${configFile}"
              fi
            ''
        ) (lib.mapAttrsToList (file: path: { inherit file path; }) cfg.secretFiles);
      in
        ''
          rm  -f ${cfg.dataDir}/config.toml

          mkdir -p ${cfg.dataDir}/workspace

          # Generate config with placeholders for all secrets
          cp ${settingsFormat.generate "config.toml" effectiveSettings} ${cfg.dataDir}/config.toml

          # Inject actual secrets by replacing placeholders
          ${secretsSubst}

          chmod 400 ${cfg.dataDir}/config.toml
        '';
    };


  };
}
