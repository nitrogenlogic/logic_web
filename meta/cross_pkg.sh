#!/bin/sh

# Debian architecture name
ARCH=${ARCH:-armel}

# Debian release name
RELEASE=${RELEASE:-buster}

# Project directory
BASEDIR="$(readlink -m "$(dirname "$0")/..")"

# More Debian packages to install
EXTRA_PACKAGES="\
ruby-dev,\
libavahi-compat-libdnssd-dev\
"

# Command to run when build_root_helper wants to compile and install
LOCAL_BUILD=make

if [ -r /usr/local/share/nlutils/build_root_helper.sh ]; then
	. /usr/local/share/nlutils/build_root_helper.sh
elif [ -r /usr/share/nlutils/build_root_helper.sh ]; then
	. /usr/share/nlutils/build_root_helper.sh
else
	printf "\033[1;31mCan't find nlutils build root helper script\033[0m\n"
	exit 1
fi
