# Nubis project
#
# Build AMIs using packer

# Variables
RELEASE_FILE=packer/release.json

# Top level build targets
all: build

build: build-increment nubis-puppet packer

release: release-increment nubis-puppet packer

# Internal build targets
force: ;

nubis-puppet: force
	librarian-puppet install --path=nubis-puppet
	tar --exclude='nubis-puppet/.*' -zpcvf nubis-puppet.tar.gz nubis-puppet

release-increment:
	./bin/release.sh -f $(RELEASE_FILE) -r

build-increment:
	./bin/release.sh -f $(RELEASE_FILE)

packer: force
	packer build -var-file=packer/variables.json -var-file=$(RELEASE_FILE) packer/main.json