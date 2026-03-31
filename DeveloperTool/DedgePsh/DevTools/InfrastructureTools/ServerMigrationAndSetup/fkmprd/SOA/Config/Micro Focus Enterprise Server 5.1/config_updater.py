#!/usr/bin/env python3
"""
Micro Focus Enterprise Server Configuration Updater

This script updates IP addresses and hostnames in Micro Focus Enterprise Server
configuration files.
"""

import os
import re
import argparse
import configparser
import shutil
from pathlib import Path


def find_config_files(directory):
    """Find all configuration files in the given directory and subdirectories."""
    config_files = []
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.dat'):
                config_files.append(os.path.join(root, file))
    return config_files


def update_config_file(file_path, old_ip, new_ip, old_hostname, new_hostname):
    """Update IP addresses and hostnames in a configuration file."""
    # Create a backup of the original file
    backup_path = f"{file_path}.bak"
    shutil.copy2(file_path, backup_path)
    
    # Read the file content
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except UnicodeDecodeError:
        # Try with a different encoding if UTF-8 fails
        with open(file_path, 'r', encoding='latin-1') as f:
            content = f.read()
    
    # Check if the file is empty
    if not content.strip():
        print(f"Skipping empty file: {file_path}")
        return False, []
    
    original_content = content
    changes = []
    
    # Replace IP addresses
    if old_ip and new_ip:
        # Replace IP address not part of larger numbers/identifiers
        pattern = r'(?<!\d)' + re.escape(old_ip) + r'(?!\d)'
        if re.search(pattern, content):
            content = re.sub(pattern, new_ip, content)
            changes.append(f"Replaced IP: {old_ip} → {new_ip}")
    
    # Replace hostnames
    if old_hostname and new_hostname:
        # Case-insensitive replacement for hostname
        pattern = re.escape(old_hostname)
        if re.search(pattern, content, re.IGNORECASE):
            content = re.sub(pattern, new_hostname, content, flags=re.IGNORECASE)
            changes.append(f"Replaced hostname: {old_hostname} → {new_hostname}")
    
    # Write the updated content back to the file if changes were made
    if content != original_content:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        return True, changes
    else:
        # If no changes were made, remove the backup
        os.remove(backup_path)
        return False, []


def main():
    parser = argparse.ArgumentParser(description='Update IP addresses and hostnames in Micro Focus Enterprise Server configuration files.')
    parser.add_argument('directory', help='Directory containing the configuration files')
    parser.add_argument('--old-ip', help='Old IP address to replace')
    parser.add_argument('--new-ip', help='New IP address')
    parser.add_argument('--old-hostname', help='Old hostname to replace')
    parser.add_argument('--new-hostname', help='New hostname')
    args = parser.parse_args()
    
    if not (args.old_ip or args.old_hostname):
        parser.error("At least one of --old-ip or --old-hostname must be specified")
    
    if args.old_ip and not args.new_ip:
        parser.error("--new-ip must be specified when using --old-ip")
    
    if args.old_hostname and not args.new_hostname:
        parser.error("--new-hostname must be specified when using --old-hostname")
    
    config_files = find_config_files(args.directory)
    
    if not config_files:
        print(f"No configuration files found in {args.directory}")
        return
    
    print(f"Found {len(config_files)} configuration files")
    
    changed_files = 0
    for file_path in config_files:
        print(f"\nProcessing: {file_path}")
        changed, changes = update_config_file(
            file_path, 
            args.old_ip, 
            args.new_ip, 
            args.old_hostname, 
            args.new_hostname
        )
        
        if changed:
            changed_files += 1
            print("  Changes made:")
            for change in changes:
                print(f"  - {change}")
        else:
            print("  No changes needed")
    
    print(f"\nSummary: Updated {changed_files} out of {len(config_files)} files")
    if changed_files > 0:
        print("Backup files were created with .bak extension")


if __name__ == "__main__":
    main() 