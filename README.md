# logic\_web - Automation Controller UI

This is the web browser-based UI for Nitrogen Logic's [Automation
Controller][0].  It provides a user interface for changing some system
settings, uploading firmware, controlling automation parameters, and
discovering other Nitrogen Logic devices on the same network.

The logic\_web service uses Sinatra for HTTP routing and Thin for its HTTP
server.  The UI is unauthenticated and should only be run on an isolated
network, or with other means of authentication in front of it.

# Copying

&copy;2011-2021 Mike Bourgeous.  Released under [AGPLv3][1].

Some CSS and Javascript dependencies under `static/` will have their own
licenses.  See each file for details.

Not recommended for use in new projects.

# Running

## Dependencies

There are some system-level dependencies to install, such as DNSSD/Avahi for
device discovery:

```bash
sudo apt install libavahi-compat-libdnssd-dev
```

This project uses Ruby, with gems installed by Bundler.  You'll also want to
install and run the logic\_system backend, which is written in C.

```bash
rvm install 2.7.2
echo '2.7.2' > .ruby-version
echo 'logic_web' > .ruby-gemset
rvm use .
bundle install
```

## Direct use

To run logic\_web directly:

```bash
./logic_web.rb
```

Then visit http://localhost:4567/ in your browser.

## Building a .deb package

You can build a .deb package, but it might not work at all:

```bash
meta/make_pkg.sh
```

## Cross-compiling a .deb package for ARM

Nitrogen Logic controllers originally used Debian Squeeze and a somewhat
automated build process, but significant changes to the Linux and web ecosystem
over the last 10 years (such as SystemD and TLS1.2+) have broken most of that
build process.  So this also probably won't work:

```bash
# From within nlutils
PACKAGE=0 TESTS=0 meta/make_root.sh

# From within logic_web
meta/cross_pkg.sh
```

[0]: http://www.nitrogenlogic.com/products/automation_controller.html
[1]: https://www.gnu.org/licenses/agpl-3.0.html
