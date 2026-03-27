# ZeroClaw

A NixOS module for managing the ZeroClaw service.

## Overview

ZeroClaw is a service that can be deployed and managed on NixOS systems using this flake. The module provides a declarative way to configure, deploy, and maintain the ZeroClaw service.

## Features

- Declarative NixOS module configuration
- Systemd service integration
- Configurable data directory, user/group settings
- Environment file support
- Customizable log levels and environment variables

## Prerequisites

- NixOS 22.11 or later (or any NixOS version compatible with nixpkgs-unstable)
- Nix package manager with flakes enabled

## Installation

Add this flake to your NixOS configuration:

```nix
{
  inputs = {
    zeroclaw.url = "github:impure0xntk/nix-zeroclaw";
  };
}
```

Then import and enable the module:

```nix
{
  imports = [
    inputs.zeroclaw.nixosModules.default
  ];

  services.zeroclaw = {
    enable = true;
    # Additional configuration options below
  };
}
```

## Configuration Options

The `services.zeroclaw` module provides the following options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | `bool` | `false` | Enable the ZeroClaw service |
| `package` | `package` | `pkgs.zeroclaw` | ZeroClaw package to use |
| `user` | `str` | `"zeroclaw"` | User account to run the service under |
| `group` | `str` | `"zeroclaw"` | Group for the service user |
| `dataDir` | `str` | `"/var/lib/zeroclaw"` | Directory for service data and configuration |
| `settings` | `attrs` | `{ }` | ZeroClaw configuration as a Nix attribute set. These settings are automatically converted to TOML format and written to `config.toml`. See the [Configuration Reference](https://github.com/zeroclaw-labs/zeroclaw/wiki/04.1-Configuration-File-Reference) for all available options. Supports nested attribute sets that map to TOML structure. |
| `secretFiles` | `attrs` | `{ }` | Attribute set mapping file paths to TOML configuration paths. File contents are securely injected into `config.toml` at the specified location during service start. Supports dot notation for nested paths. Example: `{ "/run/keys/api-key" = "api_key"; "/run/keys/telegram-token" = "channels_config.telegram.bot_token"; }` |
| `resources.memoryMax` | `str` | `"512M"` | Memory limit for the service |
| `resources.cpuQuota` | `str` | `"200%"` | CPU quota for the service |
| `environmentFiles` | `list of str` | `[]` | Paths to environment files (NAME=value format) loaded by systemd before starting |
| `extraEnvironment` | `attrs` | `{ }` | Additional environment variables for the service |
| `afterServices` | `list of str` | `[]` | Systemd services that should start before ZeroClaw (added to 'after' and 'requires') |

### Environment Variables

Through the module's configuration, you can set environment variables that will be passed to the service:

```nix
services.zeroclaw = {
  enable = true;
  environment = {
    ZEROCLAW_LOG_LEVEL = "info";  # debug, info, warn, error
    ZEROCLAW_EXTRA_VAR = "value";
  };
};
```

## Configuration Generation

The module automatically generates a configuration file (`config.toml`) in the data directory with basic settings including the provider configuration, gateway settings, and memory configuration.

## Usage Examples

### Complete Example

```nix
services.zeroclaw = {
  enable = true;

  # Test custom user and group
  user = "testzeroclaw";
  group = "testzeroclaw";

  # Test custom data directory
  dataDir = "/var/lib/zeroclaw-custom";

  # Test environment files
  environmentFiles = [ "/etc/zeroclaw/env" ];

  # Wait for pre-start service to ensure secrets are generated. e.g.: sops-nix
  afterServices = [ "zeroclaw-pre-start.service" ];

  # Secret files injection
  secretFiles = {
    "/run/keys/telegram-bot-token" = "channels_config.telegram.bot_token";
    "/run/keys/matrix-access-token" = "channels_config.matrix.access_token";
    "/run/keys/matrix-room-id" = "channels_config.matrix.room_id";
  };

  # Resource limits
  resources = {
    memoryMax = "1G";
    cpuQuota = "150%";
  };

  # Extra environment variables
  extraEnvironment = {
    ZEROCLAW_LOG_LEVEL = "debug";
    CUSTOM_VAR = "testvalue";
  };

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
```

## Testing

The flake includes tests located in `tests/default.nix`. To run the tests:

```bash
nix flake check
```

## Building

Build the package:

```bash
nix build
```

The resulting package will be available at `./result`.

## Package Outputs

This flake provides the following outputs:

- `nixosModules.zeroclaw`: The NixOS module
- `nixosModules.default`: Default module (alias to zeroclaw)
- `checks.test-module`: Module integration tests

## Development

### Working with the Module

The module is defined in `nix/module.nix`. After making changes, rebuild and test:

```bash
nix build
nixos-rebuild test -I nixos-module=./result
```

### Running Tests

```bash
nix flake check
```

## License

This project is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Support

For issues, bug reports, or feature requests, please use the GitHub issue tracker.
