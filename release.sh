#!/usr/bin/env bash

set -e

cd "$(dirname "$0")" || exit 1
CURDIR="$(pwd)"

PERCY_COMMON_VERSION="$(grep "VERSION" lib/percy/common/version.rb | awk -F "'" '{print $2}')"

echo "Current percy-common version: $PERCY_COMMON_VERSION"

if [[ $# -lt 1 ]]; then
  echo "Usage $0 <version>"
  exit 1
fi

rm "$CURDIR/"percy-common*.gem >/dev/null 2>&1 || true

delete_existing_version() {
  git tag -d "v$1" || true
  git push origin ":v$1" || true
  # Replace - with .pre. in version string for rubygems compatibility
  GEM_VERSION=${1/-/.pre.}
  gem yank percy-common -v "$GEM_VERSION" || true
}

if [[ $1 =~ ^.*delete$ ]]; then
  shift
  echo "Preparing to delete $1"
  sleep 3
  delete_existing_version "$PERCY_COMMON_VERSION"
else
  CLEAN=$(
    git diff-index --quiet HEAD --
    echo $?
  )
  if [[ "$CLEAN" == "0" ]]; then
    if [[ $1 == '--force' ]]; then
      shift
      VERSION=$1
      if [[ -n $VERSION ]]; then
        echo "Deleting version $VERSION"
        sleep 1
        delete_existing_version "$VERSION"
      else
        echo "Missing release version"
        exit 1
      fi
    fi
    VERSION=$1
    # Replace - with .pre. in version string for rubygems compatibility
    GEM_VERSION="${VERSION/-/.pre.}"
    if [[ "$GEM_VERSION" == "$VERSION" ]]; then
      echo "Releasing $VERSION"
    else
      echo "Releasing $VERSION as $GEM_VERSION"
    fi
    sleep 1

    sed -i "" -e "s/$PERCY_COMMON_VERSION/$VERSION/g" "lib/percy/common/version.rb"
    git add "lib/percy/common/version.rb"
    git commit -a -m "Release $VERSION" || true

    git tag -a "v$VERSION" -m "$1" || true
    git push origin "v$VERSION" || true

    bundle exec rake build
    gem push "$CURDIR/pkg/percy-common-$GEM_VERSION.gem"
    open "https://github.com/percy/percy-common/releases/new?tag=v$VERSION&title=$VERSION"
    rm "$CURDIR/pkg/percy-common-$GEM_VERSION.gem"
  else
    echo "Please commit your changes and try again"
    exit 1
  fi
fi
echo "Done"
