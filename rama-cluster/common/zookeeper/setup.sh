#!/bin/bash

# Update package metadata (supports both yum/dnf and apt)
# No package manager update needed for tar.gz installation

echo "Downloading zookeeper..." >> setup.log

# Download and unpack Zookeeper
wget $1 -O zookeeper.tar.gz -o setup.log

# Extract zookeeper tar into a temporary directory
mkdir -p tmp && tar zxvf zookeeper.tar.gz -C tmp &>> setup.log

# Then move everything out of the top-level directory in tmp, into a zookeeper
# directory. Since we don't know the name of the file this is going to be, we
# can't just do a more straight fowards rename without isolating the file into
# it's own directory first.
# Ensure destination directory exists
mkdir -p zookeeper
# Move extracted contents (assuming a single top-level directory) into zookeeper root
first_dir=$(ls -1 tmp | head -n1)
mv tmp/"$first_dir"/* zookeeper/
rm -rf tmp # then we clean up the now empty temporary directory

echo "Successfully downloaded Zookeeper" >> setup.log

mkdir -p zookeeper/data
mkdir -p zookeeper/logs
