# -*- Makefile -*-
#
# Common Makefile for building RPMs
# Licensed under the new-BSD license (http://www.opensource.org/licenses/bsd-license.php)
# Copyright (C) 2004-2005 Red Hat, Inc.
# Copyright (C) 2005 Fedora Foundation
#
# $Id: Makefile.common,v 1.13 2010/03/21 01:36:40 laxathom Exp $

# Define the common dir.
# This needs to happen first.
define find-common-dir
for d in common ../common ../../common ; do if [ -f $$d/Makefile.common ] ; then echo "$$d"; break ; fi ; done
endef
COMMON_DIR := $(shell $(find-common-dir))

# Branch and disttag definitions
# These need to happen second.
ifndef HEAD_BRANCH
HEAD_BRANCH := devel
endif
BRANCH:=$(shell pwd | awk -F '/' '{ print $$NF }' )
BRANCHINFO = $(shell grep ^$(BRANCH): $(COMMON_DIR)/branches | cut -d: --output-delimiter=" " -f2-)
TARGET := $(word 1, $(BRANCHINFO))
DIST = $(word 2, $(BRANCHINFO))
DISTVAR = $(word 3, $(BRANCHINFO))
DISTVAL = $(word 4, $(BRANCHINFO))
DIST_DEFINES = --define "dist $(DIST)" --define "$(DISTVAR) $(DISTVAL)"

BUILD_FLAGS ?=  $(shell echo $(KOJI_FLAGS))


## a base directory where we'll put as much temporary working stuff as we can
ifndef WORKDIR
WORKDIR := $(shell pwd)
endif
## of course all this can also be overridden in your RPM macros file,
## but this way you can separate your normal RPM setup from your CVS
## setup. Override RPM_WITH_DIRS in ~/.cvspkgsrc to avoid the usage of
## these variables.
SRCRPMDIR ?= $(WORKDIR)
BUILDDIR ?= $(WORKDIR)
RPMDIR ?= $(WORKDIR)
MOCKDIR ?= $(WORKDIR)
ifeq ($(DISTVAR),epel)
DISTVAR := rhel
MOCKCFG ?= epel-$(DISTVAL)-$(BUILDARCH)-rpmfusion_free
else
MOCKCFG ?= fedora-$(DISTVAL)-$(BUILDARCH)-rpmfusion_free
## 4, 5, 6 need -core
ifeq ($(DISTVAL),4)
MOCKCFG = fedora-$(DISTVAL)-$(BUILDARCH)-core
endif
ifeq ($(DISTVAL),5)
MOCKCFG = fedora-$(DISTVAL)-$(BUILDARCH)-core
endif
ifeq ($(DISTVAL),6)
MOCKCFG = fedora-$(DISTVAL)-$(BUILDARCH)-core
endif
## Devel builds use -devel mock config
ifeq ($(BRANCH),devel)
MOCKCFG = fedora-rawhide-$(BUILDARCH)-rpmfusion_free
endif
endif

## SOURCEDIR is special; it has to match the CVS checkout directory, 
## because the CVS checkout directory contains the patch files. So it basically 
## can't be overridden without breaking things. But we leave it a variable
## for consistency, and in hopes of convincing it to work sometime.
ifndef SOURCEDIR
SOURCEDIR := $(shell pwd)
endif

ifndef RPM_DEFINES
RPM_DEFINES = --define "_sourcedir $(SOURCEDIR)" \
		--define "_builddir $(BUILDDIR)" \
		--define "_srcrpmdir $(SRCRPMDIR)" \
		--define "_rpmdir $(RPMDIR)" \
                $(DIST_DEFINES)
endif

# Initialize the variables that we need, but are not defined
# the version of the package
ifndef NAME
$(error "You can not run this Makefile without having NAME defined")
endif
ifndef VERSION
VERSION := $(shell rpm $(RPM_DEFINES) $(DIST_DEFINES) -q --qf "%{VERSION}\n" --specfile $(SPECFILE)| head -1)
endif
# the release of the package
ifndef RELEASE
RELEASE := $(shell rpm $(RPM_DEFINES) $(DIST_DEFINES) -q --qf "%{RELEASE}\n" --specfile $(SPECFILE)| head -1)
endif
# this is used in make patch, maybe make clean eventually.
# would be nicer to autodetermine from the spec file...
RPM_BUILD_DIR ?= $(BUILDDIR)/$(NAME)-$(VERSION)

