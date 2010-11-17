# Copyright (C) 1999-2007  IMSEC GmbH
# Copyright (C) 2004-2007  Logintas AG
#
# This file is part of ISiBackup.
#
#    ISiBackup is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    ISiBackup is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with ISiBackup; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#

package=isibackup
manpages=isibackup-main.1 isibus.1 isirestore.1 deleteoldbackups.1 cleanbackups.1
manpages_html=$(addsuffix .html,${manpages})
documents=html

.PHONY: all
all: ${documents} ${manpages} #${manpages_html}

.PHONY: install
install:

.PHONY: clean
clean:
	rm -rf ${documents} ${manpages} ${manpages_html}

%.1: %.1.xml
	docbook2x-man $<

%.1.html: %.1.xml
	docbook2html $< && mv index.html $@

.PHONY: htmlmans
htmlmans: ${manpages_html}

html:	${package}.sgml
	mkdir -p html
	docbook2html -o html $<
