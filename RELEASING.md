# Releasing

1. `git pull origin master`
1. Bump the version number in `lib/percy/common/version.rb`
1. `git add lib/percy/common/version.rb`
1. `git commit -m "version bump to X.X.X"`
1. `git push origin master`
1. `git tag vX.X.X`
1. `git push --tags`
1. `bundle exec rake build`
1. `gem push pkg/percy-common-X.X.X.gem`
1. Visit [RubyGems.org](https://rubygems.org/gems/percy-common) and see the gem has been published
1. Document the release on Github by first [creating a new release](https://github.com/percy/percy-common/releases/new)
1. Enter "vX.X.X" as the tag version. It should auto complete to say "Existing Tag"
1. Enter "vX.X.X" as the release title
1. Write a brief description as to what is included in this release. Linking to specific PRs is great.
1. Click "Publish release"
