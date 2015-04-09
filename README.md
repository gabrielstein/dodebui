# Dodebui

Debian Docker builder

This tool helps to build Debian binary packages for multiple distribution
releases.

## Features

### Implemented

* build multiple a package for multiple releases in parallel
* use docker containers for isolation
* install dependencies automatically
* use a apt cache for minimizing download times

### Planned

* Cache images after dependency installation for faster build times

## Installation

Add this Gemfile to your debian packge:

```ruby
source 'https://rubygems.org'
gem 'dodebui'
```

And then execute:

    $ bundle install

Now create your Dodebuifile in project root:

```ruby
# vim: ft=ruby

# Configure distributions to build
@build_distributions = [
  'debian:wheezy',
  'debian:jessie',
  'debian:squeeze',
  'ubuntu:precise',
  'ubuntu:trusty',
]

# Configure a apt-proxy (warmly recommended)
#@apt_proxy = 'http://my-apt-proxy.com/'
```

## Usage

    $ bundle exec dodebui

## Example project

https://github.com/simonswine/dodebui-package-hello

## Contributing

1. Fork it ( https://github.com/[my-github-username]/dodebui/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
