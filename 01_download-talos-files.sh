#!/bin/bash
# download-talos-files.sh

# Configurable directory - change this to your preferred location
VMLINUZ_DIR="_out"

# Set architecture (adjust if needed)
ARCH="amd64"  # or "arm64"

# Get Talos version from talosctl or specify manually
TALOS_VERSION=$(talosctl version --client --short 2>/dev/null | grep Talos | cut -d' ' -f2)
if [ -z "$TALOS_VERSION" ]; then
    TALOS_VERSION="v1.7.6"  # Fallback to version from manual
fi

# URLs for downloads
KERNEL_URL="https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/vmlinuz-${ARCH}"
INITRAMFS_URL="https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/initramfs-${ARCH}.xz"

# Local file paths
KERNEL_FILE="${VMLINUZ_DIR}/vmlinuz-${ARCH}"
INITRAMFS_FILE="${VMLINUZ_DIR}/initramfs-${ARCH}.xz"

# Create directory
mkdir -p "$VMLINUZ_DIR"

echo "Downloading Talos files for version: $TALOS_VERSION"
echo "Architecture: $ARCH"
echo "Directory: $VMLINUZ_DIR"
echo ""

# Function to check if file exists and is not empty
file_exists() {
    [ -f "$1" ] && [ -s "$1" ]
}

# Function to download with resume support and only if needed
download_if_not_exists() {
    local url="$1"
    local output_file="$2"
    local file_name=$(basename "$output_file")
    
    if file_exists "$output_file"; then
        echo "✓ $file_name already exists, skipping download"
        return 0
    fi
    
    echo "Downloading $file_name..."
    
    # Use curl with resume support and show progress
    if curl -L -f -C - -o "$output_file" "$url" --progress-bar; then
        echo "✓ Downloaded $file_name"
        return 0
    else
        # If resume fails, try fresh download
        echo "Retrying fresh download of $file_name..."
        if curl -L -f -o "$output_file" "$url" --progress-bar; then
            echo "✓ Downloaded $file_name"
            return 0
        else
            echo "✗ Failed to download $file_name"
            # Clean up potentially corrupted file
            rm -f "$output_file"
            return 1
        fi
    fi
}

# Function to verify checksum (optional)
verify_file() {
    local file="$1"
    local file_name=$(basename "$file")
    
    if file_exists "$file"; then
        local size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
        echo "  $file_name: $(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo "${size}B")"
        return 0
    else
        echo "  $file_name: MISSING"
        return 1
    fi
}

# Download files
echo "Checking existing files..."
download_if_not_exists "$KERNEL_URL" "$KERNEL_FILE"
download_if_not_exists "$INITRAMFS_URL" "$INITRAMFS_FILE"

echo ""
echo "Verification:"

# Verify both files exist
KERNEL_OK=0
INITRAMFS_OK=0

if verify_file "$KERNEL_FILE"; then
    KERNEL_OK=1
fi

if verify_file "$INITRAMFS_FILE"; then
    INITRAMFS_OK=1
fi

echo ""


# Summary
if [ $KERNEL_OK -eq 1 ] && [ $INITRAMFS_OK -eq 1 ]; then
    echo "✅ All files downloaded successfully to $VMLINUZ_DIR"
    exit 0
elif [ $KERNEL_OK -eq 1 ] || [ $INITRAMFS_OK -eq 1 ]; then
    echo "⚠️  Some files may be missing from $VMLINUZ_DIR"
    exit 1
else
    echo "❌ Failed to download files"
    exit 1
fi