## for secondary arch only packages we cant build on the primary hub
## we need to go direct to the secondary arch hub
define secondary-arch 
for name in silo prtconf lssbus afbinit xorg-x11-drv-sunbw2 xorg-x11-drv-suncg14 xorg-x11-drv-suncg3 xorg-x11-drv-suncg6 xorg-x11-drv-sunffb xorg-x11-drv-sunleo xorg-x11-drv-suntcx ; \
do if [ "$$name" = "$(NAME)" ]; then echo "-c ~/.koji/sparc-config"; fi \
done 
endef
SECONDARY_CONFIG := $(shell $(secondary-arch))

# default target: just make sure we've got the sources
all: sources

# user specific configuration
CVS_EXTRAS_RC	:= $(shell if test -f $(HOME)/.cvspkgsrc ; then echo $(HOME)/.cvspkgsrc ; fi)
ifdef CVS_EXTRAS_RC
include $(CVS_EXTRAS_RC)
endif

# The repository and the clients we use for the files
REPOSITORY ?= http://cvs.rpmfusion.org/repo/pkgs/free
UPLOAD_REPOSITORY ?= https://cvs.rpmfusion.org/repo/pkgs/upload.cgi

# We define CURL and WGET in a way that makes if possible to have them
# overwritten from the module's Makefiles. Then CLIENT picks CURL, otherwise WGET
CURL	?= $(shell if test -f /usr/bin/curl ; then echo "curl -H Pragma: -O -R -S --fail --show-error" ; fi)
WGET	?= $(shell if test -f /usr/bin/wget ; then echo "wget -nd -m" ; fi)
CLIENT	?= $(if $(CURL),$(CURL),$(if $(WGET),$(WGET)))
PLAGUE_CLIENT ?= $(shell which plague-client 2>/dev/null)
BUILD_CLIENT ?= $(shell which koji 2>/dev/null)

# RPM with all the overrides in place; you can override this in your
# .cvspkgsrc also, to use a default rpm setup
# the rpm build command line
ifndef RPM
RPM := $(shell if test -f /usr/bin/rpmbuild ; then echo rpmbuild ; else echo rpm ; fi)
endif
ifndef RPM_WITH_DIRS
RPM_WITH_DIRS = $(RPM) $(RPM_DEFINES)
endif

