#!/bin/bash
#
# Repackaging Git for Windows and bundling Git LFS from upstream.
#

# i want to centralize this function but everything is terrible
# go read https://github.com/desktop/dugite-native/issues/38
computeChecksum() {
   if [ -z "$1" ] ; then
     # no parameter provided, fail hard
     exit 1
   fi

  path_to_sha256sum=$(which sha256sum)
  if [ -x "$path_to_sha256sum" ] ; then
    echo $(sha256sum $1 | awk '{print $1;}')
  else
    echo $(shasum -a 256 $1 | awk '{print $1;}')
  fi
}

DESTINATION=$1
mkdir -p $DESTINATION

echo "-- Downloading MinGit"
GIT_FOR_WINDOWS_FILE=git-for-windows.zip
curl -sL -o $GIT_FOR_WINDOWS_FILE $GIT_FOR_WINDOWS_URL
COMPUTED_SHA256=$(computeChecksum $GIT_FOR_WINDOWS_FILE)
if [ "$COMPUTED_SHA256" = "$GIT_FOR_WINDOWS_CHECKSUM" ]; then
  echo "MinGit: checksums match"
  unzip -qq $GIT_FOR_WINDOWS_FILE -d $DESTINATION
else
  echo "MinGit: expected checksum $GIT_FOR_WINDOWS_CHECKSUM but got $COMPUTED_SHA256"
  echo "aborting..."
  exit 1
fi

# download Git LFS, verify its the right contents, and unpack it
echo "-- Bundling Git LFS"
GIT_LFS_FILE=git-lfs.zip
GIT_LFS_URL="https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}/git-lfs-windows-amd64-${GIT_LFS_VERSION}.zip"
curl -sL -o $GIT_LFS_FILE $GIT_LFS_URL
COMPUTED_SHA256=$(computeChecksum $GIT_LFS_FILE)
if [ "$COMPUTED_SHA256" = "$GIT_LFS_CHECKSUM" ]; then
  echo "Git LFS: checksums match"
  SUBFOLDER="$DESTINATION/mingw64/libexec/git-core/"
  unzip -qq -j $GIT_LFS_FILE -x '*.md' -d $SUBFOLDER
else
  echo "Git LFS: expected checksum $GIT_LFS_CHECKSUM and got $COMPUTED_SHA256"
  echo "aborting..."
  exit 1
fi

SYSTEM_CONFIG="$DESTINATION/mingw64/etc/gitconfig"

echo "-- Setting some system configuration values"
git config --file $SYSTEM_CONFIG core.symlinks "false"
git config --file $SYSTEM_CONFIG core.autocrlf "true"
git config --file $SYSTEM_CONFIG core.fscache "true"
git config --file $SYSTEM_CONFIG http.sslBackend "schannel"

# See https://github.com/desktop/desktop/issues/4817#issuecomment-393241303
# Even though it's not set openssl will auto-discover the one we ship because
# it sits in the right location already. So users manually switching
# http.sslBackend to openssl will still pick it up.
git config --file $SYSTEM_CONFIG --unset http.sslCAInfo

# Git for Windows 2.18.0 now supports controlling how curl uses any certificate
# bundle - rather than just loading the bundle if http.useSSLCAInfo is set
# For the moment we want to favour using the OS certificate store unless the
# user has overriden this in their global configuration.
#
# details: https://github.com/dscho/git/commit/ffd4963bde17c11dfc2580d258a315964fa21378
git config --file $SYSTEM_CONFIG http.schannel.useSSLCAInfo "false"

# removing global gitattributes file
rm "$DESTINATION/mingw64/etc/gitattributes"
echo "-- Removing global gitattributes which handles certain file extensions"
