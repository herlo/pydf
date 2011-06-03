ifndef WORKDIR
	WORKDIR := $(shell pwd)
endif

sources:
	$(CLIENT) http://herlo.org/misc/pydf_9.tar.gz

clean:
	rm pydf_9.tar.gz
