#!/bin/bash

# 1) Create container "reverseproxy" in unpriviliged mode
# 2) Enable container -nesting- & -NFS-

echo Update System
apt-get update -y
apt-get upgrade -y

echo Set TimZone to Europe/Amsterdam
timedatectl set-timezone Europe/Amsterdam

echo NFS Share
