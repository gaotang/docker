#!/bin/bash
set -e

# This file is used to auto-generate Dockerfiles for making debs via 'make deb'
#
# usage: ./generate.sh [versions]
#    ie: ./generate.sh
#        to update all Dockerfiles in this directory
#    or: ./generate.sh ubuntu-xenial
#        to only update ubuntu-xenial/Dockerfile
#    or: ./generate.sh ubuntu-newversion
#        to create a new folder and a Dockerfile within it

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

for version in "${versions[@]}"; do
	echo "${versions[@]}"
	distro="${version%-*}"
	suite="${version##*-}"
	from="ppc64le/${distro}:${suite}"

	mkdir -p "$version"
	echo "$version -> FROM $from"
	cat > "$version/Dockerfile" <<-EOF
		#
		# THIS FILE IS AUTOGENERATED; SEE "contrib/builder/deb/ppc64le/generate.sh"!
		#

		FROM $from

	EOF

	extraBuildTags='pkcs11'
	runcBuildTags=

	# this list is sorted alphabetically; please keep it that way
	packages=(
		apparmor # for apparmor_parser for testing the profile
		bash-completion # for bash-completion debhelper integration
		btrfs-tools # for "btrfs/ioctl.h" (and "version.h" if possible)
		build-essential # "essential for building Debian packages"
		curl ca-certificates # for downloading Go
		debhelper # for easy ".deb" building
		dh-apparmor # for apparmor debhelper
		dh-systemd # for systemd debhelper integration
		git # for "git commit" info in "docker -v"
		golang-go # ppc64le needs go to bootstrap go
		libapparmor-dev # for "sys/apparmor.h"
		libdevmapper-dev # for "libdevmapper.h"
		libltdl-dev # for pkcs11 "ltdl.h"
		libseccomp-dev  # for "seccomp.h" & "libseccomp.so"
		libsqlite3-dev # for "sqlite3.h"
		libsystemd-dev
		pkg-config # for detecting things like libsystemd-journal dynamically
	)
	
	case "$suite" in
		# ppc64le support was backported into libseccomp 2.2.3-2,
		# so enable seccomp by default
		*)
			extraBuildTags+=' seccomp'
			runcBuildTags="apparmor seccomp selinux"
			;;
	esac
	
	# update and install packages
	echo "RUN apt-get update && apt-get install -y ${packages[*]} --no-install-recommends && rm -rf /var/lib/apt/lists/*" >> "$version/Dockerfile"
	echo >> "$version/Dockerfile"

	# ppc64le doesn't have an official downloadable binary as of go 1.6.2. so use the
	# older packaged go(v1.6.1) to bootstrap latest go, then remove the packaged go
	awk '$1 == "ENV" && $2 == "GO_VERSION" { print; exit }' ../../../../Dockerfile.ppc64le >> "$version/Dockerfile"
	echo 'ENV GO_DOWNLOAD_URL https://golang.org/dl/go${GO_VERSION}.src.tar.gz' >> "$version/Dockerfile"
	echo 'ENV GOROOT_BOOTSTRAP /usr/lib/go-1.6' >> "$version/Dockerfile"
	echo >> "$version/Dockerfile"
	
	echo 'RUN curl -fsSL "$GO_DOWNLOAD_URL" -o golang.tar.gz \' >> "$version/Dockerfile"
	echo '	&& tar -C /usr/local -xzf golang.tar.gz \' >> "$version/Dockerfile"
	echo '	&& rm golang.tar.gz \' >> "$version/Dockerfile"
	echo '	&& cd /usr/local/go/src && ./make.bash 2>&1 \' >> "$version/Dockerfile"
	echo '	&& apt-get purge -y golang-go && apt-get autoremove -y' >> "$version/Dockerfile"
	echo >> "$version/Dockerfile"

	echo 'ENV PATH $PATH:/usr/local/go/bin' >> "$version/Dockerfile"
	echo >> "$version/Dockerfile"

	echo 'ENV AUTO_GOPATH 1' >> "$version/Dockerfile"
	echo >> "$version/Dockerfile"

	# print build tags in alphabetical order
	buildTags=$( echo "apparmor selinux $extraBuildTags" | xargs -n1 | sort -n | tr '\n' ' ' | sed -e 's/[[:space:]]*$//' )
	echo "ENV DOCKER_BUILDTAGS $buildTags" >> "$version/Dockerfile"
	echo "ENV RUNC_BUILDTAGS $runcBuildTags" >> "$version/Dockerfile"
done
