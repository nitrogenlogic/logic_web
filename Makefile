# This Makefile is for meta/cross_build.sh and meta/make_pkg.sh to build
# releasable packages e.g. in an ARM QEMU chroot.  It's for a standardish
# packaging and deployment system from nlutils.

.PHONY: all install

all:
	gem install bundler --no-document
	bundle install --verbose --deployment

install:
	mkdir -vp /etc/systemd/system/
	mkdir -vp /opt/nitrogenlogic/webstatus/
	touch /opt/nitrogenlogic/webstatus/.keep
	cp -R Gemfile Gemfile.lock embedded/appinfo.txt logic_web.rb logic_web.ru lib/ routes/ static/ vendor/ .bundle/ embedded/webstatus_monitor.sh /opt/nitrogenlogic/webstatus/
	cp -vR embedded/systemd/* /etc/systemd/system/
