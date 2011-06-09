CURL	?= $(shell if test -f /usr/bin/curl ; then echo "curl -H Pragma: -O -R -S --fail --show-error" ; fi)
WGET	?= $(shell if test -f /usr/bin/wget ; then echo "wget -nd -m" ; fi)
CLIENT	?= $(if $(CURL),$(CURL),$(if $(WGET),$(WGET)))

sources:
	$(CLIENT) http://herlo.org/misc/pydf_9.tar.gz
	$(CLIENT) http://herlo.org/misc/MD5SUM

test: sources
	md5sum -c MD5SUM || echo 'MD5 check failed'

clean:
	rm pydf_9.tar.gz
