# Installing GitX Command Line Tool

This document explains how to manually install the GitX command line tool, which allows you to open GitX from the terminal.

## Manual Installation

1. **Build GitX** (if not already done):
   ```bash
   cd /path/to/gitx
   xcodebuild -project GitX.xcodeproj -scheme Debug -configuration Debug
   ```

2. **Locate the built gitx executable**:
   The command line tool is bundled inside the GitX.app at:
   ```
   GitX.app/Contents/Resources/gitx
   ```

3. **Create the symlink manually**:
   ```bash
   # Create /usr/local/bin if it doesn't exist
   sudo mkdir -p /usr/local/bin
   
   # Create symlink to the gitx executable
   sudo ln -sf "/path/to/GitX.app/Contents/Resources/gitx" /usr/local/bin/gitx
   ```

4. **Verify installation**:
   ```bash
   which gitx
   # Should show: /usr/local/bin/gitx
   
   gitx --version
   # Should show GitX version info
   ```

## Usage

Once installed, you can use GitX from the command line:

```bash
# Open current directory in GitX
gitx

# Open specific repository
gitx /path/to/repo

# Open specific repository and show diff view
gitx --diff /path/to/repo
```

## Uninstallation

To remove the command line tool:

```bash
sudo rm /usr/local/bin/gitx
```

## Notes

- The symlink approach ensures the command line tool stays current with app updates
- Make sure `/usr/local/bin` is in your PATH environment variable
- If you move the GitX.app, you'll need to recreate the symlink with the new path