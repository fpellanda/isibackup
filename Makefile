# Copyright (C) 2007 Logintas AG
#
# This file is part of ISiBackup.
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License along
#    with this program; if not, write to the Free Software Foundation, Inc.,
#    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

SCRIPTS=cleanbackups deleteoldbackups isibackup isibus isirestore isibackup-main isirestore-main isibackup-info
CONF_DIRS=config data system keys media

include Makefile.rules

all:
	$(MAKE) -C docs

install:
	$(MKDIR) $(DESTDIR)$(PREFIX)/bin
	$(INSTALL_bin) $(SCRIPTS) $(DESTDIR)$(PREFIX)/bin
	$(MKDIR) $(DESTDIR)$(PREFIX)/lib
	$(MKDIR) $(DESTDIR)$(PREFIX)/lib/ruby/1.8
	$(INSTALL_data) lib/path_list.rb $(DESTDIR)$(PREFIX)/lib/ruby/1.8
	$(INSTALL_data) lib/backup.rb $(DESTDIR)$(PREFIX)/lib/ruby/1.8
	$(MKDIR) $(DESTDIR)/etc/isibackup
	$(INSTALL_data) ./conf/defaults.conf $(DESTDIR)/etc/isibackup
	$(INSTALL_data) ./conf/isibackup.conf $(DESTDIR)/etc/isibackup
	$(INSTALL_data) ./conf/control $(DESTDIR)/etc/isibackup
	$(INSTALL_data) ./conf/mount_points $(DESTDIR)/etc/isibackup
	for DIR in $(CONF_DIRS); do \
		$(MKDIR) $(DESTDIR)/etc/isibackup/$$DIR; \
		$(INSTALL_data) ./conf/$$DIR/set.conf $(DESTDIR)/etc/isibackup/$$DIR; \
		$(INSTALL_data) ./conf/$$DIR/backup_pre_commands.sh $(DESTDIR)/etc/isibackup/$$DIR; \
		$(INSTALL_data) ./conf/$$DIR/*.lst $(DESTDIR)/etc/isibackup/$$DIR; \
		done
	$(MAKE) -C docs install

clean:
	$(MAKE) -C docs clean

.PHONY: all install clean
