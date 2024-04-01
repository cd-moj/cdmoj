SERVERDIR ?= /home/$(SUDO_USER)/cdmoj/server
HTMLDIR ?= /home/$(SUDO_USER)/cdmoj/html
CONTESTSDIR ?= /home/$(SUDO_USER)/cdmoj/server/contests

export SERVERDIR
export HTMLDIR
export CONTESTSDIR
export CONFDIR=$(SERVERDIR)/etc
export SCRIPTSDIR=$(SERVERDIR)/scripts

PACKAGES = apache2 rsync xclip curl default-jre default-jdk openjdk-17-jre openjdk-17-jdk

.PHONY: confirm
confirm:
	@echo "\n====================================================================================\n"
	@echo "SERVERDIR= $$SERVERDIR"
	@echo "HTMLDIR = $$HTMLDIR"
	@echo "CONTESTSDIR = $$CONTESTSDIR"
	@echo "\n====================================================================================\n"
	@echo "use: sudo make SERVERDIR=/example/path HTMLDIR=/example/path CONTESTSDIR=/example/path"
	@echo "\n====================================================================================\n"
	@echo "The following packages will be installed:\n"
	@echo "${PACKAGES}"
	@echo "\n====================================================================================\n"

	@read -p "Do you want to proceed? (y/n): " answer; \
    if [ "$$answer" != "y" ]; then \
        echo "Make stopped."; \
        exit 1; \
    fi



.PHONY: packages
packages:
	-@apt update
	-@apt install ${PACKAGES}


change_token:
	@$(MAKE) -s clear_tmp
	find server -type d -exec mkdir -p /tmp/cdmoj-make-stubs/{} \;
	find server -type f -exec sh -c "envsubst '\$$CONFDIR\$$SCRIPTSDIR\$$HTMLDIR\$$SERVERDIR\$$CONTESTSDIR'< {} >> /tmp/cdmoj-make-stubs/{}" \;

	find html -type d -exec mkdir /tmp/cdmoj-make-stubs/{} \;
	find html -type f -exec sh -c "envsubst '\$$CONFDIR\$$SCRIPTSDIR\$$HTMLDIR\$$SERVERDIR\$$CONTESTSDIR'< {} >> /tmp/cdmoj-make-stubs/{}" \;


install_html:
	mkdir -p $(HTMLDIR)
	-install -D -m 755 /tmp/cdmoj-make-stubs/html/* $(HTMLDIR)/
	install -D /tmp/cdmoj-make-stubs/html/cgi-bin/* -t $(HTMLDIR)/cgi-bin/
	install -D /tmp/cdmoj-make-stubs/html/images/* -t $(HTMLDIR)/images/
	install -D /tmp/cdmoj-make-stubs/html/js/* -t $(HTMLDIR)/js/
	install -D /tmp/cdmoj-make-stubs/html/self.d/* -t $(HTMLDIR)/self.d/

	-install -D /tmp/cdmoj-make-stubs/html/css/* -t $(HTMLDIR)/css/
	install -D /tmp/cdmoj-make-stubs/html/css/clarification/* -t $(HTMLDIR)/css/clarification

	install -o www-data -g www-data -m 755 -d $(CONTESTSDIR)
	install -d -m 777 $(HTMLDIR)/submissions
	install -d -m 777 $(HTMLDIR)/submissions-enviaroj


install_server:
	install -D /tmp/cdmoj-make-stubs/server/bin/* -t $(SERVERDIR)/bin/
	install -D /tmp/cdmoj-make-stubs/server/daemons/* -t $(SERVERDIR)/daemons/
	install -D /tmp/cdmoj-make-stubs/server/etc/* -t $(SERVERDIR)/etc/
	install -D /tmp/cdmoj-make-stubs/server/judge/* -t $(SERVERDIR)/judge/
	install -D /tmp/cdmoj-make-stubs/server/scripts/* -t $(SERVERDIR)/scripts/
	install -d -m 777 $(SERVERDIR)/jplag


apache_conf:
	envsubst '\$$CONFDIR\$$SCRIPTSDIR\$$HTMLDIR'< server/apache/apache2.conf >> /tmp/cdmoj-make-stubs/apache2.conf
	if ! grep -qF -x -f /tmp/cdmoj-make-stubs/apache2.conf /etc/apache2/apache2.conf; then \
		cat /tmp/cdmoj-make-stubs/apache2.conf >> /etc/apache2/apache2.conf; \
	fi

	envsubst '\$$CONFDIR\$$SCRIPTSDIR\$$HTMLDIR'< server/apache/moj.conf >> /tmp/cdmoj-make-stubs/moj.conf
	if ! grep -qF -x -f /tmp/cdmoj-make-stubs/moj.conf /etc/apache2/sites-available/moj.conf; then \
		cat /tmp/cdmoj-make-stubs/moj.conf >> /etc/apache2/sites-available/moj.conf; \
	fi

	envsubst '\$$CONFDIR\$$SCRIPTSDIR\$$HTMLDIR'< server/apache/serve-cgi-bin.conf >> /tmp/cdmoj-make-stubs/serve-cgi-bin.conf
	install -C -D /tmp/cdmoj-make-stubs/serve-cgi-bin.conf /etc/apache2/conf-available/serve-cgi-bin.conf
				# sed -i 's@ScriptAlias /cgi-bin/ /usr/lib/cgi-bin/@ScriptAlias /cgi-bin/  $HTMLDIR/cgi-bin/@g' /etc/apache2/conf-available/serve-cgi-bin.conf
				# sed -i 's@<Directory "/usr/lib/cgi-bin/">@<Directory "$HTMLDIR/cgi-bin/">@g' /etc/apache2/conf-available/serve-cgi-bin.conf

	ln -sf /etc/apache2/mods-available/cgi.load /etc/apache2/mods-enabled/cgi.load
	a2dissite 000-default	
	a2ensite moj
	systemctl reload apache2


.PHONY: clear_tmp
clear_tmp:
	-rm -r /tmp/cdmoj-make-stubs/server
	-rm -r /tmp/cdmoj-make-stubs/html
	-rm /tmp/cdmoj-make-stubs/apache2.conf
	-rm /tmp/cdmoj-make-stubs/moj.conf
	-rm /tmp/cdmoj-make-stubs/serve-cgi-bin.conf


.PHONY: message
message:
	@$(MAKE) -s clear_tmp
	@echo "\n\n\n\n\n====================================================================================\n"
	@echo "Please, make sure that $(SERVERDIR)/etc/judge.conf"
	@echo "contanis your spoj credencials."
	@echo "\n====================================================================================\n"
	@echo "Please, make sure that $(SERVERDIR)/scripts/sync-training.sh"
	@echo "contains a valid HOST and PORT"
	@echo "\n====================================================================================\n\n"


# Alvos do Makefile
all: confirm packages change_token install_html install_server apache_conf message

# Alvo padrão
.DEFAULT_GOAL := all