# CVS-safe version/release -- a package name like 4Suite screws things
# up, so we have to remove the leaving digits from the name
TAG_NAME    := $(shell echo $(NAME)    | sed -e s/\\\./_/g -e s/^[0-9]\\\+//g)
TAG_VERSION := $(shell echo $(VERSION) | sed s/\\\./_/g)
TAG_RELEASE := $(shell echo $(RELEASE) | sed s/\\\./_/g)

# tag to export, defaulting to current tag in the spec file
TAG?=$(TAG_NAME)-$(TAG_VERSION)-$(TAG_RELEASE)

# where to cvs export temporarily
TMPCVS := $(WORKDIR)/cvs-$(TAG)

# source file basenames
SOURCEFILES := $(shell cat sources 2>/dev/null | awk '{ print $$2 }')
# full path to source files
FULLSOURCEFILES := $(addprefix $(SOURCEDIR)/,$(SOURCEFILES))

# retrieve the stored md5 sum for a source download
define get_sources_md5
$(shell cat sources 2>/dev/null | while read m f ; do if test "$$f" = "$@" ; then echo $$m ; break ; fi ; done)
endef

# list the possible targets for valid arches
ARCHES = noarch i386 i586 i686 x86_64 ia64 s390 s390x ppc ppc64 pseries ppc64pseries iseries ppc64iseries athlon alpha alphaev6 sparc sparc64 sparcv9 sparcv9v sparc64v i164 mac sh mips geode

# for the modules that do different "make prep" depending on what arch we build for
PREP_ARCHES	= $(addprefix prep-,$(ARCHES))

## list all our bogus targets
.PHONY :: $(ARCHES) sources uploadsource upload export check build-check plague koji build cvsurl chain-build test-srpm srpm tag force-tag verrel new clean patch prep compile install-short compile-short FORCE local

# The TARGETS define is meant for local module targets that should be
# made in addition to the SOURCEFILES whenever needed
TARGETS		?=

# default target - retrieve the sources and make the module specific targets
sources: $(SOURCEFILES) $(TARGETS)

# Retrieve the sources we do not have in CVS
$(SOURCEFILES): #FORCE
	@mkdir -p $(SOURCEDIR)
	@echo "Downloading $@..."
	@for i in `find ../ -maxdepth 2 -name "$@"`; do \
	    if test "$$(md5sum $$i | awk '{print $$1}')" = "$(get_sources_md5)"  ; then \
		echo "Copying from $$i" ; \
	        ln $$i $@ ; \
		break ; \
	    fi ; \
	done 
	@if [ ! -e "$@" ] ; then $(CLIENT) $(REPOSITORY)/$(NAME)/$@/$(get_sources_md5)/$@  ; fi
	@if [ ! -e "$@" ] ; then echo "Could not download source file: $@ does not exist" ; exit 1 ; fi
	@if test "$$(md5sum $@ | awk '{print $$1}')" != "$(get_sources_md5)" ; then \
	    echo "md5sum of the downloaded $@ does not match the one from 'sources' file" ; \
	    echo "Local copy: $$(md5sum $@)" ; \
	    echo "In sources: $$(grep $@ sources)" ; \
	    exit 1 ; \
	else \
	    ls -l $@ ; \
	fi

# Support for uploading stuff into the repository. Since this is
# pretty specific to the upload.cgi we use, we hardwire the assumption
# that we're always using upload.cgi
ifdef FILES

# we hardwire curl in here because the upload rules are very dependent
# on curl's behavior on missing pages, ISEs, etc.
UPLOAD_CERT	   = $(shell if test -f $(HOME)/.rpmfusion.cert ; then echo " --cert $(HOME)/.rpmfusion.cert" ; fi)
UPLOAD_CHECK	   = curl -k $(UPLOAD_CERT) --fail --silent
UPLOAD_CLIENT	   = curl -k $(UPLOAD_CERT) --fail --show-error --progress-bar

upload-check = $(UPLOAD_CHECK) -F "tree=free" -F "name=$(NAME)" -F "md5sum=$${m%%[[:space:]]*}" -F "filename=$$f" $(UPLOAD_REPOSITORY)
upload-file  = $(UPLOAD_CLIENT) -F "tree=free" -F "name=$(NAME)" -F "md5sum=$${m%%[[:space:]]*}" -F "file=@$$f" $(UPLOAD_REPOSITORY)

define upload-request
echo "Checking : $$b on $(UPLOAD_REPOSITORY)..." ; \
check=$$($(upload-check)) ; retc=$$? ; \
if test $$retc -ne 0 ; then \
    echo "ERROR: could not check remote file status" ; \
    exit -1 ; \
elif test "$$check" = "Available" ; then \
    echo "This file ($$m) is already uploaded" ; \
elif test "$$check" = "Missing" ; then \
    echo "Uploading: $$b to $(UPLOAD_REPOSITORY)..." ; \
    $(upload-file) || exit 1 ; \
else  \
	echo "$$check" ; \
	exit 1 ; \
fi
endef

OPENSSL=$(shell which openssl 2>/dev/null)
define check-cert
	@if ! test -f $(HOME)/.rpmfusion.cert ; then echo "ERROR: You need to download your rpmfusion client certificate" >&2 ; echo "       from https://fas.rpmfusion.org/accounts/" >&2; exit 1 ; fi
	@if [ -x ${OPENSSL} ]; then \
	    ${OPENSSL} x509 -checkend 6000 -noout -in ${HOME}/.rpmfusion.cert ; \
	    if [ $$? -ne 0 ]; then \
	        echo "ERROR: Your rpmfusion client-side certificate expired." >&2 ; \
                echo "       You need to download a new client-side certificate" >&2 ; \
                echo "       from https://fas.rpmfusion.org/accounts/" >&2 ; \
                exit 1 ; \
	    fi ; \
	fi
endef

# Upload the FILES, adding to the ./sources manifest
upload: $(TREE) $(FILES)
	$(check-cert)
	@if ! test -f ./sources ; then touch ./sources ; fi
	@if ! test -f ./.cvsignore ; then touch ./.cvsignore ; fi
	@for f in $(FILES); do \
	    if ! test -s $$f ; then echo "SKIPPING EMPTY FILE: $$f" ; continue ; fi ; \
	    b="$$(basename $$f)" ; \
	    m="$$(cd $$(dirname $$f) && md5sum $$b)" ; \
	    if test "$$m" = "$$(grep $$b sources)" ; then \
	        echo "ERROR: file $$f is already listed in the sources file..." ; \
		exit 1 ; \
	    fi ; \
	    chmod +r $$f ; \
	    echo ; $(upload-request) ; echo ; \
	    if test -z "$$(egrep ""[[:space:]]$$b$$"" sources)" ; then \
	        echo "$$m" >> sources ; \
	    else \
	        egrep -v "[[:space:]]$$b$$" sources > sources.new ; \
	        echo "$$m" >> sources.new ; \
		mv sources.new sources ; \
	    fi ; \
	    if test -z "$$(egrep ""^$$b$$"" .cvsignore)" ; then \
	        echo $$b >> .cvsignore ; \
	    fi \
	done
	@if grep "^/sources/" CVS/Entries >/dev/null; then true ; else cvs -Q add sources; fi
	@echo "Source upload succeeded. Don't forget to commit the new ./sources file"
	@cvs update sources .cvsignore

# Upload FILES and recreate the ./sources file to include only these FILES
new-source new-sources: $(FILES)
	$(check-cert)
	@rm -f sources && touch sources
	@rm -f .cvsignore && touch .cvsignore
	@for f in $(FILES); do \
	    if ! test -s $$f ; then echo "SKIPPING EMPTY FILE: $$f" ; continue ; fi ; \
	    b="$$(basename $$f)" ; \
	    m="$$(cd $$(dirname $$f) && md5sum $$b)" ; \
	    chmod +r $$f ; \
	    echo ; $(upload-request) ; echo ; \
	    echo "$$m" >> sources ; \
	    echo "$$b" >> .cvsignore ; \
	done
	@if grep "^/sources/" CVS/Entries >/dev/null; then true ; else cvs -Q add sources; fi
	@echo "Source upload succeeded. Don't forget to commit the new ./sources file"
	@cvs update sources .cvsignore
endif

# allow overriding buildarch so you can do, say, an i386 build on x86_64
ifndef BUILDARCH
BUILDARCH := $(shell rpm --eval "%{_arch}")
endif

# test build in mock
mockbuild : srpm
	mock $(MOCKARGS) -r $(MOCKCFG) --resultdir=$(MOCKDIR)/$(TAG) $(SRCRPMDIR)/$(NAME)-$(VERSION)-$(RELEASE).src.rpm

# build for a particular arch
$(ARCHES) : sources $(TARGETS)
	$(RPM_WITH_DIRS) --target $@ -ba $(SPECFILE) 2>&1 | tee .build-$(VERSION)-$(RELEASE).log
	@exit ${PIPESTATUS[0]}

# empty target to force checking of md5sums in FULLSOURCEFILES
FORCE:

# build whatever's appropriate for the local architecture
local: $(if $(shell grep -i '^BuildArch:.*noarch' $(SPECFILE)), noarch, $(shell uname -m))

# attempt to apply all the patches, optionally only for a particular arch
ifdef PREPARCH
prep: sources $(TARGETS)
	$(RPM_WITH_DIRS) --nodeps -bp --target $(PREPARCH) $(SPECFILE)
else
prep: sources $(TARGETS)
	$(RPM_WITH_DIRS) --nodeps -bp $(SPECFILE)
endif

# this allows for make prep-i686, make prep-ppc64, etc
prep-% : Makefile
	$(MAKE) prep PREPARCH=$*

compile: sources $(TARGETS)
	$(RPM_WITH_DIRS) -bc $(SPECFILE)

compile-short: sources $(TARGETS)
	$(RPM_WITH_DIRS) --nodeps --short-circuit -bc $(SPECFILE)

install-short: sources $(TARGETS)
	$(RPM_WITH_DIRS) --nodeps --short-circuit -bi $(SPECFILE)

CVS_ROOT	:= $(shell if [ -f CVS/Root ] ; then cat CVS/Root ; fi)
CVS_REPOSITORY	:= $(shell if [ -f CVS/Repository ] ; then cat CVS/Repository ; fi)
CVS_URL		:= cvs://cvs.rpmfusion.org/cvs/pkgs?$(CVS_REPOSITORY)\#$(TAG)

## create a clean exported copy in $(TMPCVS)
export:: sources
	@mkdir -p $(WORKDIR)
	/bin/rm -rf $(TMPCVS)
	@if test -z "$(TAG)" ; then echo "Must specify a tag to check out" ; exit 1; fi
	@mkdir -p $(TMPCVS)
	@cd $(TMPCVS) && \
	    cvs -Q -d $(CVS_ROOT) export -r$(TAG) -d $(NAME) $(CVS_REPOSITORY) && \
	    cvs -Q -d $(CVS_ROOT) export -rHEAD common
	@if [ -n "$(FULLSOURCEFILES)" ]; then ln -f $(FULLSOURCEFILES) $(TMPCVS)/$(NAME) 2> /dev/null || cp -f $(FULLSOURCEFILES) $(TMPCVS)/$(NAME) ; fi
	@echo "Exported $(TMPCVS)/$(NAME)"

## build a test-srpm and see if it will -bp on all arches 
# XXX: I am not sure exactly what this is supposed to really do, since the
# query format returns (none) most of the time, and that is not
# handled --gafton
check: test-srpm
	@archs=`rpm -qp $(SRCRPMDIR)/$(NAME)-$(VERSION)-$(RELEASE).src.rpm --qf "[%{EXCLUSIVEARCH}\n]" | egrep -v "(i586)|(i686)|(athlon)"` ;\
	if test -z "$$archs"; then archs=noarch; fi ; \
	echo "Checking arches: $$archs" ; \
	for arch in $$archs; do \
	    echo "Checking $$arch..."; \
	    if ! $(RPM_WITH_DIRS) -bp --target $$arch $(SPECFILE); then \
		echo "*** make prep failed for $$arch"; \
		exit 1; \
	    fi; \
	done;

## use this to build an srpm locally
srpm: sources $(TARGETS)
	$(RPM_WITH_DIRS) $(DIST_DEFINES) --nodeps -bs $(SPECFILE)

test-srpm: srpm

verrel:
	@echo $(NAME)-$(VERSION)-$(RELEASE)

# If you build a new version into the tree, first do "make tag",
# then "make srpm", then build the package.  
tag::    $(SPECFILE) $(COMMON_DIR)/branches
	cvs tag $(TAG_OPTS) -c $(TAG)
	@echo "Tagged with: $(TAG)"
	@echo

force-tag: $(SPECFILE) $(COMMON_DIR)/branches
	@$(MAKE) tag TAG_OPTS="-F $(TAG_OPTS)"

define find-user
if [ `cat CVS/Root |grep -c [^:]@` -ne 0 ]; then cat CVS/Root  |cut -d @ -f 1 |  sed 's/:.*://' ; else echo $(USER); fi
endef
USER := $(shell $(find-user))

oldbuild:   $(COMMON_DIR)/branches
	@if [ -z "$(TARGET)" -a ! -d CVS ]; then echo "Must be in a branch subdirectory"; exit 1; fi

	@cvs status -v $(SPECFILE) 2>/dev/null | grep -q $(TAG); ret=$$? ;\
	if [ $$ret -ne 0 ]; then echo "$(SPECFILE) not tagged with tag $(TAG)"; exit 1;  fi	

	@(pushd $(COMMON_DIR) >/dev/null ;\
	rm -f tobuild ;\
	cvs -Q update -C tobuild ;\
	echo -e "$(USER)\t$(CVS_REPOSITORY)\t$(TAG)\t$(TARGET)" >> tobuild ;\
	cvs commit -m "request build of $(CVS_REPOSITORY) $(TAG) for $(TARGET)" tobuild ;\
	popd >/dev/null)

build-check: $(SPECFILE)
	@if [ -z "$(TARGET)" -o ! -d CVS ]; then echo "Must be in a branch subdirectory"; exit 1; fi
	@cvs -f status -v $(SPECFILE) 2>/dev/null | grep -q $(TAG); ret=$$? ;\
	if [ $$ret -ne 0 ]; then echo "$(SPECFILE) not tagged with tag $(TAG)"; exit 1;  fi

plague: build-check $(COMMON_DIR)/branches
	@if [ ! -x "$(PLAGUE_CLIENT)" ]; then echo "Must have plague-client installed - see http://rpmfusion.org/Buildsystem/PlagueUsage"; exit 1; fi
	PLAGUE_CLIENT_CONFIG=$(HOME)/.plague-client-rpmfusion.cfg $(PLAGUE_CLIENT) build $(NAME) $(TAG) $(TARGET)

koji: build-check $(COMMON_DIR)/branches
	@if [ ! -x "$(BUILD_CLIENT)" ]; then echo "Must have koji installed - see http://rpmfusion.org/Buildsystem/PlagueUsage"; exit 1; fi
	@$(BUILD_CLIENT) $(SECONDARY_CONFIG) build $(BUILD_FLAGS) $(TARGET) '$(CVS_URL)'

#ifneq (, $(filter devel F-7 OLPC-2, $(BRANCH)))
#build: koji
#else
build: plague
#endif

cvsurl:
	@echo '$(CVS_URL)'

chain-build: build-check
	@if [ -z "$(CHAIN)" ]; then \
                echo "Missing CHAIN variable, please specify the order of packages to" ; \
                echo "chain build.  For example:  make chain-build CHAIN='foo bar'" ; \
                exit 1 ; \
        fi ; \
        set -e ; \
        subdir=`basename $$(pwd)` ; \
        urls="" ; \
        for component in $(CHAIN) ; do \
                if [ "$$component" = "$(NAME)" ]; then \
                        echo "$(NAME) must not appear in CHAIN" ; \
                        exit 1 ; \
                fi ; \
                if [ "$$component" = ":" ]; then \
                        urls="$$urls :" ; \
                        continue ; \
                elif [ -n "$$urls" -a -z "$(findstring :,$(CHAIN))" ]; then \
                        urls="$$urls :" ; \
                fi ; \
                rm -rf .tmp-$$$$ ; \
                mkdir -p .tmp-$$$$ ; \
                pushd .tmp-$$$$ > /dev/null ; \
                cvs -f -Q -z 3 -d $(CVS_ROOT) co $$component ; \
                urls="$$urls `make -s -C $$component/$$subdir cvsurl`" ; \
                popd > /dev/null ; \
                rm -rf .tmp-$$$$ ; \
        done ; \
        if [ -z "$(findstring :,$(CHAIN))" ]; then \
                urls="$$urls :" ; \
        fi ; \
        urls="$$urls `make -s cvsurl`" ; \
        $(BUILD_CLIENT) chain-build $(BUILD_FLAGS) $(TARGET) $$urls

# "make new | less" to see what has changed since the last tag was assigned
new:
	-@cvs diff -u -r$$(cvs log Makefile 2>/dev/null | awk '/^symbolic names:$$/ {getline; sub(/^[ \t]*/, "") ; sub (/:.*$$/, ""); print; exit 0}')

# mop up, printing out exactly what was mopped.
clean ::
	@echo "Running the %clean script of the rpmbuild..."
	-@$(RPM_WITH_DIRS) --clean --nodeps $(SPECFILE)
	@for F in $(FULLSOURCEFILES); do \
                if test -e $$F ; then \
                        echo "Deleting $$F" ; /bin/rm -f $$F ; \
                fi; \
        done
	@if test -d $(TMPCVS); then \
		echo "Deleting CVS dir $(TMPCVS)" ; \
		/bin/rm -rf $(TMPCVS); \
	fi
	@if test -e $(SRCRPMDIR)/$(NAME)-$(VERSION)-$(RELEASE).src.rpm ; then \
		echo "Deleting $(SRCRPMDIR)/$(NAME)-$(VERSION)-$(RELEASE).src.rpm" ; \
		/bin/rm -f $(SRCRPMDIR)/$(NAME)-$(VERSION)-$(RELEASE).src.rpm ; \
        fi
	@rm -fv *~ clog
	@echo "Fully clean!"

# To prevent CVS noise due to changing file timestamps, upgrade
# to patchutils-0.2.23-3 or later, and add to ~/.cvspkgsrc:
#    FILTERDIFF := filterdiff --remove-timestamps
ifndef FILTERDIFF
FILTERDIFF := cat
endif

ifdef CVE
PATCHFILE := $(NAME)-$(VERSION)-CVE-$(CVE).patch
SUFFIX := cve$(shell echo $(CVE) | sed s/.*-//)
else
PATCHFILE := $(NAME)-$(VERSION)-$(SUFFIX).patch
endif

patch:
	@if test -z "$(SUFFIX)"; then echo "Must specify SUFFIX=whatever" ; exit 1; fi
	(cd $(RPM_BUILD_DIR)/.. && gendiff $(NAME)-$(VERSION) .$(SUFFIX) | $(FILTERDIFF)) > $(PATCHFILE) || true
	@if ! test -s $(PATCHFILE); then echo "Patch is empty!"; exit 1; fi
	@echo "Created $(PATCHFILE)"
	@grep "$(PATCHFILE)" CVS/Entries >&/dev/null || cvs add -ko $(PATCHFILE) || true

# Recreates the patch file of specified suffix from the current working sources
# but keeping any comments at the top of file intact, and backing up the old copy
# with a '~' suffix.
rediff:
	@if test -z "$(SUFFIX)"; then echo "Must specify SUFFIX=whatever" ; exit 1; fi
	@if ! test -f "$(PATCHFILE)"; then echo "$(PATCHFILE) not found"; exit 1; fi
	@mv -f $(PATCHFILE) $(PATCHFILE)\~
	@sed '/^--- /,$$d' < $(PATCHFILE)\~ > $(PATCHFILE)
	@(cd $(RPM_BUILD_DIR)/.. && gendiff $(NAME)-$(VERSION) .$(SUFFIX) | $(FILTERDIFF)) >> $(PATCHFILE) || true

clog: $(SPECFILE)
	@sed -n '/^%changelog/,/^$$/{/^%/d;/^$$/d;s/%%/%/g;p}' $(SPECFILE) | tee $@

help:
	@echo "Usage: make <target>"
	@echo "Available targets are:"
	@echo "	help			Show this text"
	@echo "	sources			Download source files [default]"
	@echo "	upload FILES=<files>	Add <files> to CVS"
	@echo "	new-sources FILES=<files>	Replace sources in CVS with <files>"
	@echo "	<arch>			Local test rpmbuild binary"
	@echo "	local			Local test rpmbuild binary"
	@echo "	prep			Local test rpmbuild prep"
	@echo "	compile			Local test rpmbuild compile"
	@echo "	compile-short		Local test rpmbuild short-circuit compile"
	@echo "	install-short		Local test rpmbuild short-circuit install"
	@echo "	export			Create clean export in \"cvs-$(TAG)\""
	@echo "	check			Check test srpm preps on all archs"
	@echo "	srpm			Create a srpm"
	@echo "	tag			Tag sources as \"$(TAG)\""
	@echo "	build			Request build of \"$(TAG)\" for $(TARGET)"
	@echo "	chain-build		Build current package in order with other packages"
	@echo "		example:  make chain-build CHAIN='libwidget libgizmo'"
	@echo "		The current package is added to the end of the CHAIN list."
	@echo "		Colons (:) can be used in the CHAIN parameter to define dependency groups."
	@echo "		Packages in a single group will be built in parallel, and all packages"
	@echo "		  in a group must build successfully and populate the repository before"
	@echo "		  the next group will begin building."
	@echo "		If no groups are defined, packages will be built sequentially."
	@echo "	mockbuild		Local test build using mock"
	@echo "	verrel			Echo \"$(NAME)-$(VERSION)-$(RELEASE)\""
	@echo "	new			Diff against last tag"
	@echo "	clog			Make a clog file containing top changelog entry"
	@echo "	clean			Remove srcs ($(SOURCEFILES)), export dir (cvs-$(TAG)) and srpm ($(NAME)-$(VERSION)-$(RELEASE).src.rpm)"
	@echo "	patch SUFFIX=<suff>	Create and add a gendiff patch file"
	@echo "	rediff SUFFIX=<suff>	Recreates a gendiff patch file, retaining comments"
	@echo "	unused-patches		Print list of patches not referenced by name in specfile"
	@echo "	unused-fedora-patches   Print rpmfusion patches not used by Patch and/or ApplyPatch directives"
	@echo "	gimmespec		Print the name of the specfile"

gimmespec:
	@echo "$(SPECFILE)"

unused-patches:
	@for f in *.patch; do if [ -e $$f ]; then grep -q $$f $(SPECFILE) || echo $$f; fi; done

unused-rpmfusion-patches:
	@for f in *.patch; do if [ -e $$f ]; then (egrep -q "^Patch[[:digit:]]+:[[:space:]]+$$f" $(SPECFILE) || echo "Unused:    $$f") && egrep -q "^ApplyPatch[[:space:]]+$$f" $(SPECFILE) || echo "Unapplied: $$f"; fi; done

##################### EXPERIMENTAL ##########################
# this stuff is very experimental in nature and should not be
# relied upon until these targets are moved above this line

# This section contains some hacks that instrument
# download-from-upstream support. You'll have to talk to gafton, he
# knows how this shit works.

# Add to the list of hardcoded upstream files the contents of the
# ./upstream file
UPSTREAM_FILES	+= $(shell if test -f ./upstream ; then cat ./upstream ; fi)
# extensions for signature files we need to retrieve for verification
# Warning: if you update the set of defaults, please make sure to
# update/add to the checking rules further down
UPSTREAM_CHECKS	?= sign asc sig md5

# check the signatures for the downloaded upstream stuff
UPSTREAM_CHECK_FILES = $(foreach e, $(UPSTREAM_CHECKS), $(addsuffix .$(e), $(UPSTREAM_FILES)))

# Download a file from a particular host.
# First argument contains the url base, the second the filename,
# third extra curl options
define download-host-file
if test ! -e "$(2)" ; then \
    echo -n "URL: $(1)/$(2) ..." ; \
    $(CURL) --silent --head $(1)/$(2) && \
        { \
	  echo "OK, downloading..." ; \
          $(CURL) $(3) $(1)/$(2) ; \
        } || \
	echo "not found" ; \
fi
endef

# Download a file, trying each mirror in sequence. Also check for
# signatures, if available
# First argument contains the file name. We read the list of mirrors
# from the ./mirrors file
define download-file
$(foreach h, $(shell cat mirrors), 
    $(call download-host-file,$(h),$(1))
    if test -e $(1) ; then \
        $(foreach e,$(UPSTREAM_CHECKS),$(call download-host-file,$(h),$(1).$(e),--silent) ; ) \
    fi
)
if test ! -e $(1) ; then \
    echo "ERROR: Could not download file: $(1)" ; \
    exit -1 ; \
else \
    echo "File $(1) available for local use" ; \
fi
endef

# Download all the UPSTREAM files
define download-files
$(foreach f, $(UPSTREAM_FILES),
    $(call download-file,$(f))
    echo
)
endef

# Make sure the signature files we download are properly added
define cvs-add-upstream-sigs
for s in $(UPSTREAM_CHECK_FILES) ; do \
    if test -f "$$s" ; then \
        if ! grep "^/$$s/" CVS/Entries >/dev/null 2>/dev/null ; then \
	    cvs -Q add "$$s" ; \
	fi ; \
    fi ; \
done
endef

download : upstream mirrors
	@$(download-files)
	$(MAKE) download-checks

download-checks :: import-upstream-gpg
download-checks :: $(UPSTREAM_CHECK_FILES)

# how to check for a gpg signature, given a separate signature file
define check-upstream-gpg-sig
echo -n "Checking GPG signature on $* from $@ : "
if ! test -f $@ ; then \
    echo "ERROR" ; echo "GPG signature file $@ not found" ; \
    exit 1 ; \
fi
if ! gpg --no-secmem-warning --no-permission-warning -q --verify $@ $* 2>/dev/null ; then \
    echo "FAILED" ; \
    exit 1 ; \
else \
    echo "OK" ; \
fi
endef

# how to check for a md5sum, given a separate .md5 file
define check-upstream-md5sum
echo -n "Checking md5sum on $* from $@ : "
if ! test -f $@ ; then \
    echo "ERROR" ; echo "md5sum file $@ not found" ; \
    exit 1 ; \
fi
if ! md5sum $* | diff >/dev/null --brief "$@" - ; then \
    echo "FAILED" ; \
    exit 1 ; \
else \
    echo "OK" ; \
fi
endef

# and now the rules, specific to each extension
$(addsuffix .sign,$(UPSTREAM_FILES)): %.sign: % FORCE
	@$(check-upstream-gpg-sig)
$(addsuffix .asc,$(UPSTREAM_FILES)): %.asc: % FORCE
	@$(check-upstream-gpg-sig)
$(addsuffix .sig,$(UPSTREAM_FILES)): %.sig: % FORCE
	@$(check-upstream-gpg-sig)
$(addsuffix .md5,$(UPSTREAM_FILES)): %.md5: % FORCE
	@$(check-upstream-md5sum)

# We keep all the relevant GPG keys in the upstream-key.gpg so we can
# check the signatures...
import-upstream-gpg : upstream-key.gpg FORCE
	mkdir -p $(HOME)/.gnupg
	gpg --quiet --import --no-secmem-warning --no-permission-warning $< || :

# A handy target to download the latest and greatest from upstream and
# check it into the lookaside cache.
# new-base assumes that all the sources are downloaded from upstream, so it uses "make new-source"
# rebase uses the standard "make upload"
new-base : clean download
	$(MAKE) new-source FILES="$(UPSTREAM_FILES)"
	@$(cvs-add-upstream-sigs)
	@echo "Don't forget to do a 'cvs commit' for your new sources file."

rebase : clean download
	$(MAKE) upload FILES="$(UPSTREAM_FILES)"
	@$(cvs-add-upstream-sigs)
	@echo "Don't forget to do a 'cvs commit' for your new sources file."

# there is more stuff to clean, now that we have upstream files
clean ::
	@rm -fv $(UPSTREAM_FILES)
