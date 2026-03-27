{
  pkgs,
  modules,
  ...
}:
pkgs.testers.nixosTest {
  name = "zeroclaw-module-test";
  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [
        modules.zeroclaw
        (
          { config, ... }:
          {
            services.zeroclaw = {
              enable = true;

              # Test custom user and group
              user = "testzeroclaw";
              group = "testzeroclaw";

              # Test custom data directory
              dataDir = "/var/lib/zeroclaw-custom";

              # Test environment files
              environmentFiles = [ "/etc/zeroclaw/env" ];

              # Wait for pre-start service to ensure secrets are generated
              afterServices = [ "zeroclaw-pre-start.service" ];

              # Test secret files injection
              secretFiles = {
                "/run/keys/telegram-bot-token" = "channels_config.telegram.bot_token";
                "/run/keys/matrix-access-token" = "channels_config.matrix.access_token";
                "/run/keys/matrix-room-id" = "channels_config.matrix.room_id";
              };
              # Test additional packages (curl and git)
              additionalPackages = with pkgs; [ curl gitMinimal ];


              # Test resource limits
              resources = {
                memoryMax = "1G";
                cpuQuota = "150%";
              };

              # Test extra environment variables
              extraEnvironment = {
                ZEROCLAW_LOG_LEVEL = "debug";
                CUSTOM_VAR = "testvalue";
              };

              autoStartChannel = false; # For test: cannot start channel with invalid token.

              # Comprehensive settings
              settings = {
                default_provider = "anthropic";
                default_model = "claude-sonnet-4-5";

                # API keys will be injected via secretFiles
                api_key = "";  # placeholder

                gateway = {
                  port = 3000;
                  host = "127.0.0.1";
                  require_pairing = false;
                  allow_public_bind = true;  # for test
                };

                memory = {
                  backend = "sqlite";
                  auto_save = true;
                  vector_weight = 0.7;
                  keyword_weight = 0.3;
                };

                channels_config = {
                  telegram = {
                    allowed_users = [];
                  };
                  matrix = {
                    homeserver = "https://matrix.example.com";
                    allowed_users = [];
                  };
                };
              };
            };

            # Create test environment file
            environment.etc."zeroclaw/env".text = ''
              ZEROCLAW_EXTRA_VAR=extravalue
            '';

            # Create fake key files for secret injection test
            systemd.services.zeroclaw-pre-start = {
              wantedBy = [ "multi-user.target" ];
              before = [ "zeroclaw.service" ];  # Ensure keys are created before ZeroClaw starts
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "/bin/sh -c 'mkdir -p /run/keys && echo \"123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11\" > /run/keys/telegram-bot-token && echo \"dmljYXN0ZXJfYWNjZXNzX3Rva2VuX3ZlcnlfbG9uZ19ieXRlcw==\" > /run/keys/matrix-access-token && echo \"!abc123def456:example.com\" > /run/keys/matrix-room-id'";
              };
            };
          }
        )
      ];
    };

  testScript = ''
    machine.start()

    # Wait for system to be ready
    machine.wait_for_unit("multi-user.target")

    # Wait for pre-start keys creation
    machine.wait_for_unit("zeroclaw-pre-start.service")

    # ==============================
    # Basic service checks
    # ==============================
    machine.succeed("systemctl cat zeroclaw.service")

    # Check config file exists
    machine.succeed("test -f /var/lib/zeroclaw-custom/config.toml")

    # Debug: print config file contents
    machine.execute("cat /var/lib/zeroclaw-custom/config.toml")

    # ==============================
    # Validate TOML structure
    # ==============================
    # Core sections
    machine.succeed("grep -q 'default_provider' /var/lib/zeroclaw-custom/config.toml")
    machine.succeed("grep -q 'gateway' /var/lib/zeroclaw-custom/config.toml")
    machine.succeed("grep -q 'memory' /var/lib/zeroclaw-custom/config.toml")
    machine.succeed("grep -q 'channels_config.matrix' /var/lib/zeroclaw-custom/config.toml")
    machine.succeed("grep -q 'channels_config' /var/lib/zeroclaw-custom/config.toml")

    # Nested sections
    machine.succeed("grep -q '\\[gateway\\]' /var/lib/zeroclaw-custom/config.toml")
    machine.succeed("grep -q '\\[memory\\]' /var/lib/zeroclaw-custom/config.toml")
    machine.succeed("grep -q '\\[channels_config.matrix\\]' /var/lib/zeroclaw-custom/config.toml")
    machine.succeed("grep -q '\\[channels_config.telegram\\]' /var/lib/zeroclaw-custom/config.toml")

    # Secret injection checks
    machine.succeed("grep -q 'bot_token = \"123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11\"' /var/lib/zeroclaw-custom/config.toml")
    machine.succeed("grep -q 'access_token = \"dmljYXN0ZXJfYWNjZXNzX3Rva2VuX3ZlcnlfbG9uZ19ieXRlcw==\"' /var/lib/zeroclaw-custom/config.toml")
    machine.succeed("grep -q 'room_id = \"!abc123def456:example.com\"' /var/lib/zeroclaw-custom/config.toml")

    # ==============================
    # Test Service Configuration
    # ==============================
    # Check service runs as custom user
    machine.succeed("systemctl show zeroclaw.service -p User | grep -q 'User=testzeroclaw'")
    machine.succeed("systemctl show zeroclaw.service -p Group | grep -q 'Group=testzeroclaw'")

    # Check working directory
    machine.succeed("systemctl show zeroclaw.service -p WorkingDirectory | grep -q 'WorkingDirectory=/var/lib/zeroclaw-custom'")

    # Check resource limits
    machine.succeed("systemctl show zeroclaw.service -p MemoryMax | grep -q 'MemoryMax=1073741824'") # 1G
    machine.succeed("systemctl show zeroclaw.service -p CPUQuotaPerSecUSec | grep -q 'CPUQuotaPerSecUSec=1.500000s'") # CPUQuota=150%

    # Check environment variables
    machine.succeed("systemctl show zeroclaw.service -p Environment | grep -q 'ZEROCLAW_LOG_LEVEL=debug'")
    machine.succeed("systemctl show zeroclaw.service -p Environment | grep -q 'CUSTOM_VAR=testvalue'")

    # Check ZEROCLAW_CONFIG points to correct path
    machine.succeed("systemctl show zeroclaw.service -p Environment | grep -q 'ZEROCLAW_CONFIG=/var/lib/zeroclaw-custom/config.toml'")

    # Check environment file exists
    machine.succeed("test -f /etc/zeroclaw/env")

    # Check environment file content
    machine.succeed("grep -q 'ZEROCLAW_EXTRA_VAR=extravalue' /etc/zeroclaw/env")

    # Verify that environment variables from file are available to service
    machine.succeed("systemctl cat zeroclaw.service | grep -q 'EnvironmentFile=/etc/zeroclaw/env'")

    machine.succeed("systemctl cat zeroclaw.service | grep -q 'Environment=\"PATH=.*curl'")

    # ==============================
    # Test User and Group
    # ==============================
    machine.succeed("getent passwd testzeroclaw > /dev/null")
    machine.succeed("getent group testzeroclaw > /dev/null")
    machine.succeed("test -d /var/lib/zeroclaw-custom")
    machine.succeed("stat -c %U /var/lib/zeroclaw-custom | grep -q testzeroclaw")

    # ==============================
    # Test Config Permissions
    # ==============================
    machine.succeed("test -f /var/lib/zeroclaw-custom/config.toml")
    machine.succeed("test -r /var/lib/zeroclaw-custom/config.toml")
    machine.succeed("ls -l /var/lib/zeroclaw-custom/config.toml | grep -q '^-r--------'")

    # ==============================
    # Test Service is Active
    # ==============================
    machine.succeed("systemctl is-active -q zeroclaw.service")
  '';
}
