# Definição de variáveis
SERVERDIR := $(1)
HTMLDIR := $(2)

# Verifica se SERVERDIR e HTMLDIR foram especificados
ifeq ($(SERVERDIR),)
$(error SERVERDIR não especificado. Use 'make SERVERDIR=<path>')
endif

ifeq ($(HTMLDIR),)
$(error HTMLDIR não especificado. Use 'make HTMLDIR=<path>')
endif

export BASEDIR=$(SERVERDIR)
export CONFDIR=$(SERVERDIR)/etc
export SCRIPTSDIR=$(SERVERDIR)/scripts
export HTMLDIR=$(HTMLDIR)"

.PHONY: packages
packages:
	apt install gcc git apache2 rsync xclip curl default-jre default-jdk openjdk-17-jre openjdk-17-jdk


change_token:
	find server -type d -exec mkdir -p /tmp/{} \;
	find server -type f -exec sh -c "envsubst '\$$BASEDIR\$$CONFDIR\$$SCRIPTSDIR\$$HTMLDIR'< {} >> /tmp/{}" \;

	find html -type d -exec mkdir /tmp/{} \;
	find html -type f -exec sh -c "envsubst '\$$BASEDIR\$$CONFDIR\$$SCRIPTSDIR\$$HTMLDIR'< {} >> /tmp/{}" \;


install_html:
	mkdir -p $(HTMLDIR)
	-install -D -m 755 /tmp/html/* $(HTMLDIR)/
	install -D /tmp/html/cgi-bin/* -t $(HTMLDIR)/cgi-bin/
	install -D /tmp/html/images/* -t $(HTMLDIR)/images/
	install -D /tmp/html/js/* -t $(HTMLDIR)/js/
	install -D /tmp/html/self.d/* -t $(HTMLDIR)/self.d/

	-install -D /tmp/html/css/* -t $(HTMLDIR)/css/
	install -D /tmp/html/css/clarification/* -t $(HTMLDIR)/css/clarification

	install -o www-data -g www-data -m 755 -d $(HTMLDIR)/contests
	install -d -m 777 $(HTMLDIR)/submissions
	install -d -m 777 $(HTMLDIR)/jplag


install_server:
	install -D /tmp/server/bin/* -t $(SERVERDIR)/bin/
	install -D /tmp/server/daemons/* -t $(SERVERDIR)/daemons/
	install -D /tmp/server/etc/* -t $(SERVERDIR)/etc/
	install -D /tmp/server/judge/* -t $(SERVERDIR)/judge/
	install -D /tmp/server/scripts/* -t $(SERVERDIR)/scripts/


apache_conf:
	envsubst '\$$BASEDIR\$$CONFDIR\$$SCRIPTSDIR\$$HTMLDIR'< apache/apache2.conf >> /tmp/apache2.conf
	if ! grep -qF -x -f /tmp/apache2.conf /etc/apache2/apache2.conf; then \
		cat /tmp/apache2.conf >> /etc/apache2/apache2.conf; \
	fi

	envsubst '\$$BASEDIR\$$CONFDIR\$$SCRIPTSDIR\$$HTMLDIR'< apache/moj.conf >> /tmp/moj.conf
	if ! grep -qF -x -f /tmp/moj.conf /etc/apache2/sites-available/moj.conf; then \
		cat /tmp/moj.conf >> /etc/apache2/sites-available/moj.conf; \
	fi

	envsubst '\$$BASEDIR\$$CONFDIR\$$SCRIPTSDIR\$$HTMLDIR'< apache/serve-cgi-bin.conf >> /tmp/serve-cgi-bin.conf
	install -C -D /tmp/serve-cgi-bin.conf /etc/apache2/conf-available/serve-cgi-bin.conf
				# sed -i 's@ScriptAlias /cgi-bin/ /usr/lib/cgi-bin/@ScriptAlias /cgi-bin/  $HTMLDIR/cgi-bin/@g' /etc/apache2/conf-available/serve-cgi-bin.conf
				# sed -i 's@<Directory "/usr/lib/cgi-bin/">@<Directory "$HTMLDIR/cgi-bin/">@g' /etc/apache2/conf-available/serve-cgi-bin.conf

	ln -sf /etc/apache2/mods-available/cgi.load /etc/apache2/mods-enabled/cgi.load
	a2dissite 000-default	
	a2ensite moj
	systemctl reload apache2

.PHONY: clear_tmp
clear_tmp:
	-rm -r /tmp/server
	-rm -r /tmp/html
	-rm /tmp/apache2.conf
	-rm /tmp/moj.conf
	-rm /tmp/serve-cgi-bin.conf

.PHONY: message
message:
	$(MAKE) -s clear_tmp
	@echo "\n\n\n\n\n======================================================================"
	@echo "Please, make sure that $(SERVERDIR)/etc/judge.conf"
	@echo "contanis your spoj credencials"
	@echo "======================================================================\n\n"


# Alvos do Makefile
all: clear_tmp change_token install_html install_server apache_conf message

# Alvo padrão
.DEFAULT_GOAL := all
