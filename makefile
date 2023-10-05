# Definição de variáveis
PREFIX := $(1)
HTMLDIR := $(2)

# Verifica se PREFIX e HTMLDIR foram especificados
ifeq ($(PREFIX),)
$(error PREFIX não especificado. Use 'make PREFIX=<path>')
endif

ifeq ($(HTMLDIR),)
$(error HTMLDIR não especificado. Use 'make HTMLDIR=<path>')
endif

# Alvos do Makefile
all: create_dirs \
	 copy_files \
	 copy_sample \
	 common_conf \
	 message \
	 apache_conf

create_dirs:
	mkdir -p "$(HTMLDIR)"
	mkdir -p "$(PREFIX)"
	
	mkdir -p "$(HTMLDIR)/contests"
	chown -R www-data:www-data $(HTMLDIR)/contests
	chown -R $(USER).$(USER) $(HTMLDIR)/contests

	mkdir -p "$(HTMLDIR)/submissions"
	sudo chmod 777 $(HTMLDIR)/submissions

	mkdir -p "$(PREFIX)/etc"
	mkdir -p "$(PREFIX)/jplag"

# copy_files:
# 	sed  -i -e "s;#CONFDIR#;$(PREFIX)/etc;g" \
# 		-e "s;#SCRIPTSDIR#;$(PREFIX)scripts;g" \
# 		-e "s;#BASEDIR#;$(PREFIX);g" \
# 		-e "s;#HTMLDIR#;$(HTMLDIR);g" \
# 		judge/*sh html/cgi-bin/*sh bin/*sh etc/* scripts/* daemons/*sh

# 	rsync -aHx --delete-during --exclude=contests html/ "$(HTMLDIR)"
# 	rsync -aHx --delete-during bin judge scripts daemons "$(PREFIX)"

copy_files:
	cp -r server/* $(PREFIX)
	cp -r html/* $(HTMLDIR)

	sed  -i -e "s;#CONFDIR#;$(PREFIX)/etc;g" \
		-e "s;#SCRIPTSDIR#;$(PREFIX)scripts;g" \
		-e "s;#BASEDIR#;$(PREFIX);g" \
		-e "s;#HTMLDIR#;$(HTMLDIR);g" \
		$(PREFIX)/judge/*sh $(PREFIX)/bin/*sh $(PREFIX)/etc/* $(PREFIX)/scripts/* $(PREFIX)/daemons/*sh $(HTMLDIR)/cgi-bin/*sh

copy_sample:
	cp -r contests/sample .
	tar cfj "$(HTMLDIR)/contests/sample.tar.bz2" sample
	rm -rf sample


# Alvo para copiar judge.conf se não existir
ifeq (,$(wildcard $(PREFIX)/etc/judge.conf))
	cp etc/judge.conf "$(PREFIX)/etc/judge.conf"
	chmod 600 "$(PREFIX)/etc/judge.conf"
endif

common_conf: 
ifeq ("$(wildcard $(PREFIX)/etc/common.conf)", "")
	@echo "CACHEDIR=/tmp/" >> $(PREFIX)/etc/common.conf
	@echo "CONTESTSDIR=$(HTMLDIR)/contests" >> $(PREFIX)/etc/common.conf
	@echo "SUBMISSIONDIR=$(HTMLDIR)/submissions" >> $(PREFIX)/etc/common.conf
	@echo "BASEURL='http://localhost'" >> $(PREFIX)/etc/common.conf
	@echo "HTMLDIR=$(HTMLDIR)" >> $(PREFIX)/etc/common.conf
	@echo "JPLAGDIR=$(PREFIX)/jplag" >> $(PREFIX)/etc/common.conf
	chmod 600 "$(PREFIX)/etc/common.conf"
endif


apache_conf:
ifneq ($(shell grep -q '<Directory $${HTMLDIR}' /etc/apache2/apache2.conf),)
	@echo "
	\n\n<Directory ${HTMLDIR}/> \n\
		Options +ExecCGI \n\
		AddHandler cgi-script .cgi .sh \n\
	</Directory>" >> /etc/apache2/apache2.conf
endif

	ln -sf /etc/apache2/mods-available/cgi.load /etc/apache2/mods-enabled/cgi.load

	sed -i 's@ScriptAlias /cgi-bin/ /usr/lib/cgi-bin/@ScriptAlias /cgi-bin/  ${HTMLDIR}/cgi-bin/@g' /etc/apache2/conf-available/serve-cgi-bin.conf
	sed -i 's@<Directory "/usr/lib/cgi-bin/">@<Directory "${HTMLDIR}/cgi-bin/">@g' /etc/apache2/conf-available/serve-cgi-bin.conf

ifneq ($(shell grep -q 'moj.com.br' /etc/apache2/sites-available/moj.conf),)
	@echo "
	<VirtualHost *:80> \n\
			ServerName moj.com.br \n\n\
			ServerAdmin webmaster@localhost \n\
			DocumentRoot ${HTMLDIR}  \n\n\
			ErrorLog \$${APACHE_LOG_DIR}/moj.com.br-error.log \n\
			CustomLog \$${APACHE_LOG_DIR}/moj.com.br-access.log combined \n\n\
			Include conf-available/serve-cgi-bin.conf \n\n\
			ScriptAlias /cgi-bin/ ${HTMLDIR}/cgi-bin/ \n\
		<Directory "/"> \n\
			Options Indexes FollowSymLinks MultiViews Includes \n\
			Require all granted \n\
		</Directory> \n\
	</VirtualHost> \n" >> /etc/apache2/sites-available/moj.conf
endif

	a2dissite 000-default
	a2ensite moj
	systemctl reload apache2

# Alvo de exibição de mensagem final
.PHONY: message
message:
	@echo "\n\n======================================================================"
	@echo "Please, make sure that $(PREFIX)/etc/judge.conf"
	@echo "contais your spoj credencials"
	@echo "======================================================================\n\n"

# Alvo padrão
.DEFAULT_GOAL := all