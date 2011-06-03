CLIENT := $(shell which curl)

sources:
	 $(CLIENT) http://herlo.org/misc/pydf_9.tar.gz

clean:
	rm pydf_9.tar.gz
