CURL	?= $(shell if test -f /usr/bin/curl ; then echo "curl -H Pragma: -O -R -S --fail --show-error" ; fi)
WGET	?= $(shell if test -f /usr/bin/wget ; then echo "wget -nd -m" ; fi)
CLIENT	?= $(if $(CURL),$(CURL),$(if $(WGET),$(WGET)))

sources:
	$(CLIENT) http://herlo.org/misc/pydf_9.tar.gz
	$(CLIENT) http://herlo.org/misc/archive
	md5sum -c archive || ( echo 'MD5 check failed' ; exit 1 )

clean:
	rm pydf_9.tar.gz